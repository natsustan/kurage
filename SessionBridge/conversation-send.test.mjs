import assert from 'node:assert/strict';
import test from 'node:test';
import { LoroDoc } from 'loro-crdt';
import { sendText } from './conversation-send.mjs';

function fixture() {
  const doc = new LoroDoc();
  const meta = {
    userId: 'user', cliType: 'codex', agentType: 'codex', status: { type: 'idle' },
  };
  const calls = [];
  const repo = {
    listDoc: async () => [{ docId: 'session-chat', meta }],
    getDocMeta: async () => ({ meta }),
    openPersistedDoc: async () => ({ doc }),
    sync: async options => { calls.push(options); return { outcome: 'synced' }; },
    upsertDocMeta: async (_id, patch) => { Object.assign(meta, patch); },
  };
  return { repo, doc, meta, calls };
}

test('a text turn syncs before its dispatch pointer and retry keeps one ID', async () => {
  const { repo, doc, meta, calls } = fixture();
  const timestamp = '2026-09-24T12:00:00.000Z';
  assert.equal(await sendText(repo, 'chat', 'turn-1', 'current-user', 'Hello', timestamp), 'sent');
  const entry = doc.getList('history').toJSON()[0];
  assert.equal(entry.id, 'turn-1');
  assert.equal(entry.userId, 'current-user');
  assert.equal(entry.items[0].text, 'Hello');
  assert.equal(entry.inputConfig.prompt, 'Hello');
  assert.deepEqual(entry.inputConfig.inputBlocks, [{ type: 'text', text: 'Hello' }]);
  assert.equal(entry.status, 'pending');
  assert.equal(meta.latestUserMsgId, 'turn-1');
  assert.deepEqual(calls.map(call => call.scope), ['doc', 'doc', 'meta', 'meta']);

  assert.equal(await sendText(repo, 'chat', 'turn-1', 'current-user', 'Hello', timestamp), 'sent');
  assert.equal(doc.getList('history').length, 1);
  await assert.rejects(sendText(repo, 'chat', 'turn-1', 'current-user', 'Different', timestamp),
    /another turn/);
});

test('a run-config choice applies to the new turn and keeps inherited values', async () => {
  const { repo, doc, meta } = fixture();
  doc.getList('history').push({ id: 'u0', role: 'user', items: [], inputConfig: {
    modelId: 'gpt-5.5', configOptionValues: { reasoning_effort: 'high', fast: 'on' },
  } });
  doc.commit();
  assert.equal(await sendText(repo, 'chat', 'turn-1', 'current-user', 'Hello', 'now',
    { configOptionID: 'reasoning_effort', value: 'low' }), 'sent');
  const entry = doc.getList('history').toJSON()[1];
  assert.equal(entry.inputConfig.modelId, 'gpt-5.5');
  assert.deepEqual(entry.inputConfig.configOptionValues, { reasoning_effort: 'low', fast: 'on' });

  meta.lastHandledUserMsgId = 'turn-1';

  await assert.rejects(sendText(repo, 'chat', 'turn-2', 'current-user', 'Again', 'now',
    { configOptionID: 'reasoning_effort', value: '' }), /Invalid/);
  assert.equal(doc.getList('history').length, 2);
});

test('a failed body sync does not publish dispatch', async () => {
  const { repo, doc, meta } = fixture();
  let count = 0;
  repo.sync = async () => ({ outcome: ++count === 1 ? 'synced' : 'failed' });
  assert.equal(await sendText(repo, 'chat', 'turn-1', 'current-user', 'Hello', 'now'), 'unconfirmed');
  assert.equal(doc.getList('history').length, 1);
  assert.equal(meta.latestUserMsgId, undefined);
});

test('busy sessions cannot create a direct dispatch turn', async () => {
  const { repo, doc, meta } = fixture();
  meta.status = { type: 'running' };
  assert.equal(await sendText(repo, 'chat', 'turn-1', 'current-user', 'Hello', 'now'), 'busy');
  assert.equal(doc.getList('history').length, 0);
});

