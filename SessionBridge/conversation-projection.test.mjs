import test from 'node:test';
import assert from 'node:assert/strict';
import { projectConversation } from './conversation-projection.mjs';

test('file-only turns survive long or missing display names', () => {
  for (const fileName of ['a'.repeat(251) + '.txt', '', undefined, '\0']) {
    const result = projectConversation('chat', [{ id: 'file-turn', role: 'user', items: [
      { type: 'file', fileId: 'file-1', fileName, sizeBytes: 12 },
    ] }]);
    assert.equal(result.turns.length, 1);
    assert.deepEqual(result.turns[0].parts, [{
      type: 'file', fileID: 'file-1',
      fileName: fileName?.startsWith('a') ? 'a'.repeat(200) : 'File', sizeBytes: 12,
    }]);
  }
});

const activity = (id, counts = {}, steps = []) => ({
  type: 'activity', id, commands: 0, reads: 0, edits: 0, searches: 0, fetches: 0, tools: 0, ...counts, steps,
});

test('projects chat text and summarizes tool calls without exposing them as prose', () => {
  const result = projectConversation('abc', [
    { id: 'u1', role: 'user', items: [{ type: 'text', text: 'Hello **world**' }] },
    { id: 'a1', role: 'assistant', items: [
      { type: 'thought', text: 'private reasoning' },
      { type: 'text', text: 'First paragraph' },
      { type: 'tool_call', text: 'unsafe summary', content: [{ type: 'text', text: 'tool output' }] },
      { type: 'text', text: 'Second paragraph' },
    ] },
    { id: 'a2', role: 'assistant', items: [{ type: 'tool_call', text: 'not chat' }] },
    { id: 's1', role: 'system', items: [{ type: 'text', text: 'system text' }] },
  ]);
  assert.deepEqual(result, {
    sessionID: 'abc',
    latestTurnNumber: 1,
    turns: [
      {
        id: 'u1', author: 'user', text: 'Hello **world**',
        parts: [{ type: 'text', text: 'Hello **world**' }],
      },
      {
        id: 'a1', author: 'agent', text: 'First paragraph\n\nSecond paragraph',
        parts: [
          { type: 'text', text: 'First paragraph' },
          activity('2:', { tools: 1 }),
          { type: 'text', text: 'Second paragraph' },
        ],
      },
      { id: 'a2', author: 'agent', text: '', parts: [activity('0:', { tools: 1 })] },
    ],
    permission: null,
  });
});

test('projects session images in order and keeps image-only turns', () => {
  const png = {
    type: 'image', imageId: 'shot', mimeType: 'image/png', sizeBytes: 12,
    width: 20, height: 10, fileName: '  shot.png ',
  };
  const result = projectConversation('abc', [
    { id: 'u1', role: 'user', items: [
      png,
      { type: 'text', text: 'Look' },
      { type: 'image', imageId: 'nope', mimeType: 'image/svg+xml', sizeBytes: 4 },
      { type: 'image', imageId: '../x', mimeType: 'image/png', sizeBytes: 4 },
      { type: 'image', imageId: 'huge', mimeType: 'image/png', sizeBytes: 5 * 1024 * 1024 + 1 },
    ] },
    { id: 'a1', role: 'assistant', items: [
      { type: 'text', text: 'Generated' },
      { type: 'image_group', images: [
        { imageId: 'one', mimeType: 'image/jpeg', sizeBytes: 8, storageSessionId: 'fork-session' },
        { imageId: 'skip', mimeType: 'text/plain', sizeBytes: 8 },
        { imageId: 'two' },
      ] },
      { type: 'tool_call', content: [{ type: 'image', imageId: 'tool', mimeType: 'image/png', sizeBytes: 4 }] },
    ] },
    { id: 'a2', role: 'assistant', items: [{ type: 'tool_call', text: 'not chat' }] },
  ]);
  assert.deepEqual(result.turns, [
    {
      id: 'u1', author: 'user', text: 'Look',
      parts: [
        { type: 'image', imageID: 'shot', mimeType: 'image/png', fileName: 'shot.png', width: 20, height: 10 },
        { type: 'text', text: 'Look' },
      ],
    },
    {
      id: 'a1', author: 'agent', text: 'Generated',
      parts: [
        { type: 'text', text: 'Generated' },
        { type: 'image', imageID: 'one', mimeType: 'image/jpeg', storageSessionID: 'fork-session' },
        { type: 'image', imageID: 'two' },
        activity('2:', { tools: 1 }),
      ],
    },
    { id: 'a2', author: 'agent', text: '', parts: [activity('0:', { tools: 1 })], timing: { permissionWaitMs: 0 } },
  ]);
});

