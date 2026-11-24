// One bounded retry on the SAME configured route/model. No alternate models or credentials.
// Both attempts together fit inside the iOS client's 120s request / 150s resource deadline.
class ProviderFailure extends Error {
  constructor(status) {
    super(status === 429 ? "busy" : "llm_failed");
    this.retryable = [408, 429, 500, 502, 503, 504].includes(status);
    this.reason = "http_" + status;
  }
}
export async function fetchModelJSON(url, options, runtime = {}) {
  const request = runtime.fetchImpl ?? fetch;
  const pause = runtime.pause ?? (ms => new Promise(resolve => setTimeout(resolve, ms)));
  const signal = runtime.signal ?? (() => AbortSignal.timeout(45_000));
  const warn = runtime.warn ?? (reason => console.warn("ar_localize_provider_retry", reason));
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await request(url, { ...options, signal: signal() });
      if (!response.ok) {
        // Release a failed response without logging its potentially sensitive body.
        await response.body?.cancel().catch(() => {});
        throw new ProviderFailure(response.status);
      }
      return await response.json();
    } catch (error) {
      const transient = !(error instanceof ProviderFailure) || error.retryable;
      if (attempt === 1 || !transient) {
        throw new Error(error instanceof ProviderFailure ? error.message : "llm_failed");
      }
      // Log only a bounded classification. Never strings, tokens, payloads or upstream error text.
      warn(error instanceof ProviderFailure ? error.reason : "transport_or_timeout");
      await pause(1000);
    }
  }
  throw new Error("llm_failed");
}