test('a superseded retry can be followed by a fresh send', async () => {
  const { repo, doc, meta } = fixture();
  await sendText(repo, 'chat', 'turn-1', 'current-user', 'First', 'now');
  doc.getList('history').insert(1, { id: 'turn-2', role: 'user', items: [{ type: 'text', text: 'Second' }] });
  doc.commit();
  meta.latestUserMsgId = 'turn-2';
  assert.equal(await sendText(repo, 'chat', 'turn-1', 'current-user', 'First', 'now'),
    'superseded');
  assert.equal(meta.latestUserMsgId, 'turn-2');
  meta.lastHandledUserMsgId = 'turn-2';
  assert.equal(await sendText(repo, 'chat', 'turn-3', 'current-user', 'First', 'now'), 'sent');
  assert.equal(meta.latestUserMsgId, 'turn-3');
  assert.equal(doc.getList('history').length, 3);
});

test('a retry does not replace an activation missing from synced history', async () => {
  const { repo, meta } = fixture();
  await sendText(repo, 'chat', 'turn-1', 'current-user', 'First', 'now');
  meta.latestUserMsgId = 'turn-2';
  assert.equal(await sendText(repo, 'chat', 'turn-1', 'current-user', 'First', 'now'),
    'unconfirmed');
  assert.equal(meta.latestUserMsgId, 'turn-2');
});

test('a new activation during body sync is not overwritten', async () => {
  const { repo, doc, meta } = fixture();
  let docSyncs = 0;
  repo.sync = async options => {
    if (options.scope === 'doc' && ++docSyncs === 2) {
      doc.getList('history').insert(1, {
        id: 'turn-2', role: 'user', items: [{ type: 'text', text: 'Second' }],
      });
      doc.commit();
      meta.latestUserMsgId = 'turn-2';
    }
    return { outcome: 'synced' };
  };
  assert.equal(await sendText(repo, 'chat', 'turn-1', 'current-user', 'First', 'now'),
    'superseded');
  assert.equal(meta.latestUserMsgId, 'turn-2');
});

test('a competing activation after metadata write is not reported as sent', async () => {
  const { repo, meta } = fixture();
  let metaSyncs = 0;
  repo.sync = async options => {
    if (options.scope === 'meta' && ++metaSyncs === 2) {
      meta.latestUserMsgId = 'turn-2';
    }
    return { outcome: 'synced' };
  };
  assert.equal(await sendText(repo, 'chat', 'turn-1', 'current-user', 'First', 'now'),
    'unconfirmed');
  assert.equal(meta.latestUserMsgId, 'turn-2');
});


test('new turns use the matching runtime baseline, while retries keep their authored config', async () => {
  const { repo, doc, meta } = fixture();
  doc.getList('history').push({ id: 'u0', role: 'user', items: [], inputConfig: {
    modelId: 'old-model', modeId: 'old-mode',
    configOptionValues: { reasoning_effort: 'high', removed: 'old' },
  } });
  const runtime = doc.getMap('acpRuntimeConfig');
  runtime.set('basedOnUserTurnId', 'u0');
  runtime.set('modelId', 'actual-model');
  runtime.set('modeId', 'actual-mode');
  runtime.set('configOptionValues', { reasoning_effort: 'medium' });
  doc.commit();
  await sendText(repo, 'chat', 'u1', 'current-user', 'Hello', 'now',
    { configOptionID: 'reasoning_effort', value: 'low' });
  const authored = doc.getList('history').toJSON()[1].inputConfig;
  assert.equal(authored.modelId, 'actual-model');
  assert.equal(authored.modeId, 'actual-mode');
  assert.deepEqual(authored.configOptionValues, { reasoning_effort: 'low' });

  runtime.set('basedOnUserTurnId', 'u1');
  runtime.set('modelId', 'later-model');
  doc.commit();
  meta.lastHandledUserMsgId = 'u1';
  await sendText(repo, 'chat', 'u1', 'current-user', 'Hello', 'now',
    { configOptionID: 'reasoning_effort', value: 'high' });
  assert.deepEqual(doc.getList('history').toJSON()[1].inputConfig, authored);

  runtime.set('basedOnUserTurnId', 'stale-turn');
  doc.commit();
  await sendText(repo, 'chat', 'u2', 'current-user', 'Again', 'now');
  assert.equal(doc.getList('history').toJSON()[2].inputConfig.modelId, 'actual-model');
});

