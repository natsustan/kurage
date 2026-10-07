import { requestMachine } from './machine-rpc.mjs';

// Lody Code Collab v2: shared/code-collab.ts and loro-streams-rpc/rpc.ts.
// Both the request and response use the owning (parent for a tab) session envelope.
const encoder = new TextEncoder();
// Match Lody's per-snapshot text limits; display/comparison budgets belong in Swift.
const maxTextBytes = 10 * 1024 * 1024;
const maxCompressedBytes = 1024 * 1024;
const maxEnvelopeBytes = 3 * 1024 * 1024;
const salt = 'lody-code-collab-v2-bootstrap-salt-v1';
const aadLabel = 'lody-code-collab-v2-machine-rpc-payload-v1';
const unavailable = reason => ({ status: 'unavailable', reason });
const errorReasons = { unsupported_binary: 'binary', unsupported_skipped: 'unsupported',
  too_large: 'too_large', machine_offline: 'machine_offline', permission_denied: 'permission_denied',
  session_not_found: 'turn_unavailable', file_not_found: 'turn_unavailable' };

function base64(bytes) {
  let binary = '';
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function decodeBase64(value) {
  if (typeof value !== 'string' || value.length > maxEnvelopeBytes * 2) throw new Error('Invalid diff encoding');
  const text = value.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(text.padEnd(text.length + (4 - text.length % 4) % 4, '='));
  return Uint8Array.from(binary, character => character.charCodeAt(0));
}

async function contentKey(ownerSessionID) {
  const hash = async label => new Uint8Array(await crypto.subtle.digest('SHA-256',
    encoder.encode(`${label}\0${salt}\0${ownerSessionID}`)));
  const bytes = await hash('lody-code-collab-v2-bootstrap-content-key-v1');
  const digest = await hash('lody-code-collab-v2-bootstrap-content-key-id-v1');
  const keyId = `ccv2:${Array.from(digest, byte => byte.toString(16).padStart(2, '0')).join('').slice(0, 24)}`;
  const key = await crypto.subtle.importKey('raw', bytes, 'AES-GCM', false, ['encrypt', 'decrypt']);
  return { key, keyId, additionalData: encoder.encode(`${aadLabel}\0${ownerSessionID}\0${keyId}\0${1}`) };
}

export async function encryptDiffPayload(ownerSessionID, payload) {
  const { key, keyId, additionalData } = await contentKey(ownerSessionID);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData }, key,
    encoder.encode(JSON.stringify(payload)));
  const urlBase64 = bytes => base64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  return { type: 'code-collab-v2-content-envelope', keyVersion: 1, algorithm: 'AES-256-GCM',
    ownerSessionId: ownerSessionID, keyId, iv: urlBase64(iv), ciphertext: urlBase64(new Uint8Array(ciphertext)) };
}

export async function decryptDiffPayload(ownerSessionID, envelope) {
  const { key, keyId, additionalData } = await contentKey(ownerSessionID);
  if (envelope?.type !== 'code-collab-v2-content-envelope' || envelope.keyVersion !== 1 ||
      envelope.algorithm !== 'AES-256-GCM' || envelope.ownerSessionId !== ownerSessionID || envelope.keyId !== keyId) {
    throw new Error('Diff response owner or protocol mismatch');
  }
  const iv = decodeBase64(envelope.iv);
  const ciphertext = decodeBase64(envelope.ciphertext);
  if (iv.length !== 12 || ciphertext.length > maxEnvelopeBytes) throw new Error('Invalid diff envelope size');
  const plaintext = await crypto.subtle.decrypt({ name: 'AES-GCM', iv, additionalData }, key, ciphertext);
  return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(plaintext));
}

