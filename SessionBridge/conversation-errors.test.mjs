import test from 'node:test';
import assert from 'node:assert/strict';
import { projectConversation } from './conversation-projection.mjs';
import { conversationPatch } from './conversation-observer.mjs';

const failure = meta => ({ type: 'system_notice', name: 'chat_failed', ...(meta ? { meta } : {}) });
const assistant = items => ({ id: 'agent', role: 'assistant', finished: true, items });

test('projects system and assistant error-only turns with the complete provider message', () => {
  const message = 'Internal error: API Error: 400 {"error":{"message":"Sample model unavailable"},"status":400}\n';
  for (const role of ['system', 'assistant']) {
    const result = projectConversation('chat', [{ ...assistant([failure({ reason: 'acp_internal_error', message })]), role }]);
    assert.deepEqual(result.turns, [{ id: 'agent', author: 'agent', text: '', parts: [
      { type: 'error', id: 'notice-0', reason: 'acp_internal_error', message },
    ] }]);
  }
});

test('machine-authored system notices stay in history order and do not expose other system content', () => {
  const result = projectConversation('chat', [
    { id: 'user', role: 'user', items: [{ type: 'text', text: 'Test message' }] },
    { id: 'system-notice-1', role: 'system', items: [
      { type: 'text', text: 'not ordinary chat' }, failure({ reason: 'session_init_failed' }),
    ] },
    { id: 'system-notice-2', role: 'system', items: [failure({ reason: 'acp_internal_error' })] },
  ]);
  assert.deepEqual(result.turns.map(turn => turn.id), ['user', 'system-notice-1', 'system-notice-2']);
  assert.deepEqual(result.turns[1].parts, [{ type: 'error', id: 'notice-1', reason: 'session_init_failed' }]);
  assert.equal(result.turns[1].text, '');
  assert.equal(result.turns[1].timing, undefined);
});

test('missing, invalid, and new failure metadata keeps a visible fallback without projecting arbitrary objects', () => {
  for (const meta of [undefined, null, {}, 'invalid', { reason: {}, code: 400, message: [] }]) {
    assert.deepEqual(projectConversation('chat', [assistant([failure(meta)])]).turns[0].parts,
      [{ type: 'error', id: 'notice-0' }]);
  }
  assert.deepEqual(projectConversation('chat', [assistant([failure({ reason: 'future_reason', code: 'future_code',
    message: 'Details', privateData: 'not projected' })])]).turns[0].parts,
  [{ type: 'error', id: 'notice-0', reason: 'future_reason', code: 'future_code', message: 'Details' }]);
});

test('failures preserve source order and remain visible outside folded earlier work', () => {
  const turn = assistant([
    { type: 'thought', text: 'not exposed' },
    { type: 'tool_call', toolCallId: 'tool', kind: 'execute', title: 'Checking the project' },
    { type: 'text', text: 'Visible answer' },
    failure({ reason: 'acp_internal_error', message: 'First error' }),
    failure({ reason: 'acp_auth_required', message: 'Second error' }),
  ]);
  const result = projectConversation('chat', [turn]).turns[0];
  assert.deepEqual(result.parts, [{ type: 'text', text: 'Visible answer' },
    { type: 'error', id: 'notice-3', reason: 'acp_internal_error', message: 'First error' },
    { type: 'error', id: 'notice-4', reason: 'acp_auth_required', message: 'Second error' }]);
  assert.equal(result.work.parts.length, 1);
  assert.equal(result.work.parts[0].type, 'activity');
});

test('unrecognized notices and user-authored notices do not become errors or prose', () => {
  const notices = ['agent_warning', 'future_notice', 'chat_failed'].map(name => ({ type: 'system_notice', name,
    meta: { message: 'Hidden' } }));
  const result = projectConversation('chat', [
    assistant(notices.slice(0, 2)), { id: 'user', role: 'user', items: notices },
  ]);
  assert.deepEqual(result.turns, []);
});

test('live error additions, growth, and deletions emit patches without changing the turn identity', () => {
  const live = { id: 'system-notice-1', role: 'system', items: [] };
  const before = projectConversation('chat', [live]);
  live.items.push(failure({ reason: 'acp_internal_error', message: 'First detail' }));
  const added = projectConversation('chat', [live]);
  assert.deepEqual(conversationPatch(before, added).changed, added.turns);
  live.items[0].meta.message += '\nMore detail';
  const grown = projectConversation('chat', [live]);
  assert.equal(grown.turns[0].parts[0].id, added.turns[0].parts[0].id);
  assert.deepEqual(conversationPatch(added, grown).changed, grown.turns);
  live.items = [];
  live.finished = true;
  const removed = projectConversation('chat', [live]);
  assert.deepEqual(conversationPatch(grown, removed).order, []);
  assert.deepEqual(conversationPatch(grown, grown).changed, []);
});
