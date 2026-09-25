import { projectSessionActivity } from './session-activity.mjs';

function synced(report) {
  return report?.outcome === 'synced' || report?.ok === true;
}

function isSessionRow(row) {
  return typeof row?.docId === 'string' && row.docId.startsWith('session-') &&
    !row.docId.startsWith('session-comment-') && !row.deleted;
}

function text(value) {
  return typeof value === 'string' ? value : '';
}

function describe(row) {
  const docSessionID = row.docId.slice('session-'.length);
  return {
    id: text(row.meta?.id) || docSessionID,
    docSessionID,
    docId: row.docId,
    parentSessionId: text(row.meta?.parentSessionId),
    openedBySessionId: text(row.meta?.openedBySessionId),
    openedByRootSessionId: text(row.meta?.openedByRootSessionId),
  };
}

// Archiving includes child tabs and sessions opened by their owner or root.
export function collectLifecycle(sessionID, rows) {
  const sessions = rows.filter(isSessionRow).map(describe);
  const root = sessions.find(session => session.docSessionID === sessionID || session.id === sessionID);
  if (!root) return [];
  const childrenByOwner = new Map();
  for (const session of sessions) {
    for (const owner of [session.parentSessionId, session.openedBySessionId, session.openedByRootSessionId]) {
      if (!owner) continue;
      const children = childrenByOwner.get(owner) ?? [];
      children.push(session);
      childrenByOwner.set(owner, children);
    }
  }
  const result = [];
  const included = new Set();
  const pending = [root];
  for (let index = 0; index < pending.length; index += 1) {
    const current = pending[index];
    if (included.has(current.docId)) continue;
    included.add(current.docId);
    result.push(current);
    for (const owner of [current.id, current.docSessionID]) {
      pending.push(...(childrenByOwner.get(owner) ?? []));
    }
  }
  return result;
}

// The owning machine observes isArchived and releases the session runtime.
// No machine command or legacy queue is needed to accept the archive request.
export async function archiveSession(repo, sessionID) {
  const lifecycle = collectLifecycle(sessionID, await repo.listDoc());
  if (lifecycle.length === 0) return 'missing';

  for (const session of lifecycle) {
    await repo.upsertDocMeta(session.docId, { isArchived: true, status: { type: 'idle' } });
  }
  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) return 'unconfirmed';
  for (const session of lifecycle) {
    const confirmed = await repo.getDocMeta(session.docId);
    if (!confirmed || confirmed.deleted || confirmed.meta?.isArchived !== true) return 'unconfirmed';
  }
  return 'archived';
}

function isDeleted(row) {
  if (!row) return true;
  if (row.deleted === true || row.exists === false || row.e === false) return true;
  return false;
}

function isSessionDocument(row) {
  return typeof row?.docId === 'string' && row.docId.startsWith('session-') &&
    !row.docId.startsWith('session-comment-') && !isDeleted(row);
}

function sessionIDs(row) {
  const docID = row.docId.slice('session-'.length);
  const metaID = typeof row.meta?.id === 'string' && row.meta.id ? row.meta.id : docID;
  return { docID, metaID };
}

function parentID(row) {
  return typeof row.meta?.parentSessionId === 'string' ? row.meta.parentSessionId : '';
}

// Direct child tabs follow the root. Sessions opened by an agent stay independent.
function operationTargets(rows, sessionID) {
  const sessions = rows.filter(isSessionDocument);
  const root = sessions.find(row => {
    const ids = sessionIDs(row);
    return ids.docID === sessionID || ids.metaID === sessionID;
  });
  if (!root) return null;
  const rootIDs = sessionIDs(root);
  const children = sessions.filter(row => {
    if (row.docId === root.docId) return false;
    const parent = parentID(row);
    return parent === rootIDs.docID || parent === rootIDs.metaID || parent === sessionID;
  });
  return [root, ...children];
}

export function activityTime(meta) {
  if (Number.isFinite(meta?.lastMessageAt)) return meta.lastMessageAt;
  const created = Date.parse(meta?.createdAt ?? '');
  return Number.isFinite(created) ? created : 0;
}

function rethrowAbort(error) {
  if (error?.name === 'AbortError') throw error;
}

export async function readLocalProjectState(repo, workspaceID, machineID, signal) {
  const projects = new Set();
  const pending = new Set();
  const names = new Map();
  if (typeof machineID !== 'string' || !machineID) {
    return { known: false, projects, pending, names };
  }
  const flockID = `${workspaceID}:mf:${machineID}`;
  let known = false;
  try {
    const document = await repo.openFlockDoc(flockID);
    const sync = await repo.sync({
      scope: 'doc', flockDocIds: [flockID], requireTransports: ['cloud'], signal,
    });
    if (sync?.ok || sync?.outcome === 'synced') {
      known = true;
      for (const row of document.flock.scan({ prefix: ['localProject'] })) {
        if (typeof row.key?.[1] !== 'string' || !row.key[1]) continue;
        projects.add(row.key[1]);
        if (typeof row.value?.name === 'string') names.set(row.key[1], row.value.name);
      }
      for (const row of document.flock.scan({ prefix: ['cmd', 'deleteLocalProject'] })) {
        if (typeof row.key?.[2] === 'string' && row.key[2]) pending.add(row.key[2]);
      }
    }
  } catch (error) {
    rethrowAbort(error);
  }
  if (!known) return { known, projects, pending, names };
  try {
    const machine = await repo.getDocMeta(`machine-${machineID}`);
    const legacy = machine && machine.deleted !== true ? machine.meta?.localProjects : undefined;
    if (legacy && typeof legacy === 'object') {
      for (const [id, project] of Object.entries(legacy)) {
        if (!id) continue;
        projects.add(id);
        if (typeof project?.name === 'string' && !names.has(id)) names.set(id, project.name);
      }
    }
  } catch (error) {
    rethrowAbort(error);
  }
  return { known, projects, pending, names };
}

