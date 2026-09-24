import { LoroRepo } from 'loro-repo';
import { StreamsTransportAdapter } from 'loro-repo/transport/streams';
import { decompress as decompressZstd } from '@loro-dev/streams-crdt/zstd';

const originalFetch = globalThis.fetch.bind(globalThis);

function fromBase64(value) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

globalThis.fetch = async (input, init) => {
  const request = new Request(input, init);
  if (!request.url.startsWith('https://')) return originalFetch(input, init);
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    throw new Error('Session bridge only permits read requests');
  }

  const result = await window.webkit.messageHandlers.streamFetch.postMessage({
    url: request.url,
    method: request.method,
    headers: Object.fromEntries(request.headers.entries()),
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

let currentWorkspace;
// The repo and its mutable proxy credential are shared by one sync at a time.
let syncQueue = Promise.resolve();
const operations = new Map();

window.kurageCancel = (operationID) => {
  operations.get(operationID)?.abort();
};

async function openWorkspace(workspaceID, gatewayBaseURL, proxyCredential) {
  const repo = await LoroRepo.create({ metaDebounceCommitMs: 0 });
  try {
    const workspace = { repo, workspaceID, gatewayBaseURL, proxyCredential };
    const transport = new StreamsTransportAdapter({
      bucketId: 'lody',
      metaStreamId: `${workspaceID}:meta`,
      docStreamId: (docID) => docID.startsWith('session-')
        ? `${workspaceID}:s:${docID.slice('session-'.length)}` : docID,
      flockDocStreamId: (flockDocID) => flockDocID,
      auth: async () => workspace.proxyCredential,
      baseUrl: gatewayBaseURL,
      createStreamIfMissing: false,
      persistence: { mode: 'ephemeral' },
      snapshotCodec,
    });
    await repo.addTransport('cloud', transport);
    return workspace;
  } catch (error) {
    await repo.destroy();
    throw error;
  }
}

async function readSessions(workspaceID, proxyCredential, gatewayBaseURL, signal) {
  signal.throwIfAborted();
  if (currentWorkspace?.workspaceID !== workspaceID ||
      currentWorkspace?.gatewayBaseURL !== gatewayBaseURL) {
    await currentWorkspace?.repo.destroy();
    currentWorkspace = undefined;
    signal.throwIfAborted();
    currentWorkspace = await openWorkspace(workspaceID, gatewayBaseURL, proxyCredential);
  }
  const workspace = currentWorkspace;
  workspace.proxyCredential = proxyCredential;
  signal.throwIfAborted();
  const repo = workspace.repo;
  const report = await repo.sync({ scope: 'meta', requireTransports: ['cloud'], signal });
  if (!report.ok) throw new Error('Workspace metadata sync failed');
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
      const sync = await repo.sync({
        scope: 'doc',
        flockDocIds: [`${workspaceID}:mf:${machineID}`],
        requireTransports: ['cloud'],
        signal,
      });
      if (!sync.ok) return;
      for (const row of document.flock.scan({ prefix: ['localProject'] })) {
        if (typeof row.key?.[1] === 'string' && typeof row.value?.name === 'string') {
          localProjectNames.set(`${machineID}:${row.key[1]}`, row.value.name);
        }
      }
    } catch (error) {
      if (signal.aborted) throw error;
      // Project names are optional; session metadata still gives stable group IDs.
    }
  }));
  signal.throwIfAborted();
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
}

window.kurageSessions = (operationID, workspaceID, gatewayBaseURL) => {
  const controller = new AbortController();
  operations.set(operationID, controller);
  const result = syncQueue.then(() =>
    readSessions(workspaceID, operationID, gatewayBaseURL, controller.signal));
  syncQueue = result.then(() => {}, () => {});
  return result.finally(() => operations.delete(operationID));
};