test('image and file blocks survive history, dispatch, and same-ID retries', async () => {
  const { repo, doc } = fixture();
  const attachments = [
    { type: 'image', imageId: 'image-1', mimeType: 'image/png', fileName: 'test.png', sizeBytes: 10 },
    { type: 'file', fileId: 'file-1', fileName: 'notes.txt', mimeType: 'text/plain', sizeBytes: 12,
      sha256: 'a'.repeat(64), transport: 'r2', uploadedAt: 1, textPreview: false },
  ];
  assert.equal(await sendText(repo, 'chat', 'turn-attachments', 'user', '', 'now', undefined, attachments), 'sent');
  const turn = doc.getList('history').toJSON()[0];
  assert.deepEqual(turn.items.slice(1), attachments);
  assert.deepEqual(turn.inputConfig.inputBlocks.slice(1), attachments);
  const reordered = attachments.map(block => Object.fromEntries(Object.entries(block).reverse()));
  assert.equal(await sendText(repo, 'chat', 'turn-attachments', 'user', '', 'now', undefined, reordered), 'sent');
  assert.equal(doc.getList('history').length, 1);
  await assert.rejects(sendText(repo, 'chat', 'turn-attachments', 'user', '', 'now', undefined, []), /another turn/);
});

test('independent child tab sends and retries its own turn while preserving parent linkage', async () => {
  const { repo, doc, meta } = fixture();
  meta.parentSessionId = 'root';
  assert.equal(await sendText(repo, 'chat', 'tab-turn', 'user', 'Hello', 'now'), 'sent');
  assert.equal(await sendText(repo, 'chat', 'tab-turn', 'user', 'Hello', 'now'), 'sent');
  assert.equal(doc.getList('history').length, 1);
  assert.equal(meta.parentSessionId, 'root');
  meta.status = { type: 'running' };
  assert.equal(await sendText(repo, 'chat', 'next', 'user', 'Hello', 'now'), 'busy');
});

function runningFixture() {
  const state = fixture();
  state.meta.status = { type: 'running' };
  state.meta.machineId = 'machine';
  state.meta.latestUserMsgId = 'active-user';
  state.doc.getList('history').push({ id: 'active-user', role: 'user', status: 'processing',
    inputConfig: { modelId: 'model', configOptionValues: { effort: 'high' } } });
  state.doc.getList('history').push({ id: 'active-assistant', role: 'assistant', finished: false });
  state.doc.commit();
  state.requests = [];
  state.steering = { state: {}, request: async (machineID, params) => {
    state.requests.push({ machineID, params });
    return { type: 'session/steer_response', sessionId: 'chat', userTurnId: params.userTurnId,
      applied: true, disposition: 'applied' };
  } };
  state.send = (text = 'Guidance', config, attachments = []) => sendText(state.repo, 'chat', 'guide',
    'user', text, 'original-time', config, attachments, state.steering);
  return state;
}

test('running input commits a pending_apply turn before steer, without a queue or dispatch pointer', async () => {
  const state = runningFixture();
  const attachment = { type: 'image', imageId: 'photo', mimeType: 'image/png' };
  state.steering.request = async (machineID, params) => {
    assert.equal(state.doc.getList('history').toJSON().at(-1).status, 'pending_apply');
    assert.deepEqual(state.calls.map(call => call.scope), ['doc', 'doc']);
    state.requests.push({ machineID, params });
    return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide', applied: true };
  };
  assert.equal(await state.send('Guidance', { configOptionID: 'effort', value: 'low' }, [attachment]), 'sent');
  const { machineID, params } = state.requests[0];
  assert.equal(machineID, 'machine');
  assert.equal(params.expectedTurnId, 'active-assistant');
  assert.equal(params.userTurnId, 'guide');
  assert.equal(params.userId, 'user');
  assert.equal(params.timestamp, 'original-time');
  assert.equal(params.inputConfig.modelId, 'model');
  assert.equal(params.inputConfig.configOptionValues.effort, 'low');
  assert.deepEqual(params.inputConfig.inputBlocks, [{ type: 'text', text: 'Guidance' }, attachment]);
  assert.equal(state.meta.latestUserMsgId, 'active-user');
});

