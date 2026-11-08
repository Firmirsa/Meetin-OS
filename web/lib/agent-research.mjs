import { requireUser } from './hosted-account.mjs';
import { searchLinkup } from './integrations.mjs';

export async function research(body, token, env = process.env, fetcher = fetch) {
  await requireUser(token, env, fetcher);
  return searchLinkup(body, env, fetcher);
}
