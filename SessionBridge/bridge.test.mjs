import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const source = (await readFile(new URL('./bridge.js', import.meta.url), 'utf8'))
  .replace(/^import .*;\n/gm, '');

function makeBridge(sync = async () => ({ ok: true }), rows = []) {
  const repos = [];
  const transports = [];
  class Repo {
    constructor() { this.destroyed = false; }
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
    fetch: async () => {},
    AbortController,
  });
  vm.runInContext(source, context);
  return { window, repos, transports };
}

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
