const nativeFetch = (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
  if (typeof window !== 'undefined' && typeof window.fetch === 'function') {
    return window.fetch(input, init);
  }
  if (typeof globalThis !== 'undefined' && typeof globalThis.fetch === 'function') {
    return globalThis.fetch(input, init);
  }
  return Promise.reject(new Error('No fetch implementation found'));
};

export const fetch = nativeFetch;
export const Headers = typeof window !== 'undefined' ? window.Headers : (typeof globalThis !== 'undefined' ? globalThis.Headers : class {});
export const Request = typeof window !== 'undefined' ? window.Request : (typeof globalThis !== 'undefined' ? globalThis.Request : class {});
export const Response = typeof window !== 'undefined' ? window.Response : (typeof globalThis !== 'undefined' ? globalThis.Response : class {});

export default nativeFetch;
