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

function repo(rows = [], pending = false, meta = { machineId: 'mac' }) {
  return {
    listDoc: async () => [{ docId: 'session-template', meta }, ...rows],
    openFlockDoc: async () => ({ flock: { scan: ({ prefix }) => prefix[0] === 'localProject'
      ? [{ key: ['localProject', 'p'], value: { name: 'Project' } }]
      : pending ? [{ key: ['cmd', 'deleteLocalProject', 'p'] }] : [] } }),
    sync: async () => ({ ok: true }), getDocMeta: async () => null,
  };
}

test('source validates machine, project registration and pending deletion', async () => {
  const resolved = await projectGitSource(repo(), 'ws', 'template', 'local:mac:p', signal());
  assert.equal(resolved.machineID, source.machineID);
  assert.equal(resolved.localProjectID, source.localProjectID);
  assert.equal(resolved.sessionGit.matchesProject, false);
  for (const project of ['local:other:p', 'local:mac:missing', 'github:owner/repo']) {
    await assert.rejects(projectGitSource(repo(), 'ws', 'template', project, signal()));
  }
  await assert.rejects(projectGitSource(repo([], true), 'ws', 'template', 'local:mac:p', signal()));
});

test('Git state reading carries user and workspace and projects live working-tree flags', async () => {
  const result = await read(async (_access, ws, machine, method, params) => {
    assert.equal(ws, 'ws'); assert.equal(machine, 'mac'); assert.equal(method, 'local-project/git-state');
    assert.deepEqual(params, { localProjectId: 'p', requestedByUserId: 'user' });
    return response();
  });
  assert.deepEqual(result.state, { git: true, currentBranch: main, workingTree: state().workingTree,
    sessionDirectoryMatchesProject: false });
  assert.equal(result.state.currentBranch, main);
  assert.equal((await read(async () => response({ state: { git: false } }))).state.git, false);
  assert.equal((await read(async () => response({ state: state({ currentBranch: null }) }))).state.currentBranch, null);
});

const ownerMeta = () => ({ machineId: 'mac', project: { kind: 'local', localProjectId: 'p', githubRepoFullName: 'demo/repo' },
  branchName: 'feature/client', workspaceUnpushed: true, diffStats: { allChange: { add: 2, del: 0 } } });
const liveFeature = (values = {}) => state({ currentBranch: feature, defaultBranch: main, githubRepoFullName: 'demo/repo', ...values });
const resolve = (meta = ownerMeta(), rows = []) => projectGitSource(repo(rows, false, meta), 'ws', 'template', 'local:mac:p', signal());

test('matching root metadata supplies independent unpublished and committed-change hints', async () => {
  const resolved = await resolve();
  const result = await read(async () => response({ state: liveFeature() }), resolved);
  assert.equal(result.state.defaultBranch, main);
  assert.equal(result.state.githubRepoFullName, 'demo/repo');
  assert.equal(result.state.hasUnpushedCommits, true);
  assert.equal(result.state.hasBranchChanges, true);
  assert.equal(result.state.hasOpenPR, false);
  assert.equal(result.state.sessionDirectoryMatchesProject, true);
  const dirty = await read(async () => response({ state: liveFeature({
    workingTree: { ...state().workingTree, clean: false, untracked: true },
  }) }), resolved);
  assert.equal(dirty.state.hasBranchChanges, undefined);
  assert.equal(dirty.state.workingTree.untracked, true);
  assert.equal(dirty.state.hasUnpushedCommits, true);
});

test('zero line counts leave branch changes unknown without hiding other publishing hints', async () => {
  // Binary, mode-only and empty-file diffs can all have these valid line totals.
  const resolved = await resolve({ ...ownerMeta(), workspaceUnpushed: false,
    diffStats: { allChange: { add: 0, del: 0 } },
  });
  const result = await read(async () => response({ state: liveFeature() }), resolved);
  assert.equal(result.state.sessionDirectoryMatchesProject, true);
  assert.equal(result.state.hasBranchChanges, undefined);
  assert.equal(result.state.hasUnpushedCommits, false);
  assert.equal(result.state.hasOpenPR, false);
});

