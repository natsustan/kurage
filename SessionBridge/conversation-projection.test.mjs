import test from 'node:test';
import assert from 'node:assert/strict';
import { projectConversation } from './conversation-projection.mjs';

test('projects chat text without exposing structured events as prose', () => {
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
    turns: [
      { id: 'u1', author: 'user', text: 'Hello **world**' },
      { id: 'a1', author: 'agent', text: 'First paragraph\n\nSecond paragraph' },
    ],
    permission: null,
  });
});
