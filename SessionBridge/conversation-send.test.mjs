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