async function snapshotText(snapshot, signal) {
  signal.throwIfAborted();
  if (snapshot?.kind === 'missing') return '';
  if (snapshot?.kind === 'binary') return unavailable('binary');
  if (snapshot?.kind === 'too_large') return unavailable('too_large');
  if (snapshot?.kind !== 'text') throw new Error('Invalid diff snapshot');
  const payload = snapshot.text;
  if (!Number.isSafeInteger(payload?.rawBytes) || payload.rawBytes < 0) throw new Error('Invalid diff text size');
  if (payload.rawBytes > maxTextBytes) return unavailable('snapshot_limit');
  let bytes;
  if (payload.encoding === 'plain' && typeof payload.text === 'string') {
    bytes = encoder.encode(payload.text);
  } else if (payload.encoding === 'gzip-base64') {
    const compressed = decodeBase64(payload.data);
    if (compressed.length !== payload.compressedBytes || compressed.length > maxCompressedBytes) {
      throw new Error('Invalid compressed diff size');
    }
    // Bound decompressed growth, not just the declared size in the response.
    const reader = new Blob([compressed]).stream().pipeThrough(new DecompressionStream('gzip')).getReader();
    const cancel = () => { void reader.cancel().catch(() => {}); };
    signal.addEventListener('abort', cancel, { once: true });
    try {
      const chunks = [];
      let size = 0;
      while (true) {
        signal.throwIfAborted();
        const { value, done } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > maxTextBytes || size > payload.rawBytes) throw new Error('Diff text exceeds declared size');
        chunks.push(value);
      }
      bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    } finally {
      signal.removeEventListener('abort', cancel);
      await reader.cancel().catch(() => {});
      reader.releaseLock();
    }
  } else throw new Error('Unsupported diff text encoding');
  signal.throwIfAborted();
  if (bytes.length !== payload.rawBytes) throw new Error('Diff text size mismatch');
  return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
}

export async function loadTurnDiff(source, access, workspaceID, sessionID, turnID, path, signal,
  request = requestMachine) {
  signal.throwIfAborted();
  const params = await encryptDiffPayload(source.ownerSessionID, { sessionId: sessionID, turnId: turnID, path });
  signal.throwIfAborted();
  let envelope;
  try {
    envelope = await request(access, workspaceID, source.machineID, 'code-collab/open-turn-diff', params, signal, 30000);
  } catch (error) {
    signal.throwIfAborted();
    if (error.code === 'method_unavailable' || error.code === -32601) return unavailable('unsupported');
    if (Object.hasOwn(errorReasons, error.code)) return unavailable(errorReasons[error.code]);
    throw error;
  }
  signal.throwIfAborted();
  const response = await decryptDiffPayload(source.ownerSessionID, envelope);
  signal.throwIfAborted();
  if (response.status === 'error') {
    if (Object.hasOwn(errorReasons, response.code)) return unavailable(errorReasons[response.code]);
    throw new Error('Machine could not load this code difference');
  }
  if (response.turnId !== turnID || typeof response.path !== 'string' || !response.path) {
    throw new Error('Diff response does not match the requested turn');
  }
  // Lody returns a workspace-relative canonical path, including for absolute
  // requests. Compare relative requests directly; never guess a root by suffix.
  const relativePath = path.replace(/\\/g, '/');
  if (!/^(\/|[A-Za-z]:\/)/.test(relativePath)) {
    const parts = [];
    for (const part of relativePath.split('/')) {
      if (part === '..') parts.pop();
      else if (part && part !== '.') parts.push(part);
    }
    if (response.path !== parts.join('/')) throw new Error('Diff response does not match the requested file');
  }
  if (response.status === 'unavailable') {
    if (response.reason === 'transient_io') throw new Error('Could not read the historical snapshots');
    if (!['turn_unavailable', 'not_changed'].includes(response.reason)) throw new Error('Invalid diff availability');
    return unavailable(response.reason);
  }
  if (response.status !== 'ok') throw new Error('Invalid diff response');
  const oldText = await snapshotText(response.oldSnapshot, signal);
  const newText = await snapshotText(response.newSnapshot, signal);
  if (typeof oldText !== 'string') return oldText;
  if (typeof newText !== 'string') return newText;
  return { status: 'ready', edit: { id: `${turnID}:${path}`, oldText, newText } };
}

export async function turnDiffSource(repo, sessionID, signal) {
  signal.throwIfAborted();
  const rows = await repo.listDoc();
  signal.throwIfAborted();
  const row = rows.find(row => row.docId === `session-${sessionID}` && !row.deleted);
  const machineID = row?.meta?.machineId;
  if (typeof machineID !== 'string' || !machineID) throw new Error('Session machine is unavailable');
  const ownerSessionID = row.meta.parentSessionId ?? sessionID;
  if (typeof ownerSessionID !== 'string' || !ownerSessionID) throw new Error('Session owner is unavailable');
  if (ownerSessionID !== sessionID && !rows.some(row => row.docId === `session-${ownerSessionID}` &&
      !row.deleted && row.meta?.machineId === machineID)) throw new Error('Session owner is unavailable');
  return { machineID, ownerSessionID };
}