export function canRestoreArchivedSession(meta, state) {
  const project = meta?.project;
  if (project?.kind !== 'local') return true;
  if (typeof project.localProjectId !== 'string' || !project.localProjectId) return false;
  if (!state?.known) return true;
  return state.projects.has(project.localProjectId) && !state.pending.has(project.localProjectId);
}

function projectFields(meta, state, rows) {
  const project = meta.project;
  const repoName = project?.kind === 'github' ? project.repoFullName
    : project?.githubRepoFullName ?? meta.repoFullName;
  const localID = project?.kind === 'local' ? project.localProjectId : null;
  const machineID = typeof meta.machineId === 'string' ? meta.machineId : '';
  const projectID = typeof localID === 'string'
    ? `local:${machineID}:${localID}`
    : typeof repoName === 'string' && repoName.length > 0 ? `github:${repoName}` : null;
  const fallbackName = typeof repoName === 'string' ? repoName.split('/').at(-1) : null;
  if (typeof localID !== 'string') return { projectID, projectName: fallbackName };
  const named = state?.names?.get(localID);
  const legacy = rows.find(row => row.docId === `machine-${machineID}`)?.meta?.localProjects;
  const legacyName = legacy?.[localID]?.name;
  const projectName = named
    ?? (typeof legacyName === 'string' ? legacyName : null)
    ?? fallbackName
    ?? 'Local Project';
  return { projectID, projectName };
}

export function selectArchivedSessions(rows, availabilityByMachine = new Map()) {
  return rows.filter(row => isSessionDocument(row) && row.meta?.isArchived === true && !parentID(row))
    .map(row => {
      const meta = row.meta ?? {};
      const machineID = typeof meta.machineId === 'string' ? meta.machineId : '';
      const state = availabilityByMachine.get(machineID);
      const projected = projectFields(meta, state, rows);
      return {
        id: row.docId.slice('session-'.length),
        title: typeof meta.title === 'string' && meta.title.length > 0 ? meta.title : 'Untitled session',
        agentName: meta.agentType ?? meta.cliType ?? 'Agent',
        activity: projectSessionActivity(meta.status),
        preview: typeof meta.repoFullName === 'string' ? meta.repoFullName : '',
        projectID: projected.projectID,
        projectName: projected.projectName,
        lastMessageAt: activityTime(meta),
        canRestore: canRestoreArchivedSession(meta, state),
      };
    })
    .sort((a, b) => b.lastMessageAt - a.lastMessageAt || a.id.localeCompare(b.id));
}

// Clearing isArchived is the restore. Only the requested session reopens its tab.
export async function restoreArchivedSession(repo, workspaceID, sessionID) {
  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) return 'unconfirmed';
  let targets = operationTargets(await repo.listDoc(), sessionID);
  if (!targets) return 'missing';
  const project = targets[0].meta?.project;
  if (project?.kind === 'local') {
    const state = await readLocalProjectState(repo, workspaceID, targets[0].meta?.machineId);
    if (!state.known) return 'unconfirmed';
    if (!canRestoreArchivedSession(targets[0].meta, state)) return 'project-missing';
    if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) return 'unconfirmed';
    targets = operationTargets(await repo.listDoc(), sessionID);
    if (!targets) return 'missing';
  }
  if (targets.every(row => row.meta?.isArchived !== true)) return 'restored';
  for (const row of targets) {
    const ids = sessionIDs(row);
    const patch = { isArchived: false };
    if (ids.docID === sessionID || ids.metaID === sessionID) patch.isTabClosed = false;
    await repo.upsertDocMeta(row.docId, patch);
  }
  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) return 'unconfirmed';
  const confirmed = operationTargets(await repo.listDoc(), sessionID);
  if (!confirmed) return 'unconfirmed';
  return confirmed.every(row => row.meta?.isArchived !== true) ? 'restored' : 'unconfirmed';
}

// Deleting the document is the signal the owning machine observes.
export async function deleteArchivedSession(repo, sessionID) {
  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) return 'unconfirmed';
  const targets = operationTargets(await repo.listDoc(), sessionID);
  if (!targets) return 'missing';
  if (targets[0].meta?.isArchived !== true) return 'not-archived';
  for (const row of [...targets].reverse()) await repo.deleteDoc(row.docId);
  if (!synced(await repo.sync({ scope: 'meta', requireTransports: ['cloud'] }))) return 'unconfirmed';
  const remaining = await repo.listDoc();
  const stillThere = targets.some(target => remaining.some(row =>
    row.docId === target.docId && !isDeleted(row)));
  return stillThere ? 'unconfirmed' : 'deleted';
}