test('steer reaches the machine while history upload is still pending', async () => {
  const state = runningFixture();
  let finishUpload;
  let started;
  const offered = new Promise(resolve => { started = resolve; });
  let syncs = 0;
  state.repo.sync = async options => {
    if (options.scope === 'doc' && ++syncs === 2) {
      return await new Promise(resolve => { finishUpload = resolve; });
    }
    return { outcome: 'synced' };
  };
  state.steering.request = async (_machine, params) => {
    started();
    return { type: 'session/steer_response', sessionId: 'chat', userTurnId: params.userTurnId, applied: true };
  };
  let completed = false;
  const send = state.send().then(result => { completed = true; return result; });
  await Promise.race([offered, new Promise((_resolve, reject) => setTimeout(() => reject(Error('Steer waited for upload')), 100))]);
  assert.equal(completed, false, 'The ephemeral writer must survive until its history upload finishes');
  finishUpload({ outcome: 'synced' });
  assert.equal(await send, 'sent');
  assert.equal(state.meta.latestUserMsgId, 'active-user');
});

test('a permanent missing-history rejection wins over every positive acknowledgement', async () => {
  for (const status of ['pending_apply', 'pending', 'seen', 'processing', 'handled', 'canceled']) {
    const state = runningFixture();
    state.steering.request = async () => { throw Error('timeout'); };
    assert.equal(await state.send(), 'unconfirmed');
    state.doc.getList('history').get(2).set('status', status);
    state.doc.commit();
    Object.assign(state.meta, { lastMissingHistoryUserMsgId: 'guide', latestUserMsgId: 'guide',
      lastHandledUserMsgId: 'guide', steerTurnStatuses: { guide: 'pending' } });
    state.steering.request = async () => { assert.fail('A rejected ID cannot be offered again'); };
    assert.equal(await state.send(), 'rejected', status);
  }
});

test('a missing-history rejection arriving during activation or an applied RPC is never reported as sent', async () => {
  const ordinary = fixture();
  ordinary.repo.upsertDocMeta = async (_id, patch) => {
    Object.assign(ordinary.meta, patch, { lastMissingHistoryUserMsgId: 'guide' });
  };
  assert.equal(await sendText(ordinary.repo, 'chat', 'guide', 'user', 'Guidance', 'time'), 'rejected');
  const steer = runningFixture();
  steer.steering.request = async () => {
    steer.meta.lastMissingHistoryUserMsgId = 'guide';
    return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide', applied: true };
  };
  assert.equal(await steer.send(), 'rejected');
});

test('legacy non-delivery repairs already-promoted pending and seen turns', async () => {
  for (const status of ['pending', 'seen']) {
    const state = runningFixture();
    state.steering.request = async () => {
      state.doc.getList('history').get(2).set('status', status);
      state.doc.commit();
      state.meta.status = { type: 'idle' };
      state.meta.lastHandledUserMsgId = 'active-user';
      return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide',
        applied: false, disposition: 'promotion-failed' };
    };
    assert.equal(await state.send(), 'sent', status);
    assert.equal(state.meta.latestUserMsgId, 'guide');
    assert.equal(state.doc.getList('history').length, 3);
    assert.equal(state.doc.getList('history').toJSON().at(-1).status, status);
  }
});

test('a timed-out steer retries the same user turn, target, timestamp, and authored configuration', async () => {
  const state = runningFixture();
  state.steering.request = async () => { throw new Error('timeout'); };
  assert.equal(await state.send('Guidance', { configOptionID: 'effort', value: 'low' }), 'unconfirmed');
  state.doc.getList('history').insert(2, { id: 'new-assistant', role: 'assistant', finished: false });
  state.doc.getMap('acpRuntimeConfig').set('basedOnUserTurnId', 'guide');
  state.doc.getMap('acpRuntimeConfig').set('modelId', 'new-model');
  state.doc.commit();
  state.steering.request = async (_machineID, params) => {
    state.requests.push(params);
    return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide', applied: true };
  };
  assert.equal(await state.send('Guidance', { configOptionID: 'effort', value: 'high' }), 'sent');
  assert.equal(state.requests[0].expectedTurnId, 'active-assistant');
  assert.equal(state.requests[0].timestamp, 'original-time');
  assert.equal(state.requests[0].inputConfig.modelId, 'model');
  assert.equal(state.requests[0].inputConfig.configOptionValues.effort, 'low');
  assert.equal(state.doc.getList('history').toJSON().filter(turn => turn.id === 'guide').length, 1);
  assert.equal(state.meta.latestUserMsgId, 'active-user');
});

