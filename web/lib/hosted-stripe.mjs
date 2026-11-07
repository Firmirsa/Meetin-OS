import Stripe from 'stripe';
import { ApiError, safeURL, setting } from './integrations.mjs';
import { accountQuota, requireUser, rpc, uuid } from './hosted-account.mjs';

const subscriptionEvents = new Set([
  'customer.subscription.created', 'customer.subscription.updated', 'customer.subscription.deleted',
  'customer.subscription.paused', 'customer.subscription.resumed',
]);

function billing(env) {
  const key = setting(env, 'STRIPE_SECRET_KEY');
  if (!/^(sk|rk)_(test|live)_/.test(key)) throw new ApiError(503, 'Stripe est indisponible.');
  return {
    client: new Stripe(key, {apiVersion: '2025-03-31.basil', maxNetworkRetries: 1, timeout: 10_000}),
    live: /^(sk|rk)_live_/.test(key),
    price: setting(env, 'STRIPE_PRICE_ID'),
    webhookSecret: setting(env, 'STRIPE_WEBHOOK_SECRET'),
  };
}

function returnURL(env) {
  let site;
  try { site = new URL(env.MEETIN_WEB_URL); } catch { throw new ApiError(503, 'L’adresse de Meetin-OS reste à configurer.'); }
  const local = site.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(site.hostname);
  if ((!local && site.protocol !== 'https:') || site.username || site.password) {
    throw new ApiError(503, 'L’adresse de Meetin-OS reste à configurer.');
  }
  return new URL('/onboarding#subscription', site).href;
}

export async function accountBilling(body, token, env = process.env, fetcher = fetch, config = billing) {
  const user = await requireUser(token, env, fetcher);
  const quota = await accountQuota(user, env, fetcher);
  const {client, price} = config(env);
  const back = returnURL(env);
  if (body?.action === 'manage') {
    if (!quota.customerId) throw new ApiError(409, 'Aucun abonnement à gérer.');
    const portal = await client.billingPortal.sessions.create({customer: quota.customerId, return_url: back});
    const url = safeURL(portal.url, 'billing.stripe.com');
    if (!url) throw new ApiError(502, 'Le portail Stripe est indisponible.');
    return {url};
  }
  if (body?.action !== 'checkout') throw new ApiError(400, 'Action d’abonnement inconnue.');
  if (quota.plan === 'premium') throw new ApiError(409, 'Votre plan Premium est déjà actif.');
  const success = new URL(back);
  success.searchParams.set('checkout', 'returned');
  const cancel = new URL(back);
  cancel.searchParams.set('checkout', 'canceled');
  const session = await client.checkout.sessions.create({
    mode: 'subscription',
    ...(quota.customerId ? {customer: quota.customerId} : {customer_email: user.email}),
    client_reference_id: user.id,
    subscription_data: {metadata: {meetin_user_id: user.id}},
    line_items: [{price, quantity: 1}],
    success_url: success.href, cancel_url: cancel.href,
  }, {idempotencyKey: `meetin-premium-${user.id}-${Math.floor(Date.now() / 1_800_000)}`});
  const url = safeURL(session.url, 'checkout.stripe.com');
  if (!url) throw new ApiError(502, 'Stripe n’a pas renvoyé de lien de paiement.');
  return {url};
}

export async function stripeWebhook(raw, signature, env = process.env, fetcher = fetch, config = billing) {
  if (typeof signature !== 'string') throw new ApiError(400, 'Signature Stripe absente.');
  const {client, live, price, webhookSecret} = config(env);
  let event;
  try { event = client.webhooks.constructEvent(raw, signature, webhookSecret); }
  catch { throw new ApiError(400, 'Signature Stripe invalide.'); }
  if (event.livemode !== live) throw new ApiError(400, 'Environnement Stripe inattendu.');
  const object = event.data.object;
  const id = subscriptionEvents.has(event.type) ? object.id :
    event.type === 'checkout.session.completed' && object.mode === 'subscription' ? object.subscription : null;
  if (typeof id !== 'string' || !/^sub_[a-zA-Z0-9]+$/.test(id)) return {received: true};

  // A delayed event still reads the subscription's current state from Stripe.
  const observedAt = new Date().toISOString();
  const subscription = await client.subscriptions.retrieve(id);
  const user = subscription.metadata?.meetin_user_id;
  if (subscription.livemode !== live || !uuid.test(user ?? '') || typeof subscription.customer !== 'string') {
    return {received: true};
  }
  const item = subscription.items?.data?.find(line => line.price?.id === price && line.quantity > 0);
  const ends = item?.current_period_end ?? subscription.current_period_end;
  const active = item && ['active', 'trialing'].includes(subscription.status) && Number.isFinite(ends);
  await rpc('meetin_sync_subscription', {
    p_id: id, p_user: user, p_customer: subscription.customer,
    p_premium_until: active ? new Date(ends * 1000).toISOString() : null,
    p_event_time: event.created, p_observed_at: observedAt,
  }, env, fetcher);
  return {received: true};
}
