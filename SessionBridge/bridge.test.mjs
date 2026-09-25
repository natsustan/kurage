import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';
import {
  deleteArchivedSession,
  readLocalProjectState,
  restoreArchivedSession,
  selectArchivedSessions,
} from './session-archive.mjs';

const source = (await readFile(new URL('./bridge.js', import.meta.url), 'utf8'))
  .replace(/^import .*;\n/gm, '');

function makeBridge(sync = async () => ({ ok: true }), rows = [], cancel = async () => 'requested', archive = async () => ({ status: 'archived', sessionIDs: ['chat'] }), extras = {}) {
  const repos = [];
  const transports = [];
  class Repo {
    constructor() { this.destroyed = false; this.loaded = new Set(); }
    static async create() {
      const repo = new Repo();
      repos.push(repo);
      return repo;
    }
    async addTransport(_id, transport) { transports.push(transport.options); }
    async sync(options) { return sync(options); }
    async listDoc() { return rows; }
    async openFlockDoc(docID) {
      return {
        syncOnce: () => sync({ scope: 'doc', flockDocIds: [docID] }),
        flock: { scan: () => [] },
      };
    }
    async openPersistedDoc(id) { this.loaded.add(id); return { doc: { getList: () => ({ toJSON: () => [] }) } }; }
    async unloadDoc(id) { this.loaded.delete(id); }
    async getDocMeta() { return undefined; }
    async destroy() { this.destroyed = true; }
  }
  class Transport {
    constructor(options) { this.options = options; }
  }
  const window = {};
  const context = vm.createContext({
    window,
    LoroRepo: Repo,
    StreamsTransportAdapter: Transport,
    decompressZstd: async (bytes) => bytes,
    createNativeFetch: () => ({ fetch: async () => {}, receive: async () => {} }),
    projectConversation: () => ({}),
    projectSessionActivity: () => 'idle',
    observeConversation: async () => {},
    cancelSession: cancel,
    archiveSession: archive,
    selectArchivedSessions,
    readLocalProjectState: extras.readLocalProjectState ?? readLocalProjectState,
    restoreArchivedSession: extras.restoreArchivedSession ?? restoreArchivedSession,
    deleteArchivedSession: extras.deleteArchivedSession ?? deleteArchivedSession,
    fetch: async () => {},
    AbortController,
  });
  vm.runInContext(source, context);
  return { window, repos, transports };
}

test('session cancellation uses the requested workspace and releases its writer', async () => {
  let request;
  const { window, repos, transports } = makeBridge(
    async () => ({ outcome: 'synced', ok: true }), [],
    async (repo, sessionID) => { request = { repo, sessionID }; return 'requested'; },
  );
  assert.equal(await window.kurageCancelSession('workspace', 'chat', 'https://gateway.lody.ai'), 'requested');
  assert.equal(request.sessionID, 'chat');
  assert.equal(request.repo, repos[0]);
  assert.equal(transports[0].metaStreamId, 'workspace:meta');
  assert.equal(repos[0].destroyed, true);
});

test('archiving uses a short-lived writer for the requested session', async () => {
  let request;
  const { window, repos } = makeBridge(async () => ({ outcome: 'synced', ok: true }), [], async () => 'requested',
    async (repo, sessionID) => {
      request = { repo, sessionID };
      return { status: 'archived', sessionIDs: ['chat', 'opened'] };
    });
  assert.deepEqual(
    JSON.parse(await window.kurageArchiveSession('workspace', 'chat', 'https://gateway.lody.ai')),
    { status: 'archived', sessionIDs: ['chat', 'opened'] },
  );
  assert.equal(request.sessionID, 'chat');
  assert.equal(request.repo, repos[0]);
  assert.equal(repos[0].destroyed, true);
});

test('archived sessions stay out of the active list and keep newest-first order', async () => {
  const rows = [
    { docId: 'session-older', meta: { isArchived: true, title: 'Older', lastMessageAt: 1 } },
    { docId: 'session-newer', meta: { isArchived: true, title: 'Newer', lastMessageAt: 5 } },
    { docId: 'session-tab', meta: { isArchived: true, parentSessionId: 'newer', title: 'Tab', lastMessageAt: 9 } },
    { docId: 'session-live', meta: { title: 'Live', lastMessageAt: 3 } },
    { docId: 'session-comment-newer', meta: { isArchived: true, title: 'Comment' } },
  ];
  const { window } = makeBridge(async () => ({ ok: true, outcome: 'synced' }), rows);
  const active = JSON.parse(await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'active'));
  const archived = JSON.parse(await window.kurageArchivedSessions('workspace', 'https://gateway.lody.ai', 'archived'));
  assert.deepEqual(active.sessions.map(session => session.id), ['live']);
  assert.deepEqual(archived.sessions.map(session => session.id), ['newer', 'older']);
  assert.equal(archived.sessions[0].canRestore, true);
});