const finishedTurn = (items, extra = {}) => ({
  id: 'a1', role: 'assistant', finished: true, items,
  timestamp: '2026-09-27T14:00:00.000Z', endedAt: Date.parse('2026-09-27T14:01:27.400Z'), ...extra,
});

test('hiding a completed retry preserves subsequent activity and step identities', () => {
  for (const toolCallId of ['read', undefined]) {
    const project = status => projectConversation('s', [{
      id: 'a1', role: 'assistant', items: [
        { type: 'tool_call', activityKind: 'codex_retry', status, toolCallId: 'retry' },
        { type: 'tool_call', toolCallId, kind: 'read', title: 'Read file' },
      ],
    }]).turns[0].parts;
    const before = project('in_progress');
    assert.deepEqual(project('completed'), before);
    assert.equal(before[0].id, `1:${toolCallId ?? ''}`);
    assert.equal(before[0].steps[0].id, toolCallId ?? '#1');
  }
});

test('a finished turn folds earlier work behind its duration and keeps the answer visible', () => {
  const result = projectConversation('s', [finishedTurn([
    { type: 'thought', text: 'private reasoning' },
    { type: 'text', text: 'I will commit and push.' },
    { type: 'tool_call', toolCallId: 't1', kind: 'execute', title: 'git status', status: 'completed' },
    { type: 'tool_call', toolCallId: 't2', kind: 'read', title: 'Read a.swift', locations: [{ path: 'a.swift' }] },
    { type: 'tool_call', toolCallId: 't3', kind: 'read', title: 'Read a.swift again', locations: [{ path: 'a.swift' }] },
    { type: 'tool_call', toolCallId: 't4', kind: 'edit', content: [{ type: 'diff', path: 'b.swift', newText: '' }] },
    { type: 'tool_call', toolCallId: 't5', kind: 'other', content: [{ type: 'terminal_output', output: 'ok' }] },
    { type: 'tool_call', toolCallId: 't6', kind: 'think', title: 'Thinking' },
    { type: 'text', text: 'Pushed a4f33b3.' },
    { type: 'text', text: 'Workspace is clean.' },
    { type: 'image', imageId: 'shot' },
  ], { permissionWaitMs: 20_000 })]);
  const [turn] = result.turns;
  assert.equal(turn.text, 'Pushed a4f33b3.\n\nWorkspace is clean.');
  assert.deepEqual(turn.parts, [
    { type: 'text', text: 'Pushed a4f33b3.' },
    { type: 'text', text: 'Workspace is clean.' },
    { type: 'image', imageID: 'shot' },
  ]);
  assert.deepEqual(turn.work, {
    durationMs: 67_400,
    parts: [
      { type: 'text', text: 'I will commit and push.' },
      activity('2:t1', { commands: 2, reads: 1, edits: 1 }, [
        { id: 't1', kind: 'command', title: 'git status' },
        { id: 't2', kind: 'read', title: 'Read a.swift' },
        { id: 't3', kind: 'read', title: 'Read a.swift again' },
      ]),
    ],
  });
  assert.ok(!JSON.stringify(result).includes('private reasoning'));
});

test('streaming, answerless, and work-free turns stay expanded', () => {
  const work = [
    { type: 'text', text: 'Checking.' },
    { type: 'tool_call', toolCallId: 't1', kind: 'execute', title: 'npm test' },
  ];
  const streaming = projectConversation('s', [finishedTurn([...work, { type: 'text', text: 'Done.' }], { finished: false })]);
  assert.equal(streaming.turns[0].work, undefined);
  assert.equal(streaming.turns[0].parts.length, 3);
  // A cancelled turn that ends mid-tool has no answer to keep visible.
  const interrupted = projectConversation('s', [finishedTurn(work)]);
  assert.equal(interrupted.turns[0].work, undefined);
  assert.deepEqual(interrupted.turns[0].parts.map(part => part.type), ['text', 'activity']);
  const answerOnly = projectConversation('s', [finishedTurn([{ type: 'text', text: 'A' }, { type: 'text', text: 'B' }])]);
  assert.equal(answerOnly.turns[0].work, undefined);
  // Thought-only groups have no visible header, like Lody.
  const thoughtOnly = projectConversation('s', [finishedTurn([{ type: 'thought', text: 'x' }, { type: 'text', text: 'A' }])]);
  assert.equal(thoughtOnly.turns[0].work, undefined);
  assert.deepEqual(thoughtOnly.turns[0].parts, [{ type: 'text', text: 'A' }]);
});

