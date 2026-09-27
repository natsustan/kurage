import test from 'node:test';
import assert from 'node:assert/strict';
import { projectFileChanges } from './file-changes.mjs';
import { projectConversation } from './conversation-projection.mjs';
import { conversationPatch } from './conversation-observer.mjs';

const tool = (status, content) => ({ type: 'tool_call', toolCallId: 't', status, content });
const diff = { type: 'diff', path: 'src/App.swift', oldText: 'old', newText: 'new' };

test('projects summary-only turns and retains repeated paths separately by turn', () => {
  const history = [
    { id: 'u', role: 'user' },
    { id: 'a', role: 'assistant', fileDiff: [{ filePath: diff.path, add: 2, del: 1 }], items: [] },
    { id: 'v', role: 'user' },
    { id: 'b', role: 'assistant', fileDiff: [{ filePath: diff.path, add: 3, del: 0 }], items: [] },
  ];
  const result = projectConversation('s', history);
  assert.equal(result.turns.length, 0);
  assert.deepEqual(result.fileChanges.map(group => [group.id, group.turnNumber, group.files[0].additions]),
    [['a', 1, 2], ['b', 2, 3]]);
  const next = projectConversation('s', history.slice(0, 2));
  assert.deepEqual(conversationPatch(result, next).fileChanges, next.fileChanges);
  assert.equal(conversationPatch(next, projectConversation('s', [])).fileChanges, null);
  assert.equal(conversationPatch(next, next).replacesFileChanges, undefined);
  assert.equal(conversationPatch(next, next).fileChanges, undefined);
});

test('only completed structured diffs are evidence; summaries are authoritative', () => {
  const [group] = projectFileChanges([{ id: 'a', role: 'assistant',
    fileDiff: [{ filePath: diff.path, add: 10, del: 4 }],
    items: [tool('failed', [{ ...diff, path: 'failed' }]),
      tool('in_progress', [{ ...diff, path: 'pending' }]), tool('completed', [diff, diff]),
      { type: 'text', text: 'Modified imagined.txt' },
      { type: 'tool_call', status: 'completed', locations: [{ path: 'read-only' }] }],
  }]);
  assert.equal(group.files.length, 1);
  assert.equal(group.files[0].additions, 10);
  assert.equal(group.files[0].edits.length, 2);
  assert.notEqual(group.files[0].edits[0].id, group.files[0].edits[1].id);
});

test('malformed values do not break projection and unknown counts remain unknown', () => {
  const [group] = projectFileChanges([null, { id: 'u', role: 'user', fileDiff: [{ filePath: 'ignore' }] },
    { id: 'a', role: 'assistant', fileDiff: [null, {}, { filePath: 'bad\0path' },
      { filePath: 'ok', add: -1, del: Infinity }],
    items: [tool('completed', [null, { ...diff, oldText: {} }, { ...diff, oldText: null }])] }]);
  assert.equal(group.files.length, 2);
  assert.equal(group.files[0].additions, null);
  assert.equal(group.files[0].deletions, null);
  assert.equal(group.files[1].edits[0].oldText, '');
  assert.equal(group.files[1].additions, null);
});

test('oversized previews retain the file and summary without transferring large text', () => {
  const [group] = projectFileChanges([{ id: 'a', role: 'assistant', items: [
    tool('completed', [{ ...diff, newText: 'x'.repeat(129 * 1024) }]),
  ] }]);
  assert.equal(group.files[0].previewLimited, true);
  assert.deepEqual(group.files[0].edits, []);
});


test('equivalent display paths merge but unrelated absolute paths are never guessed', () => {
  const [group] = projectFileChanges([{ id: 'a', role: 'assistant',
    fileDiff: [{ filePath: './src/App.swift', add: 1, del: 1 }], items: [
      tool('completed', [diff, { ...diff, path: '/other/src/App.swift' }]),
    ] }]);
  assert.equal(group.files.length, 2);
  assert.equal(group.files[0].path, diff.path);
  assert.equal(group.files[0].edits.length, 1);
  assert.equal(group.files[0].additions, 1);
});


test('sums repeated file summaries instead of letting a later zero erase changes', () => {
  const [group] = projectFileChanges([{ id: 'a', role: 'assistant', fileDiff: [
    { filePath: 'KurageApp/App/AppModel.swift', add: 5, del: 0 },
    { filePath: 'KurageApp/Client/HTTPLodyClient.swift', add: 7, del: 0 },
    { filePath: 'KurageApp/App/AppModel.swift', add: 0, del: 0 },
    { filePath: 'KurageApp/Client/HTTPLodyClient.swift', add: 0, del: 0 },
  ] }]);
  assert.deepEqual(group.files.map(file => [file.path, file.additions, file.deletions]), [
    ['KurageApp/App/AppModel.swift', 5, 0],
    ['KurageApp/Client/HTTPLodyClient.swift', 7, 0],
  ]);
});

test('sums both directions for equivalent display paths without counting preview text twice', () => {
  const [group] = projectFileChanges([{ id: 'a', role: 'assistant', fileDiff: [
    { filePath: './src/App.swift', add: 2, del: 3 },
    { filePath: 'src/App.swift', add: 4, del: 1 },
  ], items: [tool('completed', [diff])] }]);
  assert.equal(group.files.length, 1);
  assert.equal(group.files[0].additions, 6);
  assert.equal(group.files[0].deletions, 4);
  assert.equal(group.files[0].edits.length, 1);
});

test('unknown or overflowing totals stay unknown, and genuine zero totals are retained', () => {
  const [group] = projectFileChanges([{ id: 'a', role: 'assistant', fileDiff: [
    { filePath: 'unknown', add: null, del: 1 },
    { filePath: 'unknown', add: 3, del: 2 },
    { filePath: 'overflow', add: Number.MAX_SAFE_INTEGER, del: 0 },
    { filePath: 'overflow', add: 1, del: 0 },
    { filePath: 'zero', add: 0, del: 0 },
  ] }]);
  assert.deepEqual(group.files.map(file => [file.additions, file.deletions]), [[null, 3], [null, 0], [0, 0]]);
});

test('snapshot replacement recomputes repeated summaries rather than accumulating across updates', () => {
  const turn = { id: 'a', role: 'assistant', items: [], fileDiff: [
    { filePath: diff.path, add: 5, del: 2 }, { filePath: diff.path, add: 1, del: 0 },
  ] };
  const before = projectConversation('s', [turn]);
  assert.equal(before.fileChanges[0].files[0].additions, 6);
  const after = projectConversation('s', [{ ...turn, fileDiff: [turn.fileDiff[1]] }]);
  const patch = conversationPatch(before, after);
  assert.equal(patch.replacesFileChanges, true);
  assert.equal(patch.fileChanges[0].files[0].additions, 1);
  assert.equal(patch.fileChanges[0].files[0].deletions, 0);
});
