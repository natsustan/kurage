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
      {
        id: 'u1', author: 'user', text: 'Hello **world**',
        parts: [{ type: 'text', text: 'Hello **world**' }],
      },
      {
        id: 'a1', author: 'agent', text: 'First paragraph\n\nSecond paragraph',
        parts: [
          { type: 'text', text: 'First paragraph' },
          { type: 'text', text: 'Second paragraph' },
        ],
      },
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
      ],
    },
  ]);
});
