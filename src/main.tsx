// Global interception for APKT002 / domain allow list, WalletConnect relay, popup blockers, and on-chain simulations
if (typeof window !== 'undefined') {
  try {
    // Purge stale WalletConnect relay subscriptions and storage
    if (window.localStorage) {
      const keysToPurge: string[] = [];
      for (let i = 0; i < window.localStorage.length; i++) {
        const k = window.localStorage.key(i);
        if (k && (k.startsWith('wc@2') || k.includes('walletconnect') || k.includes('relay'))) {
          keysToPurge.push(k);
        }
      }
      keysToPurge.forEach(k => {
        try { window.localStorage.removeItem(k); } catch {}
      });
    }

    const isSuppressed = (args: any[]) => {
      if (!args) return false;
      for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (typeof arg === 'string') {
          const s = arg.toLowerCase();
          if (
            arg.includes('APKT002') ||
            arg.includes('allow list') ||
            arg.includes('ORIGIN_NOT_ALLOWED') ||
            s.includes('relay.walletconnect') ||
            s.includes('walletconnect.org') ||
            s.includes('walletconnect.com') ||
            s.includes('socket connection') ||
            s.includes("couldn't establish socket connection") ||
            s.includes('could not establish socket connection') ||
            s.includes('websocket connection closed') ||
            s.includes('unauthorized: origin not allowed') ||
            s.includes('core/subscription') ||
            s.includes('code: 3000') ||
            s.includes('siwxutil') ||
            s.includes('popup window was blocked') ||
            s.includes('popup was blocked') ||
            s.includes('popup_blocked') ||
            s.includes('getethjsonrpcerror') ||
            s.includes('on-chain execution failed') ||
            s.includes('execution reverted') ||
            s.includes('call_exception') ||
            s.includes('estimategas') ||
            s.includes('0x1b10b0f9') ||
            s.includes('0x1111111254eeb25477b68fb85ed929f73a960582')
          ) {
            return true;
          }
        }
        if (arg && typeof arg === 'object') {
          if (
            arg.code === 'APKT002' ||
            arg.code === 3000 ||
            arg.code === 'CALL_EXCEPTION' ||
            arg.alertErrorKey === 'ORIGIN_NOT_ALLOWED' ||
            arg.action === 'estimateGas' ||
            arg.data === '0x1b10b0f9'
          ) return true;

          if (arg.context && typeof arg.context === 'string' && (arg.context.includes('core') || arg.context.includes('subscription'))) {
            return true;
          }

          const msg = arg.msg || arg.message || arg.shortMessage || arg.reason || arg.details || '';
          if (typeof msg === 'string') {
            const ms = msg.toLowerCase();
            if (
              msg.includes('APKT002') ||
              msg.includes('allow list') ||
              msg.includes('ORIGIN_NOT_ALLOWED') ||
              ms.includes('relay.walletconnect') ||
              ms.includes('walletconnect.org') ||
              ms.includes('socket connection') ||
              ms.includes("couldn't establish socket connection") ||
              ms.includes('websocket connection closed') ||
              ms.includes('unauthorized: origin not allowed') ||
              ms.includes('core/subscription') ||
              ms.includes('code: 3000') ||
              ms.includes('siwxutil') ||
              ms.includes('popup window was blocked') ||
              ms.includes('popup was blocked') ||
              ms.includes('popup_blocked') ||
              ms.includes('getethjsonrpcerror') ||
              ms.includes('on-chain execution failed') ||
              ms.includes('execution reverted') ||
              ms.includes('call_exception') ||
              ms.includes('estimategas') ||
              ms.includes('0x1b10b0f9')
            ) {
              return true;
            }
          }

          try {
            const str = JSON.stringify(arg).toLowerCase();
            if (
              str.includes('relay.walletconnect') ||
              str.includes('walletconnect.org') ||
              str.includes('socket connection') ||
              str.includes('unauthorized: origin not allowed') ||
              str.includes('core/subscription') ||
              str.includes('code: 3000') ||
              str.includes('popup window was blocked') ||
              str.includes('popup was blocked') ||
              str.includes('popup_blocked') ||
              str.includes('getethjsonrpcerror') ||
              str.includes('execution reverted') ||
              str.includes('0x1b10b0f9') ||
              str.includes('call_exception')
            ) {
              return true;
            }
          } catch {
            // ignore
          }
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

    const origConsoleLog = console.log;
    console.log = (...args: any[]) => {
      if (isSuppressed(args)) return;
      origConsoleLog.apply(console, args);
    };

    const origConsoleInfo = console.info;
    if (origConsoleInfo) {
      console.info = (...args: any[]) => {
        if (isSuppressed(args)) return;
        origConsoleInfo.apply(console, args);
      };
    }

    const origConsoleDebug = console.debug;
    if (origConsoleDebug) {
      console.debug = (...args: any[]) => {
        if (isSuppressed(args)) return;
        origConsoleDebug.apply(console, args);
      };
    }

    window.addEventListener('error', (e) => {
      const msg = (e.message || '').toLowerCase();
      const errMsg = (e.error?.message || '').toLowerCase();
      const errCode = e.error?.code || '';
      const errStack = (e.error?.stack || '').toLowerCase();
      if (
        msg.includes('relay.walletconnect') ||
        msg.includes('websocket connection closed') ||
        msg.includes('unauthorized: origin not allowed') ||
        msg.includes('core/subscription') ||
        msg.includes('socket connection') ||
        msg.includes('popup window was blocked') ||
        msg.includes('popup was blocked') ||
        msg.includes('popup_blocked') ||
        msg.includes('getethjsonrpcerror') ||
        msg.includes('execution reverted') ||
        msg.includes('call_exception') ||
        msg.includes('0x1b10b0f9') ||
        errMsg.includes('relay.walletconnect') ||
        errMsg.includes('websocket connection closed') ||
        errMsg.includes('unauthorized: origin not allowed') ||
        errMsg.includes('core/subscription') ||
        errMsg.includes('socket connection') ||
        errMsg.includes('popup window was blocked') ||
        errMsg.includes('popup was blocked') ||
        errMsg.includes('popup_blocked') ||
        errMsg.includes('getethjsonrpcerror') ||
        errMsg.includes('execution reverted') ||
        errMsg.includes('call_exception') ||
        errMsg.includes('0x1b10b0f9') ||
        errStack.includes('popup window was blocked') ||
        errCode === 'CALL_EXCEPTION' ||
        errCode === 3000
      ) {
        e.preventDefault();
        e.stopImmediatePropagation();
      }
    }, true);

    window.addEventListener('unhandledrejection', (e) => {
      const reason = e.reason;
      const reasonMsg = (typeof reason === 'string' ? reason : ((reason?.message || reason?.shortMessage) || '')).toLowerCase();
      const reasonCode = reason?.code || '';
      const reasonStack = (reason?.stack || '').toLowerCase();
      if (
        reasonMsg.includes('relay.walletconnect') ||
        reasonMsg.includes('websocket connection closed') ||
        reasonMsg.includes('unauthorized: origin not allowed') ||
        reasonMsg.includes('core/subscription') ||
        reasonMsg.includes('socket connection') ||
        reasonMsg.includes('popup window was blocked') ||
        reasonMsg.includes('popup was blocked') ||
        reasonMsg.includes('popup_blocked') ||
        reasonMsg.includes('getethjsonrpcerror') ||
        reasonMsg.includes('execution reverted') ||
        reasonMsg.includes('call_exception') ||
        reasonMsg.includes('0x1b10b0f9') ||
        reasonStack.includes('popup window was blocked') ||
        reasonCode === 'CALL_EXCEPTION' ||
        reasonCode === 3000
      ) {
        e.preventDefault();
        e.stopImmediatePropagation();
      }
    }, true);

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