test('duration is omitted without a valid end time and bounds long step titles', () => {
  const items = [
    { type: 'tool_call', toolCallId: 't1', kind: 'fetch', title: ` ${'x'.repeat(300)} ` },
    { type: 'tool_call', kind: 'search', title: '  ' },
    { type: 'subagent_task', taskId: 'hidden' },
    { type: 'text', text: 'Answer' },
  ];
  for (const extra of [{ endedAt: undefined }, { timestamp: 'nope' }, { endedAt: 0 }]) {
    const [turn] = projectConversation('s', [finishedTurn(items, extra)]).turns;
    assert.equal(turn.work.durationMs, undefined);
    assert.deepEqual(turn.work.parts, [activity('0:t1', { fetches: 1, searches: 1 }, [
      { id: 't1', kind: 'fetch', title: 'x'.repeat(200) },
    ])]);
  }
});

test('file attachments project explicit file metadata without inventing message text', () => {
  const result = projectConversation('chat', [{ id: 'u-file', role: 'user', items: [
    { type: 'file', fileId: 'f-1', fileName: 'notes.txt', sizeBytes: 12 },
    { type: 'file', fileId: '../bad', fileName: 'bad.txt', sizeBytes: 1 },
  ] }]);
  assert.equal(result.turns[0].text, '');
  assert.deepEqual(result.turns[0].parts, [{ type: 'file', fileID: 'f-1', fileName: 'notes.txt', sizeBytes: 12 }]);
});

test('live timing survives empty output, ends on completion and belongs only to the latest turn', () => {
  const entry = { id: 'live', role: 'assistant', timestamp: '2026-01-01T00:00:00Z', items: [], permissionWaitMs: 5000 };
  const project = history => projectConversation('chat', history).turns;
  assert.deepEqual(project([entry])[0].timing, { startedAtMs: Date.parse(entry.timestamp), permissionWaitMs: 5000 });
  assert.equal(project([{ ...entry, finished: true }]).length, 0);
  assert.equal(project([{ ...entry, endedAt: Date.parse(entry.timestamp) }]).length, 0);
  assert.equal(project([entry, { id: 'next', role: 'user', items: [{ type: 'text', text: 'Next' }] }]).length, 1);
  assert.deepEqual(project([{ ...entry, timestamp: 'invalid', permissionWaitMs: -1 }])[0].timing, { permissionWaitMs: 0 });
});

for (const attachment of [
  { type: 'image', imageId: 'before' },
  { type: 'file', fileId: 'before', fileName: 'before.txt', sizeBytes: 12 },
  { type: 'image_group', images: [{ imageId: 'one' }, { imageId: 'two' }] },
]) {
  test(`folded work stays after a leading ${attachment.type}`, () => {
    const [turn] = projectConversation('s', [finishedTurn([
      attachment,
      { type: 'text', text: 'Checking.' },
      { type: 'tool_call', kind: 'read', toolCallId: 'read', title: 'Read file' },
      { type: 'text', text: 'Answer.' },
    ])]).turns;
    const prefixLength = attachment.type === 'image_group' ? 2 : 1;
    assert.equal(turn.work.insertionIndex, prefixLength);
    const expanded = [...turn.parts];
    expanded.splice(turn.work.insertionIndex, 0, ...turn.work.parts);
    assert.deepEqual(expanded.map(part => part.type), [
      ...Array(prefixLength).fill(attachment.type === 'file' ? 'file' : 'image'),
      'text', 'activity', 'text',
    ]);
    assert.equal(expanded.at(-1).text, 'Answer.');
  });

  test(`interleaved ${attachment.type} keeps work expanded in source order`, () => {
    const items = [
      { type: 'tool_call', kind: 'read', toolCallId: 'first', title: 'Read first file' },
      attachment,
      { type: 'text', text: 'Checking the attachment.' },
      { type: 'tool_call', kind: 'read', toolCallId: 'second', title: 'Read second file' },
      { type: 'text', text: 'Answer.' },
    ];
    const [streaming] = projectConversation('s', [finishedTurn(items, { finished: false })]).turns;
    const [finished] = projectConversation('s', [finishedTurn(items)]).turns;
    assert.equal(finished.work, undefined);
    assert.deepEqual(finished.parts, streaming.parts);
    assert.equal(finished.parts[0].steps[0].id, 'first');
    assert.equal(finished.parts[1].type, attachment.type === 'file' ? 'file' : 'image');
    assert.equal(finished.parts.at(-2).steps[0].id, 'second');
    assert.equal(finished.parts.at(-1).text, 'Answer.');
  });
}
