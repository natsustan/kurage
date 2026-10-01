import assert from 'node:assert/strict';
import test from 'node:test';
import { requestMachine } from './machine-rpc.mjs';
import { control } from './mention-skills.mjs';

function harness(t, reply = true) {
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  const calls = [];
  let liveController;
  let envelope;
  let replyQueued = false;
  let cancelled = false;
  const deliver = () => {
    if (!reply || !liveController || !envelope || replyQueued) return;
    replyQueued = true;
    const messages = [
      { jsonrpc: '2.0', id: 'unrelated', result: { unrelated: true } },
      { jsonrpc: '2.0', id: envelope.id, result: { applied: true } },
    ];
    liveController.enqueue(new TextEncoder().encode(
      `event: data\ndata: ${JSON.stringify(messages)}\n\nevent: control\ndata: {"streamNextOffset":"1","upToDate":true}\n\n`));
  };
  globalThis.fetch = async (input, init) => {
    const url = new URL(input);
    calls.push({ url, init });
    if (init.method === 'PUT') {
      return new Response(null, { status: 201, headers: {
        'Stream-Next-Offset': '0', 'Content-Type': 'application/json',
      } });
    }
    if (init.method === 'GET') {
      const body = new ReadableStream({
        start(controller) { liveController = controller; deliver(); },
        cancel() { cancelled = true; },
      });
      return new Response(body, { headers: { 'Content-Type': 'text/event-stream' } });
    }
    assert.equal(init.method, 'POST');
    envelope = JSON.parse(new TextDecoder().decode(init.body));
    deliver();
    return new Response(null, { status: 200, headers: { 'Stream-Next-Offset': '1' } });
  };
  return { calls, envelope: () => envelope, cancelled: () => cancelled };
}

const access = { baseURL: 'https://gateway.example/', auth: async () => 'test-token' };

test('steer uses the workspace machine request stream and correlates a private live reply', async t => {
  const state = harness(t);
  const params = { sessionId: 'chat', expectedTurnId: 'assistant', userTurnId: 'guide',
    userId: 'user', timestamp: 'time', inputConfig: { prompt: 'Guidance' } };
  assert.deepEqual(await requestMachine(access, 'workspace', 'machine', 'session/steer', params,
    new AbortController().signal, 5000), { applied: true });
  const envelope = state.envelope();
  assert.equal(envelope.method, 'session/steer');
  assert.equal(envelope.workspaceId, 'workspace');
  assert.equal(envelope.machineId, 'machine');
  assert.deepEqual(envelope.params, params);
  assert.equal(envelope.expiresAt - envelope.sentAt, 5000);
  assert(envelope.replyTo.startsWith('workspace:rpc:res:'));
  const request = state.calls.find(call => call.init.method === 'POST');
  assert.equal(decodeURIComponent(request.url.pathname), '/ds/lody/workspace:rpc:req:machine');
  const live = state.calls.find(call => call.init.method === 'GET');
  assert.equal(live.url.searchParams.get('offset'), '-1');
  assert.equal(new Headers(request.init.headers).get('Authorization'), 'Bearer test-token');
  assert(state.calls.every(call => call.init.signal.aborted));
  assert(state.cancelled());
});

test('deadline closes the private response reader without retrying the application request', async t => {
  const state = harness(t, false);
  await assert.rejects(requestMachine(access, 'workspace', 'machine', 'session/steer', {},
    new AbortController().signal, 40), /closed|failed|aborted/i);
  assert.equal(state.calls.filter(call => call.init.method === 'POST').length, 1);
  assert(state.cancelled());
});

test('caller cancellation stops the response reader and keeps requests isolated', async t => {
  const state = harness(t, false);
  const controller = new AbortController();
  const request = requestMachine(access, 'workspace-two', 'machine', 'session/steer', {}, controller.signal);
  const rejection = assert.rejects(request, /closed|failed|aborted/i);
  while (!state.envelope()) await new Promise(resolve => setTimeout(resolve, 0));
  controller.abort();
  await rejection;
  assert(state.envelope().replyTo.startsWith('workspace-two:rpc:res:'));
  assert(state.cancelled());
});

test('existing local project controls retain their RPC method and nested request', async t => {
  const state = harness(t);
  const request = { type: 'local-project/list-skills', localProjectId: 'project' };
  await control(access, 'workspace', 'machine', request, new AbortController().signal);
  assert.equal(state.envelope().method, 'local-project/control');
  assert.deepEqual(state.envelope().params, { request });
});
