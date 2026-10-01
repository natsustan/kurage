import assert from 'node:assert/strict';
import test from 'node:test';
import { projectGitSource, readProjectGit, switchProjectBranch } from './project-git.mjs';

const source = { machineID: 'mac', localProjectID: 'p', busy: false };
const access = { baseURL: 'https://streams.test', auth: async () => 'token' };
const signal = () => new AbortController().signal;
const main = 'lody:branch:local:main';
const feature = 'lody:branch:local:feature%2Fclient';
const remote = 'lody:branch:remote:origin:develop';
const state = (values = {}) => ({ git: true, currentBranch: main, branches: [main, feature, remote],
  workingTree: { clean: true, staged: false, unstaged: false, untracked: false, conflicted: false }, ...values });
const response = (values = {}) => ({ type: 'local-project/git-state_response', machineId: 'mac',
  workspaceId: 'ws', localProjectId: 'p', success: true, observedAtMs: 1, state: state(), ...values });
const read = (rpc, target = source, abort = signal()) => readProjectGit(target, access, 'ws', 'user', abort, rpc);
const change = (rpc, branch = feature, target = source, abort = signal()) =>
  switchProjectBranch(target, access, 'ws', 'user', branch, abort, rpc);

function repo(rows = [], pending = false) {
  return {
    listDoc: async () => [{ docId: 'session-template', meta: { machineId: 'mac' } }, ...rows],
    openFlockDoc: async () => ({ flock: { scan: ({ prefix }) => prefix[0] === 'localProject'
      ? [{ key: ['localProject', 'p'], value: { name: 'Project' } }]
      : pending ? [{ key: ['cmd', 'deleteLocalProject', 'p'] }] : [] } }),
    sync: async () => ({ ok: true }), getDocMeta: async () => null,
  };
}

test('source validates machine, project registration and pending deletion', async () => {
  assert.deepEqual(await projectGitSource(repo(), 'ws', 'template', 'local:mac:p', signal()), source);
  for (const project of ['local:other:p', 'local:mac:missing', 'github:owner/repo']) {
    await assert.rejects(projectGitSource(repo(), 'ws', 'template', project, signal()));
  }
  await assert.rejects(projectGitSource(repo([], true), 'ws', 'template', 'local:mac:p', signal()));
});

test('busy check covers tabs, processing, pending dispatch and steer, but retires suppressed inputs', async () => {
  for (const fields of [{ status: { type: 'running' } }, { processingUserMsgId: 'u' },
    { latestUserMsgId: 'u' }, { steerTurnStatuses: { u: 'pending' } }]) {
    const rows = [{ docId: 'session-tab', meta: { machineId: 'mac', parentSessionId: 'template',
      project: { kind: 'local', localProjectId: 'p' }, ...fields } }];
    assert.equal((await projectGitSource(repo(rows), 'ws', 'template', 'local:mac:p', signal())).busy, true);
  }
  for (const fields of [{ lastHandledUserMsgId: 'u' }, { lastMissingHistoryUserMsgId: 'u' }, { settledActivationUserMsgId: 'u' }]) {
    const rows = [{ docId: 'session-idle', meta: { machineId: 'mac', latestUserMsgId: 'u',
      project: { kind: 'local', localProjectId: 'p' }, ...fields } }];
    assert.equal((await projectGitSource(repo(rows), 'ws', 'template', 'local:mac:p', signal())).busy, false);
  }
});

test('Git state request carries user and workspace and preserves exact local/remote selectors', async () => {
  const result = await read(async (_access, ws, machine, method, params) => {
    assert.equal(ws, 'ws'); assert.equal(machine, 'mac'); assert.equal(method, 'local-project/git-state');
    assert.deepEqual(params, { localProjectId: 'p', requestedByUserId: 'user' });
    return response();
  });
  assert.deepEqual(result.state.branches, [main, feature, remote]);
  assert.equal(result.state.currentBranch, main);
  assert.equal((await read(async () => response({ state: { git: false } }))).state.git, false);
  assert.equal((await read(async () => response({ state: state({ currentBranch: null }) }))).state.currentBranch, null);
});

