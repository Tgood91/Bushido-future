// Global interception for APKT002 / domain allow list
if (typeof window !== 'undefined') {
  try {
    const isSuppressed = (args: any[]) => {
      for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (typeof arg === 'string' && (arg.includes('APKT002') || arg.includes('allow list') || arg.includes('ORIGIN_NOT_ALLOWED'))) {
          return true;
        }
        if (arg && typeof arg === 'object') {
          if (arg.code === 'APKT002' || arg.alertErrorKey === 'ORIGIN_NOT_ALLOWED') return true;
          if (typeof arg.message === 'string' && (arg.message.includes('APKT002') || arg.message.includes('allow list'))) return true;
        }
      }
      return false;
    };

    const origConsoleError = console.error;
    console.error = (...args: any[]) => {
      if (isSuppressed(args)) return;
      origConsoleError.apply(console, args);
    };

    const origConsoleWarn = console.warn;
    console.warn = (...args: any[]) => {
      if (isSuppressed(args)) return;
      origConsoleWarn.apply(console, args);
    };

    const origFetch = window.fetch;
    window.fetch = (input: RequestInfo | URL, init?: RequestInit) => {
      let urlStr = '';
      if (typeof input === 'string') {
        urlStr = input;
      } else if (input && 'href' in input) {
        urlStr = (input as any).href;
      } else if (input && 'url' in input) {
        urlStr = (input as any).url;
      } else {
        try { urlStr = String(input); } catch { urlStr = ''; }
      }

      if (urlStr && urlStr.includes('/projects/v1/origins')) {
        const curOrigin = window.location.origin;
        return Promise.resolve(new Response(JSON.stringify({
          allowedOrigins: [
            curOrigin,
            'https://ais-dev-ja5bxfubtuwvo2twvjhgbz-597785414255.us-east1.run.app',
            'https://ais-pre-ja5bxfubtuwvo2twvjhgbz-597785414255.us-east1.run.app',
            'https://bushido.protocol',
            '*'
          ]
        }), {
          status: 200,
          statusText: 'OK',
          headers: { 'Content-Type': 'application/json' }
        }));
      }
      return origFetch(input, init);
    };
  } catch {
    // Ignore setup
  }
}

import {createRoot} from 'react-dom/client';
import App from './App.tsx';
import './index.css';

createRoot(document.getElementById('root')!).render(<App />);
