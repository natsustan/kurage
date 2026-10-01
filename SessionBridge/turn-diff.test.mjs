import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, createCipheriv, createDecipheriv } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { encryptDiffPayload, decryptDiffPayload, loadTurnDiff, turnDiffSource } from './turn-diff.mjs';

// Independent Node implementation of the envelope specified by Lody. Do not
// use the implementation under test to generate interoperability expectations.
function reference(owner, payload) {
  const salt = 'lody-code-collab-v2-bootstrap-salt-v1';
  const hash = label => createHash('sha256').update(`${label}\0${salt}\0${owner}`).digest();
  const key = hash('lody-code-collab-v2-bootstrap-content-key-v1');
  const keyId = `ccv2:${hash('lody-code-collab-v2-bootstrap-content-key-id-v1').toString('hex').slice(0, 24)}`;
  const aad = Buffer.from(`lody-code-collab-v2-machine-rpc-payload-v1\0${owner}\0${keyId}\0${1}`);
  const iv = Buffer.alloc(12, 7);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  cipher.setAAD(aad);
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(payload)), cipher.final(), cipher.getAuthTag()]);
  return { envelope: { type: 'code-collab-v2-content-envelope', ownerSessionId: owner, keyId,
    keyVersion: 1, algorithm: 'AES-256-GCM', iv: iv.toString('base64url'), ciphertext: ciphertext.toString('base64url') },
    decode: envelope => {
      const data = Buffer.from(envelope.ciphertext, 'base64url');
      const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(envelope.iv, 'base64url'));
      decipher.setAAD(aad);
      decipher.setAuthTag(data.subarray(-16));
      return JSON.parse(Buffer.concat([decipher.update(data.subarray(0, -16)), decipher.final()]).toString());
    } };
}

const text = value => ({ kind: 'text', text: { encoding: 'plain', text: value, rawBytes: Buffer.byteLength(value) } });
const source = { machineID: 'machine', ownerSessionID: 'parent' };
const response = (changes = {}) => ({ status: 'ok', path: 'src/App.swift', turnId: 'turn',
  oldSnapshot: text('old\n旧'), newSnapshot: text('new\n新'), ...changes });
const load = (payload, options = {}) => loadTurnDiff(source, {}, 'workspace', 'tab', 'turn', 'src/App.swift',
  options.signal ?? new AbortController().signal,
  options.request ?? (async () => reference(options.owner ?? 'parent', payload).envelope));

test('envelopes interoperate with Lody AES-GCM key, AAD and base64url rules', async () => {
  const payload = { sessionId: 'tab', turnId: 'turn', path: 'src/你好.swift' };
  const ref = reference('parent', payload);
  assert.deepEqual(await decryptDiffPayload('parent', ref.envelope), payload);
  const encrypted = await encryptDiffPayload('parent', payload);
  assert.equal(encrypted.keyId, ref.envelope.keyId);
  assert.deepEqual(ref.decode(encrypted), payload);
  assert.notEqual(encrypted.iv, (await encryptDiffPayload('parent', payload)).iv);
});

test('requests the correct workspace, machine, child turn and encrypted parent owner', async () => {
  const preview = await load(response(), { request: async (access, workspace, machine, method, params, signal, timeout) => {
    assert.equal(workspace, 'workspace');
    assert.equal(machine, 'machine');
    assert.equal(method, 'code-collab/open-turn-diff');
    assert.equal(timeout, 30000);
    assert.equal(signal.aborted, false);
    assert.deepEqual(reference('parent', {}).decode(params), { sessionId: 'tab', turnId: 'turn', path: 'src/App.swift' });
    return reference('parent', response()).envelope;
  } });
  assert.equal(preview.status, 'ready');
  assert.equal(preview.edit.oldText, 'old\n旧');
  assert.equal(preview.edit.newText, 'new\n新');
});