test('a failed steer upload retries its original CRDT insertion on a fresh replica without resubmitting accepted input', async () => {
  const state = runningFixture();
  const baseline = state.doc.export({ mode: 'snapshot' });
  let uploads = 0;
  state.repo.sync = async options => ({ outcome: options.scope === 'doc' && ++uploads === 2 ? 'failed' : 'synced' });
  assert.equal(await state.send('Guidance', { configOptionID: 'effort', value: 'low' }), 'unconfirmed');
  assert.equal(state.steering.state.applied, true);
  const update = state.steering.state.authoredUpdate;
  assert(update instanceof Uint8Array);
  const replica = new LoroDoc();
  replica.import(baseline);
  state.repo.openPersistedDoc = async () => ({ doc: replica });
  state.repo.sync = async () => ({ outcome: 'synced' });
  state.steering.request = async () => { assert.fail('An applied RPC must not be repeated after a failed upload'); };
  assert.equal(await state.send('Guidance', { configOptionID: 'effort', value: 'high' }), 'sent');
  replica.import(update);
  const guides = replica.getList('history').toJSON().filter(turn => turn.id === 'guide');
  assert.equal(guides.length, 1);
  assert.equal(guides[0].timestamp, 'original-time');
  assert.equal(guides[0].inputConfig.configOptionValues.effort, 'low');
  assert.equal(guides[0].status, 'processing');
  assert.equal(guides[0].inputConfig._lodyDeliveryKind, 'steer');
  assert.equal(state.steering.state.authoredUpdate, undefined);
});

test('unknown steer delivery still uploads its original insertion on a fresh replica', async () => {
  const state = runningFixture();
  const baseline = state.doc.export({ mode: 'snapshot' });
  let uploads = 0;
  state.repo.sync = async options => ({ outcome: options.scope === 'doc' && ++uploads === 2 ? 'failed' : 'synced' });
  state.steering.request = async () => {
    state.meta.steerTurnStatuses = { guide: 'delivery_unknown' };
    return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide',
      applied: false, disposition: 'delivery-unknown' };
  };
  assert.equal(await state.send('Guidance', { configOptionID: 'effort', value: 'low' }), 'unconfirmed');
  const update = state.steering.state.authoredUpdate;
  assert(update instanceof Uint8Array);
  state.steering.request = async () => { assert.fail('Unknown delivery cannot submit another offer'); };
  state.repo.upsertDocMeta = async () => { assert.fail('Unknown delivery cannot activate ordinary dispatch'); };
  let durable = baseline;
  for (const outcome of ['failed', 'synced']) {
    const replica = new LoroDoc();
    replica.import(durable);
    state.repo.openPersistedDoc = async () => ({ doc: replica });
    const calls = [];
    state.repo.sync = async options => {
      calls.push(options.scope);
      if (calls.length === 1) {
        assert.equal(replica.getList('history').toJSON().some(turn => turn.id === 'guide'), false);
        return { outcome: 'synced' };
      }
      if (outcome === 'synced') durable = replica.export({ mode: 'snapshot' });
      return { outcome };
    };
    assert.equal(await state.send('Guidance', { configOptionID: 'effort', value: 'high' }), 'unconfirmed');
    assert.deepEqual(calls, ['doc', 'doc']);
    assert.equal(state.steering.state.authoredUpdate, outcome === 'failed' ? update : undefined);
    replica.import(update);
    const guides = replica.getList('history').toJSON().filter(turn => turn.id === 'guide');
    assert.equal(guides.length, 1);
    assert.equal(guides[0].timestamp, 'original-time');
    assert.equal(guides[0].inputConfig.configOptionValues.effort, 'low');
    assert.equal(guides[0].status, 'pending_apply');
  }
  const persisted = new LoroDoc();
  persisted.import(durable);
  assert.equal(persisted.getList('history').toJSON().filter(turn => turn.id === 'guide').length, 1);
});

