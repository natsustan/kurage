import test from 'node:test';
import assert from 'node:assert/strict';
import { createNativeFetch } from './native-fetch.mjs';

function harness() {
  const commands = [];
  const bridge = createNativeFetch(async command => { commands.push(command); }, fetch);
  return { ...bridge, commands };
}

async function nextCommand(bridge) {
  for (let attempt = 0; attempt < 20 && bridge.commands.length === 0; attempt++) {
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return bridge.commands[0];
}

test('headers and partial UTF-8 SSE bytes arrive before the response ends', async () => {
  const bridge = harness();
  const pending = bridge.fetch('https://example.test/ds/lody/test');
  const { id } = await nextCommand(bridge);
  await bridge.receive({ id, type: 'headers', status: 200, headers: { 'content-type': 'text/event-stream' } });
  const response = await pending;
  const reader = response.body.getReader();
  const encoded = new TextEncoder().encode('data: 你好\n\n');
  let all = [];
  for (const bytes of [encoded.slice(0, 7), encoded.slice(7)]) {
    await bridge.receive({ id, type: 'chunk', body: Buffer.from(bytes).toString('base64') });
    const result = await reader.read();
    assert.equal(result.done, false);
    all.push(...result.value);
  }
  assert.equal(new TextDecoder().decode(Uint8Array.from(all)), 'data: 你好\n\n');
  await bridge.receive({ id, type: 'end' });
  assert.equal((await reader.read()).done, true);
});

test('aborting a live body cancels native work and ignores late chunks', async () => {
  const bridge = harness();
  const controller = new AbortController();
  const pending = bridge.fetch('https://example.test/ds/lody/test', { signal: controller.signal });
  const { id } = await nextCommand(bridge);
  await bridge.receive({ id, type: 'headers', status: 200, headers: {} });
  const reader = (await pending).body.getReader();
  controller.abort();
  await assert.rejects(reader.read(), { name: 'AbortError' });
  await bridge.receive({ id, type: 'chunk', body: 'YQ==' });
  assert.ok(bridge.commands.some(command => command.command === 'cancel' && command.id === id));
});

test('reader cancellation releases backpressure and cancels native request', async () => {
  const bridge = harness();
  const pending = bridge.fetch('https://example.test/ds/lody/test');
  const { id } = await nextCommand(bridge);
  await bridge.receive({ id, type: 'headers', status: 200, headers: {} });
  const response = await pending;
  const delivered = bridge.receive({ id, type: 'chunk', body: Buffer.alloc(65536).toString('base64') });
  await response.body.cancel();
  await delivered;
  assert.equal(bridge.commands.at(-1).command, 'cancel');
});

test('network failures reject fetch before headers and body after headers', async () => {
  for (const afterHeaders of [false, true]) {
    const bridge = harness();
    const pending = bridge.fetch('https://example.test/ds/lody/test');
    const { id } = await nextCommand(bridge);
    if (afterHeaders) await bridge.receive({ id, type: 'headers', status: 200, headers: {} });
    const failed = afterHeaders ? (await pending).text() : pending;
    const rejection = assert.rejects(failed, /Streams request failed/);
    await bridge.receive({ id, type: 'error' });
    await rejection;
  }
});

test('POST body reaches the native proxy with exact UTF-8 bytes', async () => {
  const bridge = harness();
  const pending = bridge.fetch('https://example.test/ds/lody/test', {
    method: 'POST', body: '你好', headers: { 'content-type': 'text/plain' },
  });
  const command = await nextCommand(bridge);
  assert.equal(command.method, 'POST');
  assert.equal(Buffer.from(command.body, 'base64').toString('utf8'), '你好');
  assert.equal(command.headers['content-type'], 'text/plain');
  await bridge.receive({ id: command.id, type: 'headers', status: 200, headers: {} });
  await bridge.receive({ id: command.id, type: 'end' });
  assert.equal((await pending).status, 200);
});
