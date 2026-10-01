import { requestMachine } from './machine-rpc.mjs';
import { readLocalProjectState } from './session-archive.mjs';
import { projectSessionActivity } from './session-activity.mjs';

function hasPendingInput(meta) {
  const pending = id => typeof id === 'string' && id.length > 0 &&
    id !== meta.lastMissingHistoryUserMsgId && id !== meta.settledActivationUserMsgId;
  return pending(meta.processingUserMsgId) ||
    pending(meta.latestUserMsgId) && meta.latestUserMsgId !== meta.lastHandledUserMsgId ||
    Object.entries(meta.steerTurnStatuses ?? {}).some(([id, status]) => status === 'pending' && pending(id));
}

// Resolve the registered project, never accept a client-supplied filesystem path.
export async function projectGitSource(repo, workspaceID, templateSessionID, projectID, signal) {
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
  const catalog = await readLocalProjectState(repo, workspaceID, machineID, signal);
  signal.throwIfAborted();
  if (!catalog.known || !catalog.projects.has(localProjectID) || catalog.pending.has(localProjectID)) {
    throw new Error('Project is unavailable');
  }
  const busy = rows.some(row => row.docId.startsWith('session-') &&
    !row.docId.startsWith('session-comment-') && !row.deleted && !row.meta?.isArchived &&
    row.meta?.machineId === machineID && row.meta.project?.kind === 'local' &&
    row.meta.project.localProjectId === localProjectID &&
    (projectSessionActivity(row.meta.status) === 'running' || hasPendingInput(row.meta)));
  return { machineID, localProjectID, busy };
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
  if (!response.success) return { failure: rpcFailure({ code: response.error }) };
  const state = response.state;
  if (state?.git === false) return { state: { git: false, branches: [], busy: source.busy } };
  if (state?.git !== true || !Array.isArray(state.branches) ||
      !state.branches.every(branch => typeof branch === 'string' && branch.length > 0) ||
      state.currentBranch !== null && typeof state.currentBranch !== 'string' ||
      !['clean', 'staged', 'unstaged', 'untracked', 'conflicted'].every(key => typeof state.workingTree?.[key] === 'boolean') ||
      !Number.isFinite(response.observedAtMs)) return { failure: 'unavailable' };
  return { state: { git: true, currentBranch: state.currentBranch,
    branches: [...new Set(state.branches)], workingTree: state.workingTree,
    observedAtMs: response.observedAtMs, busy: source.busy } };
}

export async function switchProjectBranch(source, access, workspaceID, userID, branch, signal,
  request = requestMachine, recheckSource = async () => source) {
  const before = await readProjectGit(source, access, workspaceID, userID, signal, request);
  if (!before.state) return before;
  const state = before.state;
  if (!state.git) return { ...before, failure: 'not_git' };
  if (state.busy) return { ...before, failure: 'busy' };
  if (!state.branches.includes(branch)) return { ...before, failure: 'branch_missing' };
  if (state.currentBranch === branch) return before;
  if (!state.workingTree.clean) return { ...before, failure: 'local_changes' };
  const latest = await recheckSource();
  signal.throwIfAborted();
  if (latest.machineID !== source.machineID || latest.localProjectID !== source.localProjectID) {
    return { failure: 'unavailable' };
  }
  if (latest.busy) return { state: { ...state, busy: true }, failure: 'busy' };
  signal.throwIfAborted();
  let failure;
  try {
    // Keep Lody's exact selector (including local/remote qualification). The
    // control schema does not accept requestedByUserId for checkout-branch.
    const response = await request(access, workspaceID, source.machineID, 'local-project/control',
      { request: { type: 'local-project/checkout-branch', workspaceId: workspaceID,
        machineId: source.machineID, localProjectId: source.localProjectID, branchName: branch } }, signal, 30000);
    signal.throwIfAborted();
    if (response?.ok !== true || response.type !== 'local-project/checkout-branch' ||
        response.result?.success !== true || typeof response.result.currentBranch !== 'string') {
      failure = 'switch_failed';
    }
  } catch (error) {
    signal.throwIfAborted();
    failure = rpcFailure(error) === 'unsupported' ? 'unsupported' : 'switch_unconfirmed';
  }
  // A lost reply can follow a successful checkout. Never automatically repeat
  // the mutation; publish a fresh read, including after a machine rejection.
  const after = await readProjectGit(source, access, workspaceID, userID, signal, request);
  return { ...after, ...(failure ? { failure } : !after.state ? { failure: 'switch_unconfirmed' } : {}) };
}