test('restore and delete use a short-lived writer', async () => {
  let restored;
  let deleted;
  const { window, repos } = makeBridge(async () => ({ outcome: 'synced', ok: true }), [], async () => 'requested', async () => 'archived', {
    restoreArchivedSession: async (repo, workspaceID, sessionID) => {
      restored = { repo, workspaceID, sessionID };
      return 'restored';
    },
    deleteArchivedSession: async (repo, sessionID) => {
      deleted = { repo, sessionID };
      return 'deleted';
    },
  });
  assert.equal(await window.kurageRestoreArchivedSession('workspace', 'chat', 'https://gateway.lody.ai'), 'restored');
  assert.equal(await window.kurageDeleteArchivedSession('workspace', 'chat', 'https://gateway.lody.ai'), 'deleted');
  assert.equal(restored.workspaceID, 'workspace');
  assert.equal(restored.sessionID, 'chat');
  assert.equal(deleted.sessionID, 'chat');
  assert.equal(restored.repo, repos[0]);
  assert.equal(deleted.repo, repos[1]);
  assert.equal(repos[0].destroyed, true);
  assert.equal(repos[1].destroyed, true);
});

test('refresh reuses the workspace repo', async () => {
  const { window, repos, transports } = makeBridge();
  await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'first');
  await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'second');

  assert.equal(repos.length, 1);
  assert.equal(repos[0].destroyed, false);
  assert.equal(typeof transports[0].auth, 'function');

  await window.kurageSessions('another-workspace', 'https://gateway.lody.ai', 'third');
  assert.equal(repos.length, 2);
  assert.equal(repos[0].destroyed, true);
});

test('cancelling a queued refresh leaves the current workspace intact', async () => {
  let beginSync;
  const started = new Promise((resolve) => { beginSync = resolve; });
  let finishSync;
  const pendingSync = new Promise((resolve) => { finishSync = resolve; });
  let syncCount = 0;
  const { window, repos } = makeBridge(async () => {
    syncCount += 1;
    if (syncCount === 1) {
      beginSync();
      return pendingSync;
    }
    return { ok: true };
  });

  const first = window.kurageSessions('workspace', 'https://gateway.lody.ai', 'first');
  await started;
  const cancelled = window.kurageSessions('another-workspace', 'https://gateway.lody.ai', 'cancelled');
  window.kurageCancel('cancelled');
  finishSync({ ok: true });

  await first;
  await assert.rejects(cancelled, { name: 'AbortError' });
  assert.equal(syncCount, 1);
  assert.equal(repos.length, 1);
  assert.equal(repos[0].destroyed, false);
});

test('cancelling an active refresh aborts its sync', async () => {
  let beginSync;
  const started = new Promise((resolve) => { beginSync = resolve; });
  const { window } = makeBridge(({ signal }) => new Promise((_resolve, reject) => {
    beginSync();
    signal.addEventListener('abort', () => reject(signal.reason), { once: true });
  }));

  const refresh = window.kurageSessions('workspace', 'https://gateway.lody.ai', 'active');
  await started;
  window.kurageCancel('active');

  await assert.rejects(refresh, { name: 'AbortError' });
});

const localSession = {
  docId: 'session-local',
  meta: { machineId: 'machine', project: { kind: 'local', localProjectId: 'project' } },
};

test('stopping observation during metadata setup releases the next refresh', async () => {
  let beginSync;
  const started = new Promise(resolve => { beginSync = resolve; });
  let finishSync;
  let aborted = false;
  let syncCount = 0;
  const { window } = makeBridge(({ signal }) => {
    if (++syncCount > 1) return { ok: true };
    return new Promise((resolve, reject) => {
      finishSync = () => resolve({ ok: true });
      signal?.addEventListener('abort', () => {
        aborted = true;
        reject(signal.reason);
      }, { once: true });
      beginSync();
    });
  });
  const observation = window.kurageObserveConversation('workspace', 'session', 'https://gateway.lody.ai', 'observe');
  const outcome = observation.then(() => null, error => error);
  await started;
  const refresh = window.kurageSessions('workspace', 'https://gateway.lody.ai', 'refresh');
  try {
    window.kurageStopConversation('observe');
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(aborted, true);
    assert.equal((await outcome)?.name, 'AbortError');
    assert.equal(syncCount, 2);
    assert.deepEqual(JSON.parse(await refresh), { sessions: [] });
  } finally {
    finishSync();
    await Promise.allSettled([observation, refresh]);
  }
});

