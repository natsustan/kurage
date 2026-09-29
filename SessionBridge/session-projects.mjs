import { control } from './mention-skills.mjs';
import { readLocalProjectState } from './session-archive.mjs';

export async function sessionProjects(repo, workspaceID, templateSessionID, action, path, cursor, access, signal,
  requestControl = control) {
  signal.throwIfAborted();
  const rows = await repo.listDoc();
  const row = rows.find(row => row.docId === `session-${templateSessionID}` &&
    !row.deleted && !row.meta?.isArchived && !row.meta?.parentSessionId);
  const machineID = row?.meta?.machineId;
  if (!machineID) throw new Error('Session machine is unavailable');
  const describe = (id, name, rootPath = '') => ({
    id: `local:${machineID}:${id}`, name, rootPath,
    templateSessionID: rows.filter(row => row.docId.startsWith('session-') && !row.docId.startsWith('session-comment-') &&
      !row.deleted && !row.meta?.isArchived && !row.meta?.parentSessionId &&
      row.meta?.machineId === machineID && row.meta?.project?.kind === 'local' && row.meta.project.localProjectId === id)
      .sort((a, b) => (b.meta.lastMessageAt ?? 0) - (a.meta.lastMessageAt ?? 0))[0]?.docId.slice(8) ?? templateSessionID,
  });
  if (action === 'catalog') {
    const state = await readLocalProjectState(repo, workspaceID, machineID, signal);
    if (!state.known) throw new Error('Project catalog could not be synced');
    return { projects: [...state.projects].filter(id => !state.pending.has(id))
      .map(id => describe(id, state.names.get(id) ?? 'Local Project'))
      .sort((a, b) => a.name.localeCompare(b.name)) };
  }
  const request = action === 'browse'
    ? { type: 'local-project/browse-dir', machineId: machineID, workspaceId: workspaceID,
        ...(path ? { absolutePath: path } : {}), ...(cursor ? { cursor } : {}), limit: 100 }
    : action === 'select' && typeof path === 'string' && path.length
      ? { type: 'local-project/prepare-add', machineId: machineID, workspaceId: workspaceID, rootPath: path }
      : null;
  if (!request) throw new Error('Invalid project request');
  const response = await requestControl(access, workspaceID, machineID, request, signal);
  signal.throwIfAborted();
  if (!response?.ok || response.type !== request.type) throw new Error('Machine project request failed');
  if (action === 'browse') return { directory: response.result };
  const result = response.result;
  if (!result.localProjectId || !result.rootPath || !result.name) {
    throw new Error('Invalid prepared project');
  }
  // Match Lody's prepareAndWriteLocalProject: preserve existing project names
  // and metadata, including when another client registered it during the RPC.
  const flockID = `${workspaceID}:mf:${machineID}`;
  const handle = await repo.openFlockDoc(flockID);
  const report = await repo.sync({ scope: 'doc', flockDocIds: [flockID], requireTransports: ['cloud'], signal });
  signal.throwIfAborted();
  if (!report.ok && report.outcome !== 'synced') throw new Error('Project catalog sync failed');
  const state = await readLocalProjectState(repo, workspaceID, machineID, signal, handle.flock);
  if (state.pending.has(result.localProjectId)) throw new Error('Project is being deleted');
  if (result.alreadyRegistered && state.projects.has(result.localProjectId)) {
    return { project: describe(result.localProjectId, state.names.get(result.localProjectId) ?? result.name, result.rootPath) };
  }
  const key = ['localProject', result.localProjectId];
  const stored = handle.flock.txn(() => {
    const existing = handle.flock.get(key);
    if (existing !== undefined) return existing;
    const now = Date.now();
    const project = { id: result.localProjectId, name: result.name, rootPath: result.rootPath,
      createdAtMs: now, lastOpenedAtMs: now };
    handle.flock.put(key, project);
    return project;
  });
  if (stored?.id !== result.localProjectId || !stored.name || !stored.rootPath) {
    throw new Error('Invalid existing project');
  }
  signal.throwIfAborted();
  const written = await repo.sync({ scope: 'doc', flockDocIds: [flockID], requireTransports: ['cloud'], signal });
  signal.throwIfAborted();
  if (!written.ok && written.outcome !== 'synced') throw new Error('Project registration is unconfirmed');
  return { project: describe(stored.id, stored.name, stored.rootPath) };
}
