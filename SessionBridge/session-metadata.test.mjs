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
