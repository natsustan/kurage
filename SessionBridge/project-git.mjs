import { requestMachine } from './machine-rpc.mjs';
import { readLocalProjectState } from './session-archive.mjs';

// Resolve the registered project, never accept a client-supplied filesystem path.
export async function projectGitSource(repo, workspaceID, templateSessionID, projectID, signal, cache) {
  signal.throwIfAborted();
  const rows = await repo.listDoc();
  const template = rows.find(row => row.docId === `session-${templateSessionID}` &&
    !row.deleted && !row.meta?.isArchived && !row.meta?.parentSessionId);
  const machineID = template?.meta?.machineId;
  const prefix = `local:${machineID}:`;
  if (!machineID || typeof projectID !== 'string' || !projectID.startsWith(prefix)) {
    throw new Error('Project does not belong to the template machine');
  }
  const localProjectID = projectID.slice(prefix.length);
  const flockID = `${workspaceID}:mf:${machineID}`;
  let flock = cache?.machine(flockID);
  // Git reads always reach the machine; only reuse a fresh directory catalog.
  if (cache?.needsRefresh) flock = undefined;
  if (!flock) {
    const document = await repo.openFlockDoc(flockID);
    const report = await repo.sync({ scope: 'doc', flockDocIds: [flockID], requireTransports: ['cloud'], signal });
    signal.throwIfAborted();
    if (!report?.ok && report?.outcome !== 'synced') throw new Error('Project catalog sync failed');
    flock = document.flock;
    cache?.rememberMachine(flockID, flock);
  }
  const catalog = await readLocalProjectState(repo, workspaceID, machineID, signal, flock);
  signal.throwIfAborted();
  if (!catalog.known || !catalog.projects.has(localProjectID) || catalog.pending.has(localProjectID)) {
    throw new Error('Project is unavailable');
  }
  const matchesProject = template.meta.project?.kind === 'local' &&
    template.meta.project.localProjectId === localProjectID && template.meta.isWorktree !== true;
  // Only the root owns the shared directory's Git hints. Never borrow metadata
  // from a different selected project or a worktree at another path.
  const meta = matchesProject ? template.meta : null;
  const related = rows.filter(row => !row.deleted && !row.meta?.isArchived &&
    !row.meta?.parentSessionId && row.meta?.machineId === machineID &&
    row.meta?.project?.kind === 'local' && row.meta.project.localProjectId === localProjectID &&
    row.meta.isWorktree !== true);
  return { machineID, localProjectID, sessionGit: {
    matchesProject,
    branchName: meta?.branchName,
    repoFullName: meta?.project?.githubRepoFullName ?? meta?.repoFullName,
    unpushed: meta?.workspaceUnpushed,
    allChange: meta?.diffStats?.allChange,
    pullRequests: related.map(row => ({ branchName: row.meta.branchName,
      repoFullName: row.meta.project.githubRepoFullName ?? row.meta.repoFullName,
      items: row.meta.pullRequests })),
  } };
}

function branchName(selector) {
  if (typeof selector !== 'string') return null;
  const local = 'lody:branch:local:';
  if (!selector.startsWith(local)) return null;
  try { return decodeURIComponent(selector.slice(local.length)); } catch { return null; }
}

function projectGitHints(source, state) {
  const result = { sessionDirectoryMatchesProject: source.sessionGit?.matchesProject === true };
  const context = source.sessionGit;
  const branch = branchName(state.currentBranch);
  if (!context?.matchesProject || !branch || context.branchName !== branch) return result;
  if (typeof context.repoFullName === 'string' &&
      context.repoFullName.toLowerCase() !== state.githubRepoFullName?.toLowerCase()) return result;
  if (typeof context.unpushed === 'boolean') result.hasUnpushedCommits = context.unpushed;
  const change = context.allChange;
  // allChange covers the working tree too. Only a clean live tree lets us use
  // this scanner statistic as a hint for committed changes against the base.
  if (state.workingTree?.clean === true && Number.isFinite(change?.add) && change.add >= 0 &&
      Number.isFinite(change?.del) && change.del >= 0) {
    result.hasBranchChanges = change.add + change.del > 0;
  }
  const repo = state.githubRepoFullName?.toLowerCase();
  if (repo && typeof context.repoFullName === 'string' && context.repoFullName.toLowerCase() === repo) {
    result.hasOpenPR = (context.pullRequests ?? []).some(record => record.branchName === branch &&
      typeof record.repoFullName === 'string' && record.repoFullName.toLowerCase() === repo &&
      Array.isArray(record.items) && record.items.some(pr =>
        (pr?.status === 'open' || pr?.status === 'draft') &&
        typeof pr.url === 'string' && pr.url.toLowerCase().startsWith(`https://github.com/${repo}/pull/`)));
  }
  return result;
}

function rpcFailure(error) {
  if (error?.code === 'method_unavailable' || error?.code === -32601) return 'unsupported';
  if (error?.code === 'access_denied' || error?.code === 'permission_denied') return 'access_denied';
  return 'unavailable';
}

export async function readProjectGit(source, access, workspaceID, userID, signal, request = requestMachine) {
  signal.throwIfAborted();
  if (!userID) return { failure: 'access_denied' };
  let response;
  try {
    response = await request(access, workspaceID, source.machineID, 'local-project/git-state',
      { localProjectId: source.localProjectID, requestedByUserId: userID }, signal, 30000);
  } catch (error) {
    signal.throwIfAborted();
    return { failure: rpcFailure(error) };
  }
  signal.throwIfAborted();
  if (response?.type !== 'local-project/git-state_response' || response.machineId !== source.machineID ||
      response.workspaceId !== workspaceID || response.localProjectId !== source.localProjectID) {
    return { failure: 'unavailable' };
  }
  if (response.success !== true) return { failure: rpcFailure({ code: response.error }) };
  const state = response.state;
  if (state?.git === false) return { state: { git: false } };
  if (state?.git !== true ||
      state.currentBranch !== null && (typeof state.currentBranch !== 'string' || !state.currentBranch.length)) {
    return { failure: 'unavailable' };
  }
  const projected = { git: true, currentBranch: state.currentBranch };
  if (state.defaultBranch === null || typeof state.defaultBranch === 'string' && state.defaultBranch.length) {
    projected.defaultBranch = state.defaultBranch;
  }
  if (state.githubRepoFullName === null || typeof state.githubRepoFullName === 'string' &&
      /^[^/\s]+\/[^/\s]+$/.test(state.githubRepoFullName)) {
    projected.githubRepoFullName = state.githubRepoFullName;
  }
  const tree = state.workingTree;
  const flags = ['clean', 'staged', 'unstaged', 'untracked', 'conflicted'];
  if (tree && flags.every(key => typeof tree[key] === 'boolean') &&
      tree.clean === !(tree.staged || tree.unstaged || tree.untracked || tree.conflicted)) {
    projected.workingTree = Object.fromEntries(flags.map(key => [key, tree[key]]));
  }
  return { state: { ...projected, ...projectGitHints(source, projected) } };
}
