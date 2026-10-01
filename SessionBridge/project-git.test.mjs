import assert from 'node:assert/strict';
import test from 'node:test';
import { projectGitSource, readProjectGit } from './project-git.mjs';

const source = { machineID: 'mac', localProjectID: 'p' };
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

test('Git state reading carries user and workspace and projects only the current branch', async () => {
  const result = await read(async (_access, ws, machine, method, params) => {
    assert.equal(ws, 'ws'); assert.equal(machine, 'mac'); assert.equal(method, 'local-project/git-state');
    assert.deepEqual(params, { localProjectId: 'p', requestedByUserId: 'user' });
    return response();
  });
  assert.deepEqual(result.state, { git: true, currentBranch: main });
  assert.equal(result.state.currentBranch, main);
  assert.equal((await read(async () => response({ state: { git: false } }))).state.git, false);
  assert.equal((await read(async () => response({ state: state({ currentBranch: null }) }))).state.currentBranch, null);
});

test('mismatched scope, invalid state, denial and unsupported methods do not publish data', async () => {
  for (const values of [{ machineId: 'other' }, { workspaceId: 'other' }, { localProjectId: 'other' },
    { state: state({ currentBranch: 42 }) }, { state: state({ currentBranch: '' }) },
    { state: state({ currentBranch: undefined }) }, { success: 'true' }]) {
    assert.deepEqual(await read(async () => response(values)), { failure: 'unavailable' });
  }
  assert.deepEqual(await read(async () => response({ success: false, error: 'access_denied' })), { failure: 'access_denied' });
  assert.deepEqual(await read(async () => { throw Object.assign(new Error(), { code: 'method_unavailable' }); }), { failure: 'unsupported' });
});

test('missing user access never starts a machine request', async () => {
  const result = await readProjectGit(source, access, 'ws', null, signal(), async () => {
    assert.fail('Machine request must not be sent');
  });
  assert.deepEqual(result, { failure: 'access_denied' });
});

test('cancellation discards late Git state replies', async () => {
  const controller = new AbortController();
  await assert.rejects(read(async () => { controller.abort(); return response(); }, source, controller.signal), { name: 'AbortError' });
});
