import assert from 'node:assert/strict';
import test from 'node:test';
import {
  archiveSession,
  deleteArchivedSession,
  readLocalProjectState,
  restoreArchivedSession,
  selectArchivedSessions,
} from './session-archive.mjs';

function session(id, meta = {}) {
  return { docId: `session-${id}`, meta: { id, title: id, ...meta } };
}

function fixture(rows, machineMeta = {}) {
  const metas = {};
  for (const row of rows) metas[row.docId] = { ...row.meta };
  Object.assign(metas, machineMeta);
  const flocks = new Map();
  const calls = [];
  const repo = {
    async listDoc() { return rows; },
    async getDocMeta(id) { return metas[id] ? { meta: metas[id] } : undefined; },
    async upsertDocMeta(id, patch) { metas[id] = { ...(metas[id] ?? {}), ...patch }; },
    async openFlockDoc(id) {
      if (!flocks.has(id)) {
        const values = new Map();
        flocks.set(id, {
          set(key, value) { values.set(JSON.stringify(key), structuredClone(value)); },
          commit() {},
          get(key) { return values.get(JSON.stringify(key)); },
        });
      }
      return { flock: flocks.get(id) };
    },
    async sync(options) {
      calls.push(options);
      return { outcome: 'synced' };
    },
  };
  return { repo, metas, flocks, calls };
}

const lifecycleRows = [
  session('root', { machineId: 'machine-root' }),
  session('tab', { machineId: 'machine-root', parentSessionId: 'root', openedBySessionId: 'root' }),
  session('opened', { machineId: 'machine-opened', openedBySessionId: 'root' }),
  session('opened-from-tab', {
    machineId: 'machine-opened-from-tab',
    openedBySessionId: 'tab',
    openedByRootSessionId: 'root',
  }),
  session('unrelated', { machineId: 'machine-other' }),
  { docId: 'session-comment-root', meta: { parentSessionId: 'root' } },
  { docId: 'session-deleted', deleted: true, meta: { parentSessionId: 'root', machineId: 'machine-root' } },
];

test('archive marks the lifecycle idle without writing machine commands', async () => {
  const { repo, metas, flocks, calls } = fixture(lifecycleRows);
  assert.equal(await archiveSession(repo, 'root'), 'archived');
  for (const id of ['root', 'tab', 'opened', 'opened-from-tab']) {
    assert.equal(metas[`session-${id}`].isArchived, true);
    assert.deepEqual(metas[`session-${id}`].status, { type: 'idle' });
    assert.equal(metas[`session-${id}`].title, id);
  }
  for (const id of ['unrelated', 'comment-root', 'deleted']) {
    assert.equal(metas[`session-${id}`].isArchived, undefined);
  }
  assert.equal(flocks.size, 0);
  assert.deepEqual(calls.map(call => call.scope), ['meta']);
  assert.equal(metas['machine-machine-root'], undefined);
});

test('archive is idempotent', async () => {
  const { repo, metas } = fixture([session('chat', { isArchived: true, status: { type: 'running' } })]);
  assert.equal(await archiveSession(repo, 'chat'), 'archived');
  assert.deepEqual(metas['session-chat'].status, { type: 'idle' });
});

test('archiving a child tab archives descendants without its parent', async () => {
  const { repo, metas } = fixture(lifecycleRows);
  assert.equal(await archiveSession(repo, 'tab'), 'archived');
  assert.equal(metas['session-tab'].isArchived, true);
  assert.equal(metas['session-opened-from-tab'].isArchived, true);
  assert.equal(metas['session-root'].isArchived, undefined);
});

test('missing session is reported without writes', async () => {
  const { repo, metas } = fixture([session('chat')]);
  assert.equal(await archiveSession(repo, 'other'), 'missing');
  assert.equal(metas['session-chat'].isArchived, undefined);
});

test('machine command unavailability and legacy queue cleanup do not reject an archive', async () => {
  const { repo, metas } = fixture([session('chat', { machineId: 'machine' })], {
    'machine-machine': { needToArchiveSessions: { chat: true } },
  });
  repo.openFlockDoc = async () => { throw new Error('Machine unavailable'); };
  repo.sync = async () => {
    metas['machine-machine'].needToArchiveSessions = {};
    return { outcome: 'synced' };
  };
  assert.equal(await archiveSession(repo, 'chat'), 'archived');
  assert.equal(metas['session-chat'].isArchived, true);
});