test('rejects wrong owner, key, tampering, protocol and wrong turn', async () => {
  await assert.rejects(load(response(), { owner: 'another' }), /owner/);
  for (const patch of [{ keyId: 'wrong' }, { algorithm: 'AES-CBC' }, { keyVersion: 2 },
    { iv: Buffer.alloc(12, 8).toString('base64url') }]) {
    await assert.rejects(decryptDiffPayload('parent', { ...reference('parent', response()).envelope, ...patch }));
  }
  await assert.rejects(load(response({ turnId: 'another' })), /requested turn/);
  await assert.rejects(load(response({ path: 'src/Other.swift' })), /requested file/);
});

test('decodes compressed UTF-8 and missing sides for additions and deletions', async () => {
  const value = 'let 文本 = "你好"\r\n';
  const compressed = gzipSync(value);
  const snapshot = { kind: 'text', text: { encoding: 'gzip-base64', data: compressed.toString('base64'),
    compressedBytes: compressed.length, rawBytes: Buffer.byteLength(value) } };
  const added = await load(response({ oldSnapshot: { kind: 'missing' }, newSnapshot: snapshot }));
  assert.equal(added.edit.oldText, '');
  assert.equal(added.edit.newText, value);
  const deleted = await load(response({ oldSnapshot: snapshot, newSnapshot: { kind: 'missing' } }));
  assert.equal(deleted.edit.newText, '');
});

test('bounds size, lines and decompression growth, and rejects malformed sizes', async () => {
  assert.equal((await load(response({ oldSnapshot: text('a'.repeat(66000)), newSnapshot: text('b'.repeat(66000)) }))).reason, 'too_large');
  assert.equal((await load(response({ newSnapshot: text('x\n'.repeat(2001)) }))).reason, 'too_large');
  assert.equal((await load(response({ newSnapshot: { kind: 'too_large' } }))).reason, 'too_large');
  const compressed = gzipSync('x'.repeat(256 * 1024));
  await assert.rejects(load(response({ newSnapshot: { kind: 'text', text: { encoding: 'gzip-base64',
    data: compressed.toString('base64'), compressedBytes: compressed.length, rawBytes: 10 } } })), /exceeds/);
  await assert.rejects(load(response({ oldSnapshot: { kind: 'text', text: { encoding: 'plain', text: '你好', rawBytes: 2 } } })), /size mismatch/);
});

test('reports explicit unavailable states and leaves transient errors retryable', async () => {
  assert.equal((await load(response({ newSnapshot: { kind: 'binary' } }))).reason, 'binary');
  assert.equal((await load(response({ status: 'unavailable', reason: 'turn_unavailable' }))).reason, 'turn_unavailable');
  assert.equal((await load({ status: 'error', code: 'machine_offline' })).reason, 'machine_offline');
  assert.equal((await load(response(), { request: async () => { throw Object.assign(new Error('Old machine'), { code: 'method_unavailable' }); } })).reason, 'unsupported');
  assert.equal((await load(response(), { request: async () => { throw Object.assign(new Error('Not readable'), { code: 'permission_denied' }); } })).reason, 'permission_denied');
  await assert.rejects(load(response({ status: 'unavailable', reason: 'transient_io' })), /snapshots/);
});

test('cancellation before request and after a late reply never publishes text', async () => {
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(load(response(), { signal: controller.signal, request: async () => assert.fail('Must not send') }), { name: 'AbortError' });
  const during = new AbortController();
  await assert.rejects(load(response(), { signal: during.signal, request: async () => {
    during.abort();
    return reference('parent', response()).envelope;
  } }), { name: 'AbortError' });
});

test('resolves machine and owner from workspace metadata, rejects deleted or foreign parents', async () => {
  const rows = [{ docId: 'session-tab', meta: { machineId: 'machine', parentSessionId: 'parent' } },
    { docId: 'session-parent', meta: { machineId: 'machine' } }];
  const repo = { listDoc: async () => rows };
  const signal = new AbortController().signal;
  assert.deepEqual(await turnDiffSource(repo, 'tab', signal), source);
  rows[1].meta.machineId = 'another';
  await assert.rejects(turnDiffSource(repo, 'tab', signal), /owner/);
  rows[0].deleted = true;
  await assert.rejects(turnDiffSource(repo, 'tab', signal), /machine/);
  await assert.rejects(turnDiffSource(repo, 'unknown', signal), /machine/);
});
