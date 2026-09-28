import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';
import { readSyncedConversation } from './conversation-observer.mjs';
import {
  activityTime,
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
    readSyncedConversation,
    cancelSession: cancel,
    newSessionOptions: extras.newSessionOptions,
    archiveSession: archive,
    updateSessionMetadata: extras.updateSessionMetadata,
    respondQuestion: extras.respondQuestion,
    activityTime,
    selectArchivedSessions,
    readLocalProjectState: extras.readLocalProjectState ?? readLocalProjectState,
    restoreArchivedSession: extras.restoreArchivedSession ?? restoreArchivedSession,
    deleteArchivedSession: extras.deleteArchivedSession ?? deleteArchivedSession,
    mentionSkills: extras.mentionSkills,
    fetch: async () => {},
    AbortController,
    setTimeout,
    clearTimeout,
  });
  vm.runInContext(source, context);
  return { window, repos, transports };
}

test('mention sessions stay in the current project and include child sessions', async () => {
  const rows = [
    { docId: 'session-current', meta: { machineId: 'machine', project: { kind: 'local', localProjectId: 'project' }, title: 'Current', lastMessageAt: 8 } },
    { docId: 'session-child', meta: { machineId: 'machine', project: { kind: 'local', localProjectId: 'project' }, parentSessionId: 'current', title: 'Review', lastMessageAt: 9 } },
    { docId: 'session-root', meta: { machineId: 'machine', project: { kind: 'local', localProjectId: 'project' }, title: 'Other', lastMessageAt: 7 } },
    { docId: 'session-archived', meta: { machineId: 'machine', project: { kind: 'local', localProjectId: 'project' }, title: 'Archived', isArchived: true } },
    { docId: 'session-other-project', meta: { machineId: 'machine', project: { kind: 'local', localProjectId: 'other' }, title: 'Elsewhere' } },
  ];
  const { window } = makeBridge(async () => ({ ok: true }), rows);
  const result = JSON.parse(await window.kurageMentionSessions('workspace', 'https://gateway.lody.ai',
    'current', 'local:machine:project', 'request'));
  assert.deepEqual(result.sessions.map(session => session.id), ['child', 'root']);
});

test('skill request uses the template machine, project, agent, workspace and user', async () => {
  let request;
  const rows = [{ docId: 'session-template', meta: {
    machineId: 'machine', agentConfigId: 'config', agentType: 'codex',
    project: { kind: 'local', localProjectId: 'project' },
  } }];
  const { window } = makeBridge(async () => ({ ok: true }), rows, undefined, undefined, {
    mentionSkills: async args => { request = args; return [{ token: 'review', name: 'Review', description: '', path: 'review/SKILL.md' }]; },
  });
  const result = JSON.parse(await window.kurageMentionSkills('workspace', 'https://gateway.lody.ai',
    'template', null, 'user', 'request'));
  assert.equal(result.skills[0].token, 'review');
  assert.equal(request.workspaceID, 'workspace');
  assert.equal(request.machineID, 'machine');
  assert.equal(request.localProjectID, 'project');
  assert.equal(request.agentType, 'codex');
  assert.equal(request.userID, 'user');
});

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