test('failed metadata confirmation is not reported as archived', async () => {
  const { repo, metas } = fixture([session('chat', { machineId: 'machine' })]);
  repo.sync = async () => ({ outcome: 'failed' });
  assert.equal(await archiveSession(repo, 'chat'), 'unconfirmed');
  assert.equal(metas['session-chat'].isArchived, true);
});

test('concurrently restored or deleted metadata is not reported as archived', async () => {
  for (const change of [{ meta: { isArchived: false } }, { deleted: true }]) {
    const { repo } = fixture([session('chat')]);
    repo.getDocMeta = async () => change;
    assert.equal(await archiveSession(repo, 'chat'), 'unconfirmed');
  }
});

function archivedRow(id, meta = {}) {
  return {
    docId: `session-${id}`,
    meta: { id, title: id, isArchived: true, ...meta },
  };
}

function documentRepo(initialRows, flockRows = []) {
  const rows = initialRows.map(row => ({ ...row, meta: { ...(row.meta ?? {}) } }));
  const deleted = new Set();
  const calls = [];
  const repo = {
    calls,
    async sync(options) {
      calls.push(options);
      return { outcome: 'synced', ok: true };
    },
    async listDoc() {
      return rows
        .filter(row => !deleted.has(row.docId))
        .map(row => ({ docId: row.docId, deleted: false, meta: { ...row.meta } }));
    },
    async getDocMeta(id) {
      if (deleted.has(id)) return { deleted: true };
      if (id.startsWith('machine-')) {
        return { meta: { localProjects: { kurage: { name: 'Kurage' } } } };
      }
      const row = rows.find(entry => entry.docId === id);
      return row ? { meta: { ...row.meta } } : undefined;
    },
    async upsertDocMeta(id, patch) {
      calls.push({ op: 'upsert', id, patch: { ...patch } });
      const row = rows.find(entry => entry.docId === id);
      if (row) Object.assign(row.meta, patch);
    },
    async deleteDoc(id) {
      calls.push({ op: 'delete', id });
      deleted.add(id);
    },
    async openFlockDoc() {
      return {
        flock: {
          scan({ prefix }) {
            return flockRows.filter(row => prefix.every((part, index) => row.key[index] === part));
          },
        },
      };
    },
  };
  return repo;
}

const archivedRows = [
  archivedRow('root', { machineId: 'machine', lastMessageAt: 20, isTabClosed: true, project: { kind: 'chat' } }),
  archivedRow('tab', { parentSessionId: 'root', lastMessageAt: 50, title: 'Tab' }),
  archivedRow('opened', { openedBySessionId: 'root', lastMessageAt: 10, title: 'Opened' }),
  archivedRow('older', { lastMessageAt: 5, title: 'Older', createdAt: '2020-01-01T00:00:00Z' }),
  archivedRow('live', { isArchived: false, lastMessageAt: 100, title: 'Live' }),
  { docId: 'session-comment-root', meta: { isArchived: true, parentSessionId: 'root', title: 'Comment' } },
];

test('archived sessions are newest first and omit child tabs', () => {
  const sessions = selectArchivedSessions(archivedRows);
  assert.deepEqual(sessions.map(session => session.id), ['root', 'opened', 'older']);
  assert.equal(sessions[0].title, 'root');
  assert.equal(sessions[1].title, 'Opened');
});

test('createdAt orders an archived session that has no last message', () => {
  const sessions = selectArchivedSessions([
    archivedRow('dated', { isArchived: true, lastMessageAt: undefined, createdAt: '2024-01-01T00:00:00Z' }),
    archivedRow('empty', { isArchived: true, lastMessageAt: undefined, createdAt: 'not-a-date', title: '' }),
  ]);
  assert.equal(sessions[0].id, 'dated');
  assert.equal(sessions[1].title, 'Untitled session');
  assert.equal(sessions[1].lastMessageAt, 0);
});