test('plain and exact local branch selectors retain publishing hints and suppress existing PRs', async () => {
  for (const [currentBranch, name] of [
    ['feature/client', 'feature/client'],
    [feature, 'feature/client'],
    ['feature/%2Fclient', 'feature/%2Fclient'],
    ['lody:branch:local:feature%2F%252Fclient', 'feature/%2Fclient'],
  ]) {
    const resolved = await resolve({ ...ownerMeta(), branchName: name,
      pullRequests: [{ url: 'https://github.com/demo/repo/pull/1', status: 'open' }],
    });
    const result = await read(async () => response({ state: liveFeature({ currentBranch }) }), resolved);
    assert.equal(result.state.currentBranch, currentBranch);
    assert.equal(result.state.hasUnpushedCommits, true);
    assert.equal(result.state.hasBranchChanges, true);
    assert.equal(result.state.hasOpenPR, true);
  }
});

test('branch, repository, project and worktree mismatches never borrow publishing hints', async () => {
  for (const meta of [
    { ...ownerMeta(), branchName: 'old-branch' },
    { ...ownerMeta(), project: { ...ownerMeta().project, githubRepoFullName: 'other/repo' } },
    { ...ownerMeta(), project: { kind: 'local', localProjectId: 'other' } },
    { ...ownerMeta(), isWorktree: true },
  ]) {
    const result = await read(async () => response({ state: liveFeature() }), await resolve(meta));
    assert.equal(result.state.hasUnpushedCommits, undefined);
    assert.equal(result.state.hasBranchChanges, undefined);
    assert.equal(result.state.hasOpenPR, undefined);
  }
  for (const currentBranch of [null, 'other', 'lody:branch:local:other',
    'lody:branch:local:', 'lody:branch:local:%FF', 'lody:branch:remote:origin:feature%2Fclient']) {
    const result = await read(async () => response({ state: liveFeature({ currentBranch }) }), await resolve());
    assert.equal(result.state.hasUnpushedCommits, undefined);
    assert.equal(result.state.hasBranchChanges, undefined);
    assert.equal(result.state.hasOpenPR, undefined);
  }
});

test('PR suppression includes same-branch project roots but excludes closed PRs and other scopes', async () => {
  const pr = { url: 'https://github.com/demo/repo/pull/1', status: 'open' };
  for (const status of ['open', 'draft', 'closed', 'merged']) {
    const result = await read(async () => response({ state: liveFeature() }), await resolve({
      ...ownerMeta(), pullRequests: [{ ...pr, status }],
    }));
    assert.equal(result.state.hasOpenPR, status === 'open' || status === 'draft');
  }
  const record = { docId: 'session-peer', meta: { ...ownerMeta(), pullRequests: [pr] } };
  const peer = await read(async () => response({ state: liveFeature() }), await resolve(ownerMeta(), [record]));
  assert.equal(peer.state.hasOpenPR, true);
  for (const row of [
    { ...record, deleted: true },
    { ...record, meta: { ...record.meta, machineId: 'other' } },
    { ...record, meta: { ...record.meta, branchName: 'other' } },
    { ...record, meta: { ...record.meta, parentSessionId: 'other' } },
    { ...record, meta: { ...record.meta, isWorktree: true } },
    { ...record, meta: { ...record.meta, project: { kind: 'local', localProjectId: 'other' } } },
  ]) {
    const result = await read(async () => response({ state: liveFeature() }), await resolve(ownerMeta(), [row]));
    assert.equal(result.state.hasOpenPR, false);
  }
});

test('absent or malformed optional Git fields preserve branch reading without inventing actions', async () => {
  for (const workingTree of [undefined, { clean: true }, { ...state().workingTree, untracked: 'true' },
    { ...state().workingTree, staged: true }]) {
    const result = await read(async () => response({ state: liveFeature({ workingTree }) }), await resolve());
    assert.equal(result.state.currentBranch, feature);
    assert.equal(result.state.workingTree, undefined);
    assert.equal(result.state.hasBranchChanges, undefined);
  }
  const result = await read(async () => response({ state: liveFeature() }), await resolve({
    ...ownerMeta(), workspaceUnpushed: undefined, diffStats: { allChange: { add: '2', del: 0 } },
  }));
  assert.equal(result.state.hasUnpushedCommits, undefined);
  assert.equal(result.state.hasBranchChanges, undefined);
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