test('session list includes the machine name and pin from workspace metadata', async () => {
  const rows = [
    { ...localSession, meta: { ...localSession.meta, isPinned: true, lastMessageAt: 200, lastReadAt: 100 } },
    { docId: 'machine-machine', meta: { name: 'spike@mac' } },
  ];
  const { window } = makeBridge(async () => ({ ok: true }), rows);

  const result = JSON.parse(await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'refresh'));
  assert.equal(result.sessions[0].machineName, 'spike@mac');
  assert.equal(result.sessions[0].isPinned, true);
  assert.equal(result.sessions[0].lastMessageAt, 200);
  assert.equal(result.sessions[0].lastReadAt, 100);
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


test('new-session options cancel metadata sync and destroy the temporary reader', async () => {
  let entered;
  const ready = new Promise(resolve => { entered = resolve; });
  let observedSignal;
  const { window, repos } = makeBridge(async ({ signal }) => {
    observedSignal = signal;
    entered();
    await new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
  });
  const pending = window.kurageNewSessionOptions('ws', 'template', null, 'https://gateway.lody.ai', 'options-1');
  await ready;
  window.kurageCancel('options-1');
  await assert.rejects(pending, { name: 'AbortError' });
  assert.equal(observedSignal.aborted, true);
  assert.equal(repos[0].destroyed, true);
});

test('new-session options forward cancellation after metadata sync and release their reader', async () => {
  let entered;
  const ready = new Promise(resolve => { entered = resolve; });
  const { window, repos } = makeBridge(async () => ({ ok: true, outcome: 'synced' }), [], undefined, undefined, {
    newSessionOptions: async (repo, workspace, template, agent, signal) => {
      assert.equal(workspace, 'ws');
      assert.equal(template, 'template');
      entered();
      await new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
    },
  });
  const pending = window.kurageNewSessionOptions('ws', 'template', null, 'https://gateway.lody.ai', 'options-2');
  await ready;
  window.kurageCancel('options-2');
  await assert.rejects(pending, { name: 'AbortError' });
  assert.equal(repos[0].destroyed, true);
});


test('metadata edits use the requested workspace and release their replica on success or failure', async () => {
  for (const fails of [false, true]) {
    let request;
    const { window, repos, transports } = makeBridge(async () => ({ outcome: 'synced' }), [], undefined, undefined, {
      updateSessionMetadata: async (repo, sessionID, change) => {
        request = { repo, sessionID, change };
        if (fails) throw new Error('write failed');
        return 'updated';
      },
    });
    const operation = window.kurageUpdateSessionMetadata('workspace-other', 'chat', 'https://gateway.lody.ai', { isPinned: true });
    if (fails) await assert.rejects(operation, /write failed/);
    else assert.equal(await operation, 'updated');
    assert.equal(request.sessionID, 'chat');
    assert.equal(request.repo, repos[0]);
    assert.equal(request.change.isPinned, true);
    assert.equal(repos[0].destroyed, true);
    assert.equal(transports[0].metaStreamId, 'workspace-other:meta');
  }
});

for (const phase of ['initial sync', 'write sync']) {
  test(`metadata cancellation during ${phase} aborts and releases its replica`, async () => {
    const started = Promise.withResolvers();
    let observedSignal;
    let writes = 0;
    const waitForCancellation = async signal => {
      observedSignal = signal;
      started.resolve();
      await new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
    };
    const { window, repos } = makeBridge(async ({ signal }) => {
      if (phase === 'initial sync') await waitForCancellation(signal);
      return { outcome: 'synced' };
    }, [], undefined, undefined, {
      updateSessionMetadata: async (repo, sessionID, change, signal) => {
        writes++;
        await waitForCancellation(signal);
      },
    });
    const pending = window.kurageUpdateSessionMetadata('ws', 'chat', 'https://gateway.lody.ai', { isPinned: true }, 'edit');
    await started.promise;
    window.kurageCancel('edit');
    await assert.rejects(pending, { name: 'AbortError' });
    assert.equal(observedSignal.aborted, true);
    assert.equal(writes, phase === 'initial sync' ? 0 : 1);
    assert.equal(repos[0].destroyed, true);
  });
}

test('metadata cancellation prevents writes even when initial sync completes successfully after abort', async () => {
  const started = Promise.withResolvers();
  const sync = Promise.withResolvers();
  const { window, repos } = makeBridge(() => {
    started.resolve();
    return sync.promise;
  }, [], undefined, undefined, {
    updateSessionMetadata: async () => assert.fail('unexpected metadata write'),
  });
  const pending = window.kurageUpdateSessionMetadata('ws', 'chat', 'https://gateway.lody.ai', { title: 'New' }, 'edit');
  await started.promise;
  window.kurageCancel('edit');
  sync.resolve({ outcome: 'synced' });
  await assert.rejects(pending, { name: 'AbortError' });
  assert.equal(repos[0].destroyed, true);
});


test('session list preserves the creation-time sorting fallback without inventing a message marker', async () => {
  const { window } = makeBridge(async () => ({ ok: true }), [
    { ...localSession, meta: { ...localSession.meta, lastMessageAt: undefined, createdAt: '2026-01-01T00:00:00Z' } },
  ]);
  const result = JSON.parse(await window.kurageSessions('workspace', 'https://gateway.lody.ai', 'refresh'));
  assert.equal(result.sessions[0].lastMessageAt, null);
  assert.equal(result.sessions[0].lastActivityAt, Date.parse('2026-01-01T00:00:00Z'));
});


test('question writes scope requests and cancellation to an ephemeral existing-stream replica', async () => {
  let entered, signal, args;
  const started = new Promise(resolve => { entered = resolve; });
  const { window, repos, transports } = makeBridge(async () => ({ outcome: 'synced' }), [], undefined, undefined, {
    respondQuestion: async (...values) => {
      args = values;
      signal = values.at(-1);
      entered();
      await new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
    },
  });
  const pending = window.kurageRespondQuestion('workspace-a', 'chat', 'https://example.test', 'turn', 'request', { q: 'Answer' }, 'operation');
  await started;
  assert.equal(transports[0].metaStreamId, 'workspace-a:meta');
  assert.equal(transports[0].createStreamIfMissing, false);
  assert.deepEqual(args.slice(1, 5), ['chat', 'turn', 'request', { q: 'Answer' }]);
  window.kurageCancel('operation');
  await assert.rejects(pending, { name: 'AbortError' });
  assert.equal(signal.aborted, true);
  assert.equal(repos[0].destroyed, true);
});
