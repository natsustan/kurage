import { StreamsClient } from '@loro-dev/streams-client';

// Lody's machine control requests travel through short-lived JSON Streams.
// Keep the response stream private to this request, including when a refresh
// is cancelled, so replies cannot leak into another workspace or account.
export async function requestMachine(repoAccess, workspaceID, machineID, method, params, signal, timeoutMs = 120000) {
  const controller = new AbortController();
  const requestSignal = signal ? AbortSignal.any([signal, controller.signal]) : controller.signal;
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await exchange(repoAccess, workspaceID, machineID, method, params, requestSignal, timeoutMs);
  } finally {
    clearTimeout(timeout);
    controller.abort();
  }
}

async function exchange(repoAccess, workspaceID, machineID, method, params, signal, timeoutMs) {
  const responseID = `${workspaceID}:rpc:res:${crypto.randomUUID()}`;
  const requestID = crypto.randomUUID();
  const stream = id => new StreamsClient({
    url: `${repoAccess.baseURL.replace(/\/+$/, '')}/ds/lody/${encodeURIComponent(id)}`,
    auth: repoAccess.auth,
    fetch: (input, init) => globalThis.fetch(input, {
      ...init, signal: init?.signal ? AbortSignal.any([init.signal, signal]) : signal,
    }),
  });
  const response = stream(responseID);
  const created = await response.create({ contentType: 'application/json', ttlSeconds: 86400 });
  if (!created.ok) throw new Error('Could not open a machine response stream');
  signal.throwIfAborted();

  const reply = (async () => {
    // This stream was just created for this call. Read from the beginning so a
    // fast machine reply cannot beat the first SSE connection.
    for await (const event of response.live({ offset: '-1', mode: 'sse', signal })) {
      if (event.type === 'error') throw new Error('Machine response stream failed');
      if (event.type !== 'data') continue;
      const messages = event.payload.json();
      for (const message of Array.isArray(messages) ? messages : [messages]) {
        if (message?.id !== requestID) continue;
        if (message.error) throw new Error(message.error.message ?? 'Machine request failed');
        return message.result;
      }
    }
    throw new Error('Machine response stream closed');
  })();
  // The live read can reject while append is still pending.
  void reply.catch(() => {});

  const now = Date.now();
  const envelope = {
    jsonrpc: '2.0', id: requestID, method, rpcVersion: '1',
    machineId: machineID, workspaceId: workspaceID, replyTo: responseID,
    sentAt: now, expiresAt: now + timeoutMs, params,
  };
  const appended = await stream(`${workspaceID}:rpc:req:${machineID}`).append({
    part: { contentType: 'application/json', body: JSON.stringify(envelope) },
  });
  if (!appended.ok) throw new Error('Could not append machine request');
  return await reply;
}
