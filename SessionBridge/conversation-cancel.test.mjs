import assert from 'node:assert/strict';
import test from 'node:test';
import { LoroDoc } from 'loro-crdt';
import { cancelSession } from './conversation-cancel.mjs';

function fixture() {
  const doc = new LoroDoc();
  const meta = { status: { type: 'running' } };
  const calls = [];
  const repo = {
    listDoc: async () => [{ docId: 'session-chat', meta }],
    openPersistedDoc: async () => ({ doc }),
    getDocMeta: async () => ({ meta }),
    sync: async options => { calls.push(options); return { outcome: 'synced' }; },
    upsertDocMeta: async (_id, patch) => { Object.assign(meta, patch); },
  };
  return { doc, meta, calls, repo };
}

test('cancellation targets the latest unfinished assistant turn and confirms metadata', async () => {
  const { doc, meta, calls, repo } = fixture();
  const history = doc.getList('history');
  history.push({ id: 'old', role: 'assistant', finished: true, items: [] });
  history.push({ id: 'user', role: 'user', items: [] });
  history.push({ id: 'active', role: 'assistant', finished: false, items: [] });
  doc.commit();

  assert.equal(await cancelSession(repo, 'chat'), 'requested');
  assert.equal(meta.lastCanceledTurn, 'active');
  assert.deepEqual(calls.map(call => call.scope), ['doc', 'meta', 'meta']);
});

test('cancellation never targets a completed or changed turn', async () => {
  const { doc, meta, repo } = fixture();
  doc.getList('history').push({ id: 'done', role: 'assistant', finished: true, items: [] });
  doc.commit();
  assert.equal(await cancelSession(repo, 'chat'), 'unavailable');
  assert.equal(meta.lastCanceledTurn, undefined);

  doc.getList('history').push({ id: 'active', role: 'assistant', items: [] });
  doc.commit();
  repo.sync = async options => {
    if (options.scope === 'meta') meta.status = { type: 'idle' };
    return { outcome: 'synced' };
  };
  assert.equal(await cancelSession(repo, 'chat'), 'unavailable');
  assert.equal(meta.lastCanceledTurn, undefined);
});

test('unconfirmed metadata sync is not reported as requested', async () => {
  const { doc, meta, repo } = fixture();
  doc.getList('history').push({ id: 'active', role: 'assistant', items: [] });
  doc.commit();
  let metaSyncs = 0;
  repo.sync = async options => ({ outcome: options.scope === 'meta' && ++metaSyncs === 2 ? 'failed' : 'synced' });
  await assert.rejects(cancelSession(repo, 'chat'), /cancellation sync failed/);
  assert.equal(meta.lastCanceledTurn, 'active');
});