for (const verdict of ['applied', 'delivery-unknown', 'timeout']) {
  test(`a rejected steer persists its original insertion after a failed upload and ${verdict}`, async () => {
    const state = runningFixture();
    const baseline = state.doc.export({ mode: 'snapshot' });
    const attachment = { type: 'image', imageId: 'photo', mimeType: 'image/png' };
    let uploads = 0;
    state.repo.sync = async options => ({ outcome: options.scope === 'doc' && ++uploads === 2 ? 'failed' : 'synced' });
    state.steering.request = async () => {
      if (verdict === 'timeout') throw Error('timeout');
      return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide',
        applied: verdict === 'applied', disposition: verdict };
    };
    assert.equal(await state.send('Guidance', { configOptionID: 'effort', value: 'low' }, [attachment]), 'unconfirmed');
    const update = state.steering.state.authoredUpdate;
    assert(update instanceof Uint8Array);
    Object.assign(state.meta, { lastMissingHistoryUserMsgId: 'guide', lastHandledUserMsgId: 'guide',
      steerTurnStatuses: { guide: 'pending' } });
    const replica = new LoroDoc();
    replica.import(baseline);
    state.repo.openPersistedDoc = async () => ({ doc: replica });
    state.steering.request = async () => { assert.fail('A rejected ID cannot be offered again'); };
    state.repo.upsertDocMeta = async () => { assert.fail('A rejected ID cannot activate ordinary dispatch'); };
    const calls = [];
    let durable = baseline;
    state.repo.sync = async options => {
      calls.push(options.scope);
      if (calls.length === 1) {
        assert.equal(replica.getList('history').toJSON().some(turn => turn.id === 'guide'), false);
      } else {
        durable = replica.export({ mode: 'snapshot' });
      }
      return { outcome: 'synced' };
    };
    assert.equal(await state.send('Guidance', { configOptionID: 'effort', value: 'high' }, [attachment]), 'rejected');
    assert.deepEqual(calls, ['doc', 'doc']);
    assert.equal(state.steering.state.authoredUpdate, undefined);
    const persisted = new LoroDoc();
    persisted.import(durable);
    assert.equal(persisted.getList('history').toJSON().filter(turn => turn.id === 'guide').length, 1);
    persisted.import(update);
    const guides = persisted.getList('history').toJSON().filter(turn => turn.id === 'guide');
    assert.equal(guides.length, 1);
    assert.equal(guides[0].timestamp, 'original-time');
    assert.equal(guides[0].inputConfig.configOptionValues.effort, 'low');
    assert.deepEqual(guides[0].inputConfig.inputBlocks, [{ type: 'text', text: 'Guidance' }, attachment]);
    assert.equal(guides[0].status, 'pending_apply');
    assert.equal(state.meta.latestUserMsgId, 'active-user');
  });
}

test('a rejected steer keeps its original insertion until a failed or cancelled retry can persist it', async () => {
  const state = runningFixture();
  const baseline = state.doc.export({ mode: 'snapshot' });
  let uploads = 0;
  state.repo.sync = async options => ({ outcome: options.scope === 'doc' && ++uploads === 2 ? 'failed' : 'synced' });
  state.steering.request = async () => { throw Error('timeout'); };
  assert.equal(await state.send(), 'unconfirmed');
  const update = state.steering.state.authoredUpdate;
  assert(update instanceof Uint8Array);
  state.meta.lastMissingHistoryUserMsgId = 'guide';
  state.steering.request = async () => { assert.fail('A rejected ID cannot be offered again'); };
  state.repo.upsertDocMeta = async () => { assert.fail('A rejected ID cannot activate ordinary dispatch'); };
  let durable = baseline;
  for (const outcome of ['failed', 'throw', 'abort', 'synced']) {
    const replica = new LoroDoc();
    replica.import(durable);
    state.repo.openPersistedDoc = async () => ({ doc: replica });
    const controller = new AbortController();
    state.steering.signal = controller.signal;
    const calls = [];
    state.repo.sync = async options => {
      calls.push(options.scope);
      if (calls.length === 1) return { outcome: 'synced' };
      assert.equal(options.signal, controller.signal);
      if (outcome === 'throw') throw Error('upload failed');
      if (outcome === 'abort') controller.abort();
      if (outcome === 'synced') durable = replica.export({ mode: 'snapshot' });
      return { outcome: outcome === 'failed' ? 'failed' : 'synced' };
    };
    if (outcome === 'abort') await assert.rejects(state.send(), { name: 'AbortError' });
    else assert.equal(await state.send(), outcome === 'synced' ? 'rejected' : 'unconfirmed');
    assert.deepEqual(calls, ['doc', 'doc']);
    assert.equal(state.steering.state.authoredUpdate, outcome === 'synced' ? undefined : update);
  }
  const persisted = new LoroDoc();
  persisted.import(durable);
  assert.equal(persisted.getList('history').toJSON().filter(turn => turn.id === 'guide').length, 1);
  persisted.import(update);
  assert.equal(persisted.getList('history').toJSON().filter(turn => turn.id === 'guide').length, 1);
});