async function currentDiffRequest(source, access, workspaceID, method, payload, signal, request) {
  signal.throwIfAborted();
  const params = await encryptDiffPayload(source.ownerSessionID, payload);
  signal.throwIfAborted();
  try {
    const envelope = await request(access, workspaceID, source.machineID, method, params, signal, 30000);
    signal.throwIfAborted();
    const response = await decryptDiffPayload(source.ownerSessionID, envelope);
    signal.throwIfAborted();
    if (response.status === 'error') {
      if (Object.hasOwn(errorReasons, response.code)) return unavailable(errorReasons[response.code]);
      throw new Error('Machine could not load branch changes');
    }
    if (response.status === 'unavailable' && response.reason === 'transient_io') {
      throw new Error('Could not read branch changes');
    }
    return response;
  } catch (error) {
    signal.throwIfAborted();
    if (error.code === 'method_unavailable' || error.code === -32601) return unavailable('unsupported');
    if (Object.hasOwn(errorReasons, error.code)) return unavailable(errorReasons[error.code]);
    throw error;
  }
}

export async function loadBranchChanges(source, access, workspaceID, sessionID, signal, request = requestMachine) {
  const response = await currentDiffRequest(source, access, workspaceID, 'code-collab/open-all-changes-diff',
    { sessionId: sessionID }, signal, request);
  if (response.status === 'unavailable') {
    if (!['base_unavailable', 'unsupported', ...Object.values(errorReasons)].includes(response.reason)) {
      throw new Error('Invalid branch availability');
    }
    return { status: 'unavailable', files: [], reason: response.reason };
  }
  if (response.status !== 'ok' || typeof response.base !== 'string' || !response.base ||
      !Array.isArray(response.entries) || response.entries.length > 10000) throw new Error('Invalid branch changes');
  const paths = new Set();
  const files = response.entries.map(entry => {
    signal.throwIfAborted();
    if (typeof entry.path !== 'string' || !entry.path || paths.has(entry.path) ||
        !['ok', 'deferred', 'unavailable'].includes(entry.status) ||
        (entry.status === 'unavailable' && entry.reason !== 'not_changed')) throw new Error('Invalid branch file');
    paths.add(entry.path);
    for (const value of [entry.add, entry.del]) {
      if (value !== undefined && (!Number.isSafeInteger(value) || value < 0)) throw new Error('Invalid branch counts');
    }
    // Keep native state bounded: current text is read on expansion, rather than
    // retaining all inline snapshots (which can expand substantially after gzip).
    return { path: entry.path, additions: entry.add ?? null, deletions: entry.del ?? null, edits: [] };
  });
  files.sort((a, b) => a.path.localeCompare(b.path));
  return { status: 'ready', files };
}

export async function loadCurrentDiff(source, access, workspaceID, sessionID, path, signal, request = requestMachine) {
  const response = await currentDiffRequest(source, access, workspaceID, 'code-collab/open-current-diff',
    { sessionId: sessionID, path }, signal, request);
  if (response.status === 'unavailable' && response.path === undefined) {
    return unavailable(response.reason === 'unsupported' ? 'branch_unsupported' : response.reason);
  }
  // Branch paths come from the machine's canonical file list, never history paths.
  if (response.path !== path) throw new Error('Diff response does not match the requested file');
  if (response.status === 'unavailable') {
    if (!['base_unavailable', 'not_changed', 'unsupported_binary'].includes(response.reason)) {
      throw new Error('Invalid branch diff availability');
    }
    return unavailable(response.reason === 'unsupported_binary' ? 'binary' : response.reason);
  }
  if (response.status !== 'ok') throw new Error('Invalid branch diff');
  const oldText = await snapshotText(response.oldSnapshot, signal);
  const newText = await snapshotText(response.newSnapshot, signal);
  if (typeof oldText !== 'string') return oldText;
  if (typeof newText !== 'string') return newText;
  return { status: 'ready', edit: { id: `branch:${path}`, oldText, newText } };
}
