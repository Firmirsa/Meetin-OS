import { requireUser, providerKey } from './hosted-account.mjs';
import { ApiError, input, searchLinkup } from './integrations.mjs';

export async function research(body, token, env = process.env, fetcher = fetch) {
  await requireUser(token, env, fetcher);
  const query = input(body?.query, 500);
  const key = await providerKey('linkup', env, fetcher);
  if (!key) throw new ApiError(503, 'La recherche Linkup doit être activée par l’équipe Meetin-OS.');
  return searchLinkup({query}, {...env, LINKUP_API_KEY: key}, fetcher);
}
