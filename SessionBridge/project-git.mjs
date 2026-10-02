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
  return { machineID, localProjectID };
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
  return { state: { git: true, currentBranch: state.currentBranch } };
}
