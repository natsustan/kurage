import test from 'node:test';
import assert from 'node:assert/strict';
import { updateSessionMetadata } from './session-metadata.mjs';

function repository(meta = { title: 'Original', titleSource: 'auto', status: { type: 'running' } }) {
  let row = { meta };
  return {
    get row() { return row; },
    set row(value) { row = value; },
    getDocMeta: async id => id === 'session-chat' ? row : null,
    upsertDocMeta: async (_, patch) => { row.meta = { ...row.meta, ...patch }; },
    sync: async () => ({ outcome: 'synced' }),
  };
}

test('pin and unpin preserve title and running state', async () => {
  const repo = repository();
  for (const isPinned of [true, false]) {
    assert.equal(await updateSessionMetadata(repo, 'chat', { isPinned }), 'updated');
    assert.equal(repo.row.meta.isPinned, isPinned);
    assert.equal(repo.row.meta.title, 'Original');
    assert.deepEqual(repo.row.meta.status, { type: 'running' });
  }
});
test('rename trims and marks title as user-authored without losing pin', async () => {
  const repo = repository({ isPinned: true });
  assert.equal(await updateSessionMetadata(repo, 'chat', { title: ' New title ' }), 'updated');
  assert.deepEqual(repo.row.meta, { isPinned: true, title: 'New title', titleSource: 'user' });
});
test('invalid names and missing, deleted or archived sessions do not write', async () => {
  const repo = repository();
  repo.upsertDocMeta = async () => assert.fail('unexpected write');
  for (const title of ['', '  ', 'x'.repeat(201)]) {
    assert.equal(await updateSessionMetadata(repo, 'chat', { title }), 'invalid');
  }
  assert.equal(await updateSessionMetadata(repo, 'absent', { isPinned: true }), 'missing');
  for (const row of [null, { exists: false }, { e: false }, { deleted: true }, { meta: { isArchived: true } }]) {
    repo.row = row;
    assert.equal(await updateSessionMetadata(repo, 'chat', { isPinned: true }), 'missing');
  }
});
test('failed sync and conflicting metadata are unconfirmed', async () => {
  const repo = repository();
  repo.sync = async () => ({ outcome: 'failed' });
  assert.equal(await updateSessionMetadata(repo, 'chat', { isPinned: true }), 'unconfirmed');
  repo.sync = async () => { repo.row.meta.title = 'Conflict'; return { outcome: 'synced' }; };
  assert.equal(await updateSessionMetadata(repo, 'chat', { title: 'Mine' }), 'unconfirmed');
});

test('metadata cancellation while reading prevents mutation and sync', async () => {
  for (const change of [{ isPinned: true }, { title: 'New' }]) {
    const controller = new AbortController();
    const started = Promise.withResolvers();
    const read = Promise.withResolvers();
    const repo = repository();
    repo.getDocMeta = () => { started.resolve(); return read.promise; };
    repo.upsertDocMeta = async () => assert.fail('unexpected write');
    repo.sync = async () => assert.fail('unexpected sync');
    const pending = updateSessionMetadata(repo, 'chat', change, controller.signal);
    await started.promise;
    controller.abort();
    read.resolve({ meta: {} });
    await assert.rejects(pending, { name: 'AbortError' });
  }
});

test('metadata sync receives cancellation and cannot report success after abort', async () => {
  const controller = new AbortController();
  const repo = repository();
  repo.sync = async ({ signal }) => {
    assert.equal(signal, controller.signal);
    controller.abort();
    return { outcome: 'synced' };
  };
  await assert.rejects(updateSessionMetadata(repo, 'chat', { isPinned: true }, controller.signal), { name: 'AbortError' });
});

test('already cancelled metadata edits do not read or write', async () => {
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(updateSessionMetadata({}, 'chat', { isPinned: true }, controller.signal), { name: 'AbortError' });
});

test('read receipts advance monotonically and preserve newer unread messages', async () => {
  const repo = repository({ lastMessageAt: 200, lastReadAt: 50, title: 'Chat' });
  assert.equal(await updateSessionMetadata(repo, 'chat', { lastReadAt: 100 }), 'updated');
  assert.equal(repo.row.meta.lastReadAt, 100);
  assert.equal(repo.row.meta.lastMessageAt, 200);
  assert.equal(await updateSessionMetadata(repo, 'chat', { lastReadAt: 75 }), 'updated');
  assert.equal(repo.row.meta.lastReadAt, 100);
  repo.sync = async () => { repo.row.meta.lastReadAt = 200; return { outcome: 'synced' }; };
  assert.equal(await updateSessionMetadata(repo, 'chat', { lastReadAt: 150 }), 'updated');
  assert.equal(repo.row.meta.title, 'Chat');
});

test('invalid read receipts do not write', async () => {
  const repo = repository();
  repo.upsertDocMeta = async () => assert.fail('unexpected write');
  for (const lastReadAt of [NaN, Infinity, '100', null]) {
    assert.equal(await updateSessionMetadata(repo, 'chat', { lastReadAt }), 'invalid');
  }
});
