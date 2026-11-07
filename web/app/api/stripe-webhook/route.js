import { boundedBody, respond } from '../../../lib/hosted-response.mjs';
import { stripeWebhook } from '../../../lib/hosted-stripe.mjs';

export function POST(request) {
  return respond(async () => stripeWebhook(
    await boundedBody(request, 256_000), request.headers.get('stripe-signature')
  ));
}
