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
    fetch: async () => {},
    AbortController,
  });
  vm.runInContext(source, context);
  return { window, repos, transports };
}

test('refresh reuses the workspace repo and updates its proxy credential', async () => {
  const { window, repos, transports } = makeBridge();
  await window.kurageSessions('first', 'workspace', 'https://gateway.lody.ai');
  await window.kurageSessions('second', 'workspace', 'https://gateway.lody.ai');

  assert.equal(repos.length, 1);
  assert.equal(repos[0].destroyed, false);
  assert.equal(await transports[0].auth(), 'second');

  await window.kurageSessions('third', 'another-workspace', 'https://gateway.lody.ai');
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

  const first = window.kurageSessions('first', 'workspace', 'https://gateway.lody.ai');
  await started;
  const cancelled = window.kurageSessions('cancelled', 'another-workspace', 'https://gateway.lody.ai');
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

  const refresh = window.kurageSessions('active', 'workspace', 'https://gateway.lody.ai');
  await started;
  window.kurageCancel('active');

  await assert.rejects(refresh, { name: 'AbortError' });
});
