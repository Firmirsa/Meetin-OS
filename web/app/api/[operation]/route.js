import { ApiError, execute } from '../../../lib/integrations.mjs';
import { agentAccess, prepareTask, detectTasks, executeTask, trelloExecutionStatus } from '../../../lib/agent.mjs';

export async function POST(request, { params }) {
  try {
    if (!request.headers.get('content-type')?.startsWith('application/json')) {
      throw new ApiError(415, 'Format de requête invalide.');
    }
    const auth = request.headers.get('authorization');
    const token = auth?.startsWith('Bearer ') ? auth.slice(7) : undefined;
    const reader = request.body?.getReader();
    const decoder = new TextDecoder();
    let raw = '';
    let bytes = 0;
    if (reader) {
      try {
        while (true) {
          const {done, value} = await reader.read();
          if (done) break;
          bytes += value.byteLength;
          if (bytes > 24_000) {
            void reader.cancel().catch(() => {});
            throw new ApiError(413, 'Requête trop longue.');
          }
          raw += decoder.decode(value, {stream: true});
        }
        raw += decoder.decode();
      } finally {
        reader.releaseLock();
      }
    }
    let body;
    try { body = JSON.parse(raw); }
    catch { throw new ApiError(400, 'Requête invalide.'); }
    const { operation } = await params;
    let result;
    if (operation === 'agent-access') result = agentAccess(token);
    else if (operation === 'agent-prepare') result = await prepareTask(body, token);
    else if (operation === 'agent-detect') result = await detectTasks(body, token);
    else if (operation === 'agent-execute') result = await executeTask(body, token);
    else if (operation === 'agent-trello-status') result = await trelloExecutionStatus(body, token);
    else result = await execute(operation, body, token);
    return Response.json(result, { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) {
    const expected = error instanceof ApiError;
    return Response.json({ error: expected ? error.message : 'Cette action a échoué.', code: expected ? error.code : undefined }, {
      status: expected ? error.status : 500,
      headers: { 'Cache-Control': 'no-store' },
    });
  }
}