test('a missing-history rejection without an authored insertion cannot recreate the old turn', async () => {
  const state = runningFixture();
  state.meta.lastMissingHistoryUserMsgId = 'guide';
  state.steering.request = async () => { assert.fail('A rejected ID cannot be offered again'); };
  state.repo.upsertDocMeta = async () => { assert.fail('A rejected ID cannot activate ordinary dispatch'); };
  assert.equal(await state.send(), 'rejected');
  assert.equal(state.doc.getList('history').toJSON().some(turn => turn.id === 'guide'), false);
  assert.deepEqual(state.calls.map(call => call.scope), ['doc']);
});

test('a timeout and failed upload restore the original offer on a fresh replica even after concurrent history grows', async () => {
  const state = runningFixture();
  const baseline = state.doc.export({ mode: 'snapshot' });
  let uploads = 0;
  state.repo.sync = async options => ({ outcome: options.scope === 'doc' && ++uploads === 2 ? 'failed' : 'synced' });
  state.steering.request = async () => { throw Error('timeout'); };
  assert.equal(await state.send('Guidance', { configOptionID: 'effort', value: 'low' }), 'unconfirmed');
  const replica = new LoroDoc();
  replica.import(baseline);
  replica.getList('history').push({ id: 'concurrent-assistant', role: 'assistant', finished: false });
  replica.commit();
  state.repo.openPersistedDoc = async () => ({ doc: replica });
  state.repo.sync = async () => ({ outcome: 'synced' });
  state.steering.request = async (_machine, params) => {
    assert.equal(params.expectedTurnId, 'active-assistant');
    assert.equal(params.timestamp, 'original-time');
    assert.equal(params.inputConfig.configOptionValues.effort, 'low');
    return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide', applied: true };
  };
  assert.equal(await state.send('Guidance', { configOptionID: 'effort', value: 'high' }), 'sent');
  assert.equal(replica.getList('history').toJSON().filter(turn => turn.id === 'guide').length, 1);
});

test('legacy proven non-delivery can activate a follow-up behind the active input without overwriting a newer producer', async () => {
  for (const competing of [false, true]) {
    const state = runningFixture();
    state.steering.request = async () => {
      if (competing) {
        state.doc.getList('history').push({ id: 'newer', role: 'user', status: 'pending' });
        state.doc.commit();
        state.meta.latestUserMsgId = 'newer';
      }
      return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide',
        applied: false, disposition: 'no-active-turn' };
    };
    assert.equal(await state.send(), competing ? 'superseded' : 'sent');
    assert.equal(state.meta.latestUserMsgId, competing ? 'newer' : 'guide');
  }
});

test('cancellation keeps the authored identity but does not promote or mutate a late steer reply', async () => {
  const state = runningFixture();
  const controller = new AbortController();
  state.steering.signal = controller.signal;
  state.steering.request = async () => {
    controller.abort();
    return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide', applied: true };
  };
  await assert.rejects(state.send(), { name: 'AbortError' });
  assert.equal(state.doc.getList('history').toJSON().at(-1).status, 'pending_apply');
  assert.equal(state.steering.state.applied, true);
  assert.equal(state.meta.latestUserMsgId, 'active-user');
});

test('daemon-owned fallback is accepted without overwriting another producer activation', async () => {
  const state = runningFixture();
  state.steering.request = async () => {
    state.meta.steerTurnStatuses = { guide: 'pending' };
    state.meta.latestUserMsgId = 'other-producer';
    return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide',
      applied: false, recoveryOwned: true, disposition: 'no-active-turn' };
  };
  assert.equal(await state.send(), 'sent');
  assert.equal(state.meta.latestUserMsgId, 'other-producer');
  state.steering.request = async () => { assert.fail('Accepted recovery must not send another RPC'); };
  assert.equal(await state.send(), 'sent');
});

