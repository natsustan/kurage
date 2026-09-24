// Fetch over WKScriptMessageHandler. Response headers resolve fetch immediately;
// body chunks retain byte boundaries (including split UTF-8 and SSE frames).
export function createNativeFetch(send, fallback) {
  const requests = new Map();
  async function receive(event) {
    const entry = requests.get(event.id);
    if (!entry) return;
    if (event.type === 'headers') {
      entry.resolve(new Response([204, 205, 304].includes(event.status) ? null : entry.body, {
        status: event.status, headers: event.headers,
      }));
    } else if (event.type === 'chunk') {
      const bytes = Uint8Array.from(atob(event.body), c => c.charCodeAt(0));
      entry.controller.enqueue(bytes);
      if (entry.controller.desiredSize <= 0) {
        await new Promise(resolve => { entry.resume = resolve; });
      }
    } else {
      requests.delete(event.id);
      entry.cleanup();
      if (event.type === 'error') {
        const error = new TypeError('Streams request failed');
        entry.reject(error);
        entry.controller.error(error);
      } else entry.controller.close();
    }
  }
  function fetch(input, init) {
    const request = new Request(input, init);
    if (!request.url.startsWith('https://')) return fallback(input, init);
    if (request.signal.aborted) return Promise.reject(new DOMException('Aborted', 'AbortError'));
    const id = crypto.randomUUID();
    return new Promise((resolve, reject) => {
      const entry = { resolve, reject };
      const abort = (reason = new DOMException('Aborted', 'AbortError')) => {
        if (!requests.delete(id)) return;
        entry.cleanup();
        reject(reason);
        try { entry.controller.error(reason); } catch { /* Reader cancellation already closed it. */ }
        void send({ command: 'cancel', id }).catch(() => {});
      };
      entry.cleanup = () => {
        request.signal.removeEventListener('abort', onAbort);
        entry.resume?.();
        entry.resume = undefined;
      };
      const onAbort = () => abort();
      entry.body = new ReadableStream({
        start(controller) { entry.controller = controller; },
        pull() { entry.resume?.(); entry.resume = undefined; },
        cancel() { abort(); },
      }, { highWaterMark: 64 * 1024, size: chunk => chunk.byteLength });
      requests.set(id, entry);
      request.signal.addEventListener('abort', onAbort, { once: true });
      void (async () => {
        const bytes = request.body ? new Uint8Array(await request.arrayBuffer()) : null;
        if (!requests.has(id)) return;
        let body;
        if (bytes) {
          let binary = '';
          for (let index = 0; index < bytes.length; index += 32_768) {
            binary += String.fromCharCode(...bytes.subarray(index, index + 32_768));
          }
          body = btoa(binary);
        }
        await send({ command: 'start', id, url: request.url, method: request.method,
          headers: Object.fromEntries(request.headers.entries()), body });
      })().catch(abort);
    });
  }
  return { fetch, receive };
}
