import { batchResult, startBatch } from '../../../lib/gladia-hosted.mjs';
import { respond } from '../../../lib/hosted-response.mjs';

export function POST(request) { return respond(() => startBatch(request)); }
export function GET(request) { return respond(() => batchResult(request)); }