test('cancelling machine sync releases the queued workspace refresh', async () => {
  let beginSync;
  const started = new Promise(resolve => { beginSync = resolve; });
  let finishSync;
  let aborted = false;
  const { window, repos } = makeBridge(options => {
    if (options.scope !== 'doc' || options.flockDocIds[0] !== 'workspace:mf:machine') {
      return { ok: true };
    }
    return new Promise((resolve, reject) => {
      finishSync = () => resolve({ ok: true });
      options.signal?.addEventListener('abort', () => {
        aborted = true;
        reject(options.signal.reason);
      }, { once: true });
      beginSync();
    });
  }, [localSession]);

  const refresh = window.kurageSessions('workspace', 'https://gateway.lody.ai', 'active');
  const outcome = refresh.then(() => null, error => error);
  await started;
  const replacement = window.kurageSessions('another-workspace', 'https://gateway.lody.ai', 'next');
  try {
    window.kurageCancel('active');
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(aborted, true);
    assert.equal((await outcome)?.name, 'AbortError');
    assert.equal(repos.length, 2);
    assert.equal(repos[0].destroyed, true);
    assert.equal(JSON.parse(await replacement).sessions[0].id, 'local');
  } finally {
    finishSync();
    await Promise.allSettled([refresh, replacement]);
  }
});

test('optional machine sync failure still returns sessions with a fallback project name', async () => {
  const { window } = makeBridge(({ scope }) => {
    if (scope === 'doc') throw new Error('Machine unavailable');
    return { ok: true };
  }, [localSession]);

  const result = JSON.parse(await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'refresh'));
  assert.equal(result.sessions[0].projectName, 'Local Project');
});

test('cancelling a transcript read releases the queued conversation observation', async () => {
  const started = Promise.withResolvers();
  let aborted = false;
  const { window } = makeBridge(options => {
    if (options.scope !== 'doc') return { ok: true };
    assert.deepEqual(Array.from(options.docIds), ['session-chat']);
    started.resolve();
    return new Promise((_resolve, reject) => {
      options.signal.addEventListener('abort', () => {
        aborted = true;
        reject(options.signal.reason);
      }, { once: true });
    });
  }, [{ docId: 'session-chat', meta: {} }]);
  const read = window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'search');
  const outcome = assert.rejects(read, { name: 'AbortError' });
  await started.promise;
  const observation = window.kurageObserveConversation('workspace', 'chat', 'https://gateway.lody.ai', 'observe');
  window.kurageCancel('search');
  await outcome;
  await observation;
  assert.equal(aborted, true);
});

test('cancelling a queued transcript read skips document sync', async () => {
  const started = Promise.withResolvers();
  const finish = Promise.withResolvers();
  let syncs = 0;
  const { window } = makeBridge(() => {
    syncs += 1;
    started.resolve();
    return finish.promise;
  }, [{ docId: 'session-chat', meta: {} }]);
  const refresh = window.kurageSessions('workspace', 'https://gateway.lody.ai', 'refresh');
  await started.promise;
  const read = window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'search');
  const outcome = assert.rejects(read, { name: 'AbortError' });
  window.kurageCancel('search');
  finish.resolve({ ok: true });
  await refresh;
  await outcome;
  assert.equal(syncs, 1);
});


test('one-shot reads release all loaded transcripts on success and sync failure', async () => {
  let fail = false;
  const { window, repos } = makeBridge(async () => {
    if (fail) throw new Error('offline');
    return { ok: true };
  }, ['a', 'b', 'c'].map(id => ({ docId: `session-${id}`, meta: {} })));
  for (const id of ['a', 'b', 'c']) {
    await window.kurageConversation('workspace', id, 'https://gateway.lody.ai', id);
    assert.equal(repos[0].loaded.size, 0);
  }
  fail = true;
  await assert.rejects(window.kurageConversation('workspace', 'a', 'https://gateway.lody.ai', 'failure'), /offline/);
  assert.equal(repos[0].loaded.size, 0);
});

test('a one-shot read does not unload an observed conversation', async () => {
  const { window, repos } = makeBridge(async () => ({ ok: true }),
    [{ docId: 'session-chat', meta: {} }]);
  await window.kurageObserveConversation('workspace', 'chat', 'https://gateway.lody.ai', 'observe');
  await window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'read');
  assert.equal(repos[0].loaded.has('session-chat'), true);
  window.kurageStopConversation('observe');
  await window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'read-again');
  assert.equal(repos[0].loaded.size, 0);
});


test('cancelling an unobserved search read unloads its document', async () => {
  const started = Promise.withResolvers();
  const { window, repos } = makeBridge(options => {
    if (options.scope !== 'doc') return { ok: true };
    started.resolve();
    return new Promise((_resolve, reject) => {
      options.signal.addEventListener('abort', () => reject(options.signal.reason), { once: true });
    });
  }, [{ docId: 'session-chat', meta: {} }]);
  const read = window.kurageConversation('workspace', 'chat', 'https://gateway.lody.ai', 'search');
  const outcome = assert.rejects(read, { name: 'AbortError' });
  await started.promise;
  window.kurageCancel('search');
  await outcome;
  assert.equal(repos[0].loaded.size, 0);
});
