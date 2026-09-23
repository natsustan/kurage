import { LoroRepo } from 'loro-repo';
import { StreamsTransportAdapter } from 'loro-repo/transport/streams';
import { decompress as decompressZstd } from '@loro-dev/streams-crdt/zstd';
import { projectConversation } from './conversation-projection.mjs';

const originalFetch = globalThis.fetch.bind(globalThis);

function toBase64(bytes) {
  let value = '';
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    value += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(value);
}

function fromBase64(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

globalThis.fetch = async (input, init) => {
  const request = new Request(input, init);
  if (!request.url.startsWith('https://')) return originalFetch(input, init);

  const body = request.method === 'GET' || request.method === 'HEAD'
    ? null : toBase64(new Uint8Array(await request.arrayBuffer()));
  const result = await window.webkit.messageHandlers.streamFetch.postMessage({
    url: request.url,
    method: request.method,
    headers: Object.fromEntries(request.headers.entries()),
    body,
  });
  if (result.error) throw new Error(result.error);
  const response = new Response([204, 205, 304].includes(result.status) ? null : fromBase64(result.body), {
    status: result.status,
    headers: result.headers,
  });
  return response;
};

const snapshotCodec = {
  compress: async (bytes) => bytes,
  decompress: async (bytes) =>
    bytes.length >= 4 && bytes[0] === 0x28 && bytes[1] === 0xb5 &&
      bytes[2] === 0x2f && bytes[3] === 0xfd
      ? await decompressZstd(bytes) : bytes,
};

let cachedWorkspace;
let workspaceOperation = Promise.resolve();

function withWorkspaceRepo(workspaceID, accessToken, gatewayBaseURL, work, refreshMeta = true) {
  // The session list has already synced metadata. Keep its in-memory repo so
  // opening a conversation needs only the session document sync.
  const operation = workspaceOperation.then(async () => {
    let state = cachedWorkspace;
    if (state && (state.workspaceID !== workspaceID || state.gatewayBaseURL !== gatewayBaseURL)) {
      cachedWorkspace = undefined;
      await state.repo.destroy();
      state = undefined;
    }
    if (!state) {
      const repo = await LoroRepo.create({ metaDebounceCommitMs: 0 });
      state = { repo, workspaceID, gatewayBaseURL, accessToken, metaReady: false };
      try {
        const transport = new StreamsTransportAdapter({
          bucketId: 'lody',
          metaStreamId: `${workspaceID}:meta`,
          docStreamId: (docID) => docID.startsWith('session-')
            ? `${workspaceID}:s:${docID.slice('session-'.length)}` : docID,
          flockDocStreamId: (flockDocID) => flockDocID,
          auth: async () => state.accessToken,
          baseUrl: gatewayBaseURL,
          createStreamIfMissing: false,
          persistence: { mode: 'ephemeral' },
          snapshotCodec,
        });
        await repo.addTransport('cloud', transport);
        cachedWorkspace = state;
      } catch (error) {
        await repo.destroy();
        throw error;
      }
    }
    state.accessToken = accessToken;
    if (refreshMeta || !state.metaReady) {
      const report = await state.repo.sync({ scope: 'meta', requireTransports: ['cloud'] });
      if (!report.ok) throw new Error('Workspace metadata sync failed');
      state.metaReady = true;
    }
    return work(state.repo);
  });
  workspaceOperation = operation.catch(() => {});
  return operation;
}

window.kurageSessions = async (workspaceID, accessToken, gatewayBaseURL) =>
  withWorkspaceRepo(workspaceID, accessToken, gatewayBaseURL, async (repo) => {
    const rows = await repo.listDoc();
    const visibleSessions = rows.filter((row) => row.docId.startsWith('session-') &&
      !row.docId.startsWith('session-comment-') && !row.deleted && !row.meta.isArchived &&
      !row.meta.parentSessionId);
    const localProjectNames = new Map();
    const machineIDs = new Set(visibleSessions
      .filter((row) => row.meta.project?.kind === 'local')
      .map((row) => row.meta.machineId)
      .filter((id) => typeof id === 'string' && id.length > 0));
    await Promise.all([...machineIDs].map(async (machineID) => {
      try {
        const document = await repo.openFlockDoc(`${workspaceID}:mf:${machineID}`);
        const sync = await document.syncOnce();
        if (!sync.ok) return;
        for (const row of document.flock.scan({ prefix: ['localProject'] })) {
          if (typeof row.key?.[1] === 'string' && typeof row.value?.name === 'string') {
            localProjectNames.set(`${machineID}:${row.key[1]}`, row.value.name);
          }
        }
      } catch {
        // Project names are optional; session metadata still gives stable group IDs.
      }
    }));
    for (const machineID of machineIDs) {
      const legacy = rows.find((row) => row.docId === `machine-${machineID}`)?.meta?.localProjects;
      if (legacy && typeof legacy === 'object') {
        for (const [localID, project] of Object.entries(legacy)) {
          if (typeof project?.name === 'string') {
            const key = `${machineID}:${localID}`;
            if (!localProjectNames.has(key)) localProjectNames.set(key, project.name);
          }
        }
      }
    }
    const projected = visibleSessions.map((row) => {
      const project = row.meta.project;
      const repoName = project?.kind === 'github' ? project.repoFullName
        : project?.githubRepoFullName ?? row.meta.repoFullName;
      const localID = project?.kind === 'local' ? project.localProjectId : null;
      const projectID = typeof localID === 'string'
        ? `local:${row.meta.machineId}:${localID}`
        : typeof repoName === 'string' && repoName.length > 0 ? `github:${repoName}` : null;
      const fallbackName = typeof repoName === 'string' ? repoName.split('/').at(-1) : null;
      const projectName = typeof localID === 'string'
        ? localProjectNames.get(`${row.meta.machineId}:${localID}`) ?? fallbackName ?? 'Local Project'
        : fallbackName;
      return {
        id: row.docId.slice('session-'.length),
        title: typeof row.meta.title === 'string' && row.meta.title.length > 0
          ? row.meta.title : 'Untitled session',
        agentName: row.meta.agentType ?? row.meta.cliType ?? 'Agent',
        activity: ['running', 'initializing', 'requestPermission'].includes(row.meta.status?.type)
          ? 'running' : 'idle',
        preview: row.meta.repoFullName ?? '',
        projectID,
        projectName,
        lastMessageAt: Number.isFinite(row.meta.lastMessageAt)
          ? row.meta.lastMessageAt : (Date.parse(row.meta.createdAt ?? '') || 0),
      };
    })
      .sort((a, b) => b.lastMessageAt - a.lastMessageAt);
    return JSON.stringify({ sessions: projected });
  });

window.kurageConversation = async (workspaceID, sessionID, accessToken, gatewayBaseURL) =>
  withWorkspaceRepo(workspaceID, accessToken, gatewayBaseURL, async (repo) => {
    const docID = `session-${sessionID}`;
    const rows = await repo.listDoc();
    if (!rows.some((row) => row.docId === docID && !row.deleted)) {
      throw new Error('Session is missing from this workspace');
    }
    const handle = await repo.openPersistedDoc(docID);
    const report = await handle.syncOnce();
    if (!report.ok) throw new Error('Session history sync failed');
    return JSON.stringify(projectConversation(sessionID, handle.doc.getList('history').toJSON()));
  }, false);
