import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const source = (await readFile(new URL('./bridge.js', import.meta.url), 'utf8'))
  .replace(/^import .*;\n/gm, '');

function makeBridge(sync = async () => ({ ok: true })) {
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
    async listDoc() { return []; }
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
    observeConversation: async () => {},
    fetch: async () => {},
    AbortController,
  });
  vm.runInContext(source, context);
  return { window, repos, transports };
}

test('refresh reuses the workspace repo', async () => {
  const { window, repos, transports } = makeBridge();
  await window.kurageSessions('workspace', 'first', 'https://gateway.lody.ai', 'first');
  await window.kurageSessions('workspace', 'second', 'https://gateway.lody.ai', 'second');

  assert.equal(repos.length, 1);
  assert.equal(repos[0].destroyed, false);
  assert.equal(typeof transports[0].auth, 'function');

  await window.kurageSessions('another-workspace', 'third', 'https://gateway.lody.ai', 'third');
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

  const first = window.kurageSessions('workspace', 'first', 'https://gateway.lody.ai', 'first');
  await started;
  const cancelled = window.kurageSessions('another-workspace', 'cancelled', 'https://gateway.lody.ai', 'cancelled');
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

  const refresh = window.kurageSessions('workspace', 'active', 'https://gateway.lody.ai', 'active');
  await started;
  window.kurageCancel('active');

  await assert.rejects(refresh, { name: 'AbortError' });
});