test('a removed or pending local project cannot be restored', async () => {
  const removed = archivedRow('local', {
    machineId: 'machine',
    project: { kind: 'local', localProjectId: 'missing' },
  });
  const pending = archivedRow('pending', {
    machineId: 'machine',
    project: { kind: 'local', localProjectId: 'kurage' },
  });
  const flock = [
    { key: ['localProject', 'kurage'], value: { name: 'Kurage' } },
    { key: ['cmd', 'deleteLocalProject', 'kurage'], value: { v: 1 } },
  ];
  const removedState = await readLocalProjectState(documentRepo([removed], flock), 'workspace', 'machine');
  const pendingState = await readLocalProjectState(documentRepo([pending], flock), 'workspace', 'machine');
  assert.equal(selectArchivedSessions([removed], new Map([['machine', removedState]]))[0].canRestore, false);
  assert.equal(selectArchivedSessions([pending], new Map([['machine', pendingState]]))[0].canRestore, false);
  assert.equal(selectArchivedSessions([removed], new Map([['machine', removedState]]))[0].projectName, 'Local Project');

  const repo = documentRepo([removed, pending], flock);
  assert.equal(await restoreArchivedSession(repo, 'workspace', 'local'), 'project-missing');
  assert.equal(await restoreArchivedSession(repo, 'workspace', 'pending'), 'project-missing');
  assert.equal(repo.calls.some(call => call.op === 'upsert'), false);
});

test('restore clears the root and its child tab without touching an opened session', async () => {
  const repo = documentRepo(archivedRows);
  assert.equal(await restoreArchivedSession(repo, 'workspace', 'root'), 'restored');
  const restored = await repo.listDoc();
  assert.equal(restored.find(row => row.docId === 'session-root').meta.isArchived, false);
  assert.equal(restored.find(row => row.docId === 'session-root').meta.isTabClosed, false);
  assert.equal(restored.find(row => row.docId === 'session-tab').meta.isArchived, false);
  assert.equal(restored.find(row => row.docId === 'session-tab').meta.isTabClosed, undefined);
  assert.equal(restored.find(row => row.docId === 'session-opened').meta.isArchived, true);
  assert.equal(await restoreArchivedSession(repo, 'workspace', 'root'), 'restored');
});

test('restore reports a missing session and an unconfirmed metadata sync', async () => {
  const missing = documentRepo(archivedRows);
  assert.equal(await restoreArchivedSession(missing, 'workspace', 'absent'), 'missing');
  const failed = documentRepo(archivedRows);
  let metaSyncs = 0;
  failed.sync = async options => {
    if (options.scope === 'meta' && ++metaSyncs === 2) return { outcome: 'failed' };
    return { outcome: 'synced', ok: true };
  };
  assert.equal(await restoreArchivedSession(failed, 'workspace', 'opened'), 'unconfirmed');
});

test('delete removes the archived root and child tab, children first', async () => {
  const repo = documentRepo(archivedRows);
  assert.equal(await deleteArchivedSession(repo, 'root'), 'deleted');
  assert.deepEqual(
    repo.calls.filter(call => call.op === 'delete').map(call => call.id),
    ['session-tab', 'session-root'],
  );
  const remaining = await repo.listDoc();
  assert.equal(remaining.some(row => row.docId === 'session-root'), false);
  assert.equal(remaining.some(row => row.docId === 'session-opened'), true);
  assert.equal(await deleteArchivedSession(repo, 'root'), 'missing');
});

test('delete refuses a session that is not archived', async () => {
  const repo = documentRepo(archivedRows);
  assert.equal(await deleteArchivedSession(repo, 'live'), 'not-archived');
  assert.equal(repo.calls.some(call => call.op === 'delete'), false);
});

test('delete is unconfirmed when metadata sync fails before the write', async () => {
  const repo = documentRepo(archivedRows);
  repo.sync = async () => ({ outcome: 'failed' });
  assert.equal(await deleteArchivedSession(repo, 'root'), 'unconfirmed');
  assert.equal(repo.calls.some(call => call.op === 'delete'), false);
});