test('unknown steer delivery is never replayed as an ordinary send', async () => {
  const state = runningFixture();
  state.steering.request = async () => {
    state.meta.steerTurnStatuses = { guide: 'delivery_unknown' };
    return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide',
      applied: false, recoveryOwned: true, disposition: 'delivery-unknown' };
  };
  assert.equal(await state.send(), 'unconfirmed');
  state.meta.status = { type: 'idle' };
  state.steering.request = async () => { assert.fail('Unknown provider delivery must not be repeated'); };
  assert.equal(await state.send(), 'unconfirmed');
  assert.equal(state.meta.latestUserMsgId, 'active-user');
});

test('an explicit unknown RPC verdict prevents replay even before its metadata arrives', async () => {
  const state = runningFixture();
  state.steering.request = async () => ({ type: 'session/steer_response', sessionId: 'chat',
    userTurnId: 'guide', applied: false, disposition: 'delivery-unknown' });
  assert.equal(await state.send(), 'unconfirmed');
  state.steering.request = async () => { assert.fail('Unknown delivery cannot submit a second offer'); };
  assert.equal(await state.send(), 'unconfirmed');
  state.meta.steerTurnStatuses = { guide: 'handled' };
  assert.equal(await state.send(), 'sent');
});

test('legacy definitive non-delivery can dispatch the same turn once the session is idle', async () => {
  const state = runningFixture();
  state.steering.request = async () => {
    state.meta.status = { type: 'idle' };
    state.meta.lastHandledUserMsgId = 'active-user';
    return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide',
      applied: false, disposition: 'no-active-turn' };
  };
  assert.equal(await state.send(), 'sent');
  assert.equal(state.meta.latestUserMsgId, 'guide');
  assert.equal(state.doc.getList('history').length, 3);
  assert.equal(state.doc.getList('history').toJSON().at(-1).status, 'pending');
});

test('repairing daemon promotion uses the same steer request rather than a client pointer write', async () => {
  const state = runningFixture();
  let requests = 0;
  state.steering.request = async (_machineID, params) => {
    state.requests.push(params);
    if (++requests === 2) state.meta.steerTurnStatuses = { guide: 'pending' };
    return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide',
      applied: false, recoveryOwned: true, disposition: requests === 1 ? 'promotion-failed' : 'no-active-turn' };
  };
  assert.equal(await state.send(), 'sent');
  assert.deepEqual(state.requests[0], state.requests[1]);
  assert.equal(state.meta.latestUserMsgId, 'active-user');
});

test('mismatched responses and running sessions without an active target stay unconfirmed or busy', async () => {
  const state = runningFixture();
  state.steering.request = async () => ({ type: 'session/steer_response', sessionId: 'other',
    userTurnId: 'guide', applied: true });
  assert.equal(await state.send(), 'unconfirmed');
  state.doc.getList('history').clear();
  state.doc.commit();
  assert.equal(await state.send(), 'busy');
  assert.equal(state.doc.getList('history').length, 0);
});

test('projected steer terminal statuses confirm delivery after daemon metadata is retired', async () => {
  for (const status of ['handled', 'canceled', 'failed', 'processing']) {
    const state = runningFixture();
    state.steering.request = async () => {
      state.doc.getList('history').get(2).set('status', status);
      state.doc.commit();
      return { type: 'session/steer_response', sessionId: 'chat', userTurnId: 'guide',
        applied: false, recoveryOwned: true, disposition: 'no-active-turn' };
    };
    assert.equal(await state.send(), 'sent', status);
    state.steering.request = async () => { assert.fail('A projected result must not send again'); };
    assert.equal(await state.send(), 'sent', status);
  }
});

test('losing an unconfirmed steer target never guesses from concurrent history', async () => {
  const state = runningFixture();
  state.steering.request = async () => { throw new Error('timeout'); };
  assert.equal(await state.send(), 'unconfirmed');
  state.steering.state = {};
  state.steering.request = async () => { assert.fail('No original target, no replay'); };
  assert.equal(await state.send(), 'unconfirmed');
  assert.equal(state.meta.latestUserMsgId, 'active-user');
});
