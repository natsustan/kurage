import { build } from 'esbuild';
import { readFile, writeFile } from 'node:fs/promises';

const output = '../KurageApp/Resources/session-bridge.js';
await build({
  entryPoints: ['bridge.js'],
  outfile: output,
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'safari18',
  minify: true,
  alias: {
    '@loro-dev/flock-wasm': '@loro-dev/flock-wasm/base64',
    'loro-crdt': 'loro-crdt/base64',
  },
});

// WKWebView can load a bundled classic script from file://, while dynamic module
// imports from that origin are blocked by WebKit's module CORS checks.
const source = await readFile(output, 'utf8');
const zstdWasm = await readFile('node_modules/@loro-dev/streams-crdt/dist/zstd.wasm');
const embeddedWasmURL = `new URL("data:application/wasm;base64,${zstdWasm.toString('base64')}")`;
const wasmURLExpression = 'new URL("./zstd.wasm",window.location.href)';
const classicSource = source.replaceAll('import.meta.url', 'window.location.href');
if (!classicSource.includes(wasmURLExpression)) {
  throw new Error('The Streams zstd loader changed; update its bundled WASM URL.');
}
await writeFile(
  output,
  `window.kurageBridgeReady=(async()=>{\n${classicSource.replaceAll(wasmURLExpression, embeddedWasmURL)}\n})();\n`,
);