test('mismatched scope, invalid state, denial and unsupported methods do not publish data', async () => {
  for (const values of [{ machineId: 'other' }, { workspaceId: 'other' }, { localProjectId: 'other' },
    { state: state({ workingTree: {} }) }, { state: state({ branches: [42] }) }]) {
    assert.deepEqual(await read(async () => response(values)), { failure: 'unavailable' });
  }
  assert.deepEqual(await read(async () => response({ success: false, error: 'access_denied' })), { failure: 'access_denied' });
  assert.deepEqual(await read(async () => { throw Object.assign(new Error(), { code: 'method_unavailable' }); }), { failure: 'unsupported' });
});

test('switch revalidates dirty, busy, missing branches and same-branch no-op without mutating', async () => {
  for (const [snapshot, target, branch, failure] of [
    [state({ workingTree: { clean: false, staged: false, unstaged: true, untracked: false, conflicted: false } }), source, feature, 'local_changes'],
    [state(), { ...source, busy: true }, feature, 'busy'],
    [state(), source, 'deleted', 'branch_missing'], [state(), source, main, undefined],
  ]) {
    let calls = 0;
    const result = await change(async (_a, _w, _m, method) => {
      assert.equal(method, 'local-project/git-state'); calls++; return response({ state: snapshot });
    }, branch, target);
    assert.equal(result.failure, failure); assert.equal(calls, 1);
  }
});

test('remote checkout sends the exact control schema and displays the resulting local branch', async () => {
  let calls = 0;
  const result = await change(async (_a, _w, _m, method, params) => {
    calls++;
    if (method === 'local-project/control') {
      assert.deepEqual(params, { request: { type: 'local-project/checkout-branch', machineId: 'mac',
        workspaceId: 'ws', localProjectId: 'p', branchName: remote } });
      return { ok: true, type: 'local-project/checkout-branch', result: { success: true, currentBranch: 'develop' } };
    }
    return response({ state: state(calls === 1 ? {} : { currentBranch: 'lody:branch:local:develop' }) });
  }, remote);
  assert.equal(calls, 3); assert.equal(result.state.currentBranch, 'lody:branch:local:develop');
  assert.equal(result.failure, undefined);
});

test('a session starting during Git state loading prevents checkout at the metadata recheck', async () => {
  let mutations = 0;
  const result = await switchProjectBranch(source, access, 'ws', 'user', feature, signal(), async (_a, _w, _m, method) => {
    if (method === 'local-project/control') mutations++;
    return response();
  }, async () => ({ ...source, busy: true }));
  assert.equal(mutations, 0); assert.equal(result.failure, 'busy');
});

test('lost checkout reply and machine rejection refresh actual state without replaying mutation', async () => {
  for (const lost of [true, false]) {
    let mutations = 0;
    const result = await change(async (_a, _w, _m, method) => {
      if (method === 'local-project/control') {
        mutations++;
        if (lost) throw new Error('reply lost');
        return { ok: true, type: 'local-project/checkout-branch', result: { success: false, error: 'dirty' } };
      }
      return response({ state: state(mutations ? { currentBranch: feature } : {}) });
    });
    assert.equal(mutations, 1); assert.equal(result.state.currentBranch, feature);
    assert.equal(result.failure, lost ? 'switch_unconfirmed' : 'switch_failed');
  }
});

test('cancellation prevents checkout and late replies from publishing state', async () => {
  const controller = new AbortController();
  await assert.rejects(change(async () => { controller.abort(); return response(); }, feature, source, controller.signal), { name: 'AbortError' });
  const second = new AbortController();
  await assert.rejects(change(async (_a, _w, _m, method) => {
    if (method === 'local-project/control') second.abort();
    return response();
  }, feature, source, second.signal), { name: 'AbortError' });
});
