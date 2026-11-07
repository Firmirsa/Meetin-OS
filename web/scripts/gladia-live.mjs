import { createServer } from 'node:http';
import { WebSocketServer } from 'ws';
import { requireUser } from '../lib/hosted-account.mjs';
import { relayGladia } from '../lib/gladia-relay.mjs';

const server = createServer((request, response) => response.writeHead(426).end());
const sockets = new WebSocketServer({noServer: true, maxPayload: 64_000});
server.on('upgrade', async (request, socket, head) => {
  const stop = () => socket.destroy();
  socket.once('error', stop);
  try {
    if (request.url !== '/api/gladia-live') return stop();
    const user = await requireUser(request.headers.authorization?.match(/^Bearer (.+)$/)?.[1]);
    socket.removeListener('error', stop);
    sockets.handleUpgrade(request, socket, head, client => relayGladia(client, user));
  } catch {
    socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
  }
});
server.listen(Number(process.env.MEETIN_GLADIA_LIVE_PORT || 3001), '127.0.0.1');
