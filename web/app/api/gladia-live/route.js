import { experimental_upgradeWebSocket } from '@vercel/functions';
import { bearer, requireUser } from '../../../lib/hosted-account.mjs';
import { relayGladia } from '../../../lib/gladia-relay.mjs';
import { respond } from '../../../lib/hosted-response.mjs';

export const runtime = 'nodejs';
export const maxDuration = 300;

export async function GET(request) {
  if (request.headers.get('upgrade')?.toLowerCase() !== 'websocket') {
    return new Response(null, {status: 426});
  }
  let user;
  try { user = await requireUser(bearer(request.headers)); }
  catch (error) { return respond(() => { throw error; }); }
  return experimental_upgradeWebSocket(socket => relayGladia(socket, user));
}
