import { ApiError } from './integrations.mjs';

const headers = {'Cache-Control': 'no-store'};

export async function respond(action) {
  try {
    return Response.json(await action(), {headers});
  } catch (error) {
    return Response.json({
      error: error instanceof ApiError ? error.message : 'Le service Meetin-OS est momentanément indisponible.',
      code: error instanceof ApiError ? error.code : undefined,
    }, {headers, status: error instanceof ApiError ? error.status : 503});
  }
}

export async function boundedBody(request, limit) {
  if (Number(request.headers.get('content-length')) > limit) throw new ApiError(413, 'Requête trop longue.');
  if (!request.body) return Buffer.alloc(0);
  const reader = request.body.getReader();
  let bytes = 0;
  const chunks = [];
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      bytes += value.length;
      if (bytes > limit) {
        void reader.cancel().catch(() => {});
        throw new ApiError(413, 'Requête trop longue.');
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  return Buffer.concat(chunks, bytes);
}
