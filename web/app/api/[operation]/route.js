import { ApiError, execute } from '../../../lib/integrations.mjs';
import { agentAccess, prepareTask, detectTasks, executeTask, trelloExecutionStatus } from '../../../lib/agent.mjs';
import { accountAuth, accountStatus, agentEnvironment, bearer } from '../../../lib/hosted-account.mjs';
import { boundedBody } from '../../../lib/hosted-response.mjs';
import { accountBilling } from '../../../lib/hosted-stripe.mjs';

export async function POST(request, { params }) {
  try {
    if (!request.headers.get('content-type')?.startsWith('application/json')) {
      throw new ApiError(415, 'Format de requête invalide.');
    }
    const token = bearer(request.headers);
    const raw = await boundedBody(request, 24_000);
    let body;
    try { body = JSON.parse(raw); }
    catch { throw new ApiError(400, 'Requête invalide.'); }
    const { operation } = await params;
    let result;
    if (operation === 'account-auth') result = await accountAuth(body, token);
    else if (operation === 'account-status') result = await accountStatus(token);
    else if (operation === 'account-billing') result = await accountBilling(body, token);
    else if (['agent-access', 'agent-prepare', 'agent-detect', 'agent-execute', 'agent-trello-status'].includes(operation)) {
      const { userId, providerEnv } = await agentEnvironment(operation, token);
      if (operation === 'agent-access') result = agentAccess(providerEnv);
      else if (operation === 'agent-prepare') result = await prepareTask(body, userId, providerEnv);
      else if (operation === 'agent-detect') result = await detectTasks(body, userId, providerEnv);
      else if (operation === 'agent-execute') result = await executeTask(body, userId, providerEnv);
      else result = await trelloExecutionStatus(body, userId, providerEnv);
    }
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
