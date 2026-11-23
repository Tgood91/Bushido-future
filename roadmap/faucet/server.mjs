// Bushido one-tap testnet faucet: 0.05 ETH on Ethereum Sepolia and Base Sepolia.
//
// Env (set in Render; never commit):
//   FAUCET_PRIVATE_KEY   faucet wallet key (fund its address on both chains). Without it the faucet reports
//                        "not configured" and sends nothing.
//   ALLOWED_ORIGIN       page allowed to call /drip (default https://solving.onrender.com)
//   DRIP_ETH             amount per drip per chain (default 0.05)
//   DAILY_CAP_ETH        max total sent per chain per rolling 24 h (default 2 = 40 drips)
//   MAX_RECIPIENT_ETH    refuse wallets already holding at least this much (default 0.5)
//   RPC_SEPOLIA, RPC_BASE_SEPOLIA   override the RPCs from ../testnet/chains.json
//   PORT                 set by Render
//
// Limits: one drip per address per chain and one per client IP per chain every 24 h, plus the daily cap.
// They live in memory, so a restart clears them; the daily cap and the balance floor still bound the loss.
import http from 'node:http';
import { readFileSync } from 'node:fs';
import { ethers } from 'ethers';

const DAY = 24 * 60 * 60 * 1000;
const ORIGIN = process.env.ALLOWED_ORIGIN || 'https://solving.onrender.com';
const DRIP = ethers.parseEther(process.env.DRIP_ETH || '0.05');
const DAILY_CAP = ethers.parseEther(process.env.DAILY_CAP_ETH || '2');
const MAX_RECIPIENT = ethers.parseEther(process.env.MAX_RECIPIENT_ETH || '0.5');

let registry = {};
try {
  registry = JSON.parse(readFileSync(new URL('../testnet/chains.json', import.meta.url), 'utf8')).chains;
} catch {
  /* fall back to env/defaults below */
}
const CHAINS = {
  sepolia: { id: 11155111, name: 'Ethereum Sepolia', rpc: process.env.RPC_SEPOLIA || registry.sepolia?.rpc || 'https://ethereum-sepolia-rpc.publicnode.com', explorer: registry.sepolia?.explorer || 'https://sepolia.etherscan.io' },
  'base-sepolia': { id: 84532, name: 'Base Sepolia', rpc: process.env.RPC_BASE_SEPOLIA || registry['base-sepolia']?.rpc || 'https://sepolia.base.org', explorer: registry['base-sepolia']?.explorer || 'https://sepolia.basescan.org' },
};

const key = process.env.FAUCET_PRIVATE_KEY;
const wallets = {};
for (const [k, c] of Object.entries(CHAINS)) {
  // cacheTimeout -1: no 250 ms read cache, so balances reported right after a drip are current
  c.provider = new ethers.JsonRpcProvider(c.rpc, c.id, { staticNetwork: true, cacheTimeout: -1 });
  if (key) wallets[k] = new ethers.NonceManager(new ethers.Wallet(key, c.provider));
}
const faucetAddress = key ? new ethers.Wallet(key).address : null;

// ---- limits (in memory) ----
const lastDrip = new Map(); // `${chain}|addr|${address}` or `${chain}|ip|${ip}` -> timestamp
const sent = Object.fromEntries(Object.keys(CHAINS).map((k) => [k, []])); // [{ t, amount }]
const locks = {}; // serialise sends per chain so nonces never collide
function serial(k, fn) {
  const p = (locks[k] || Promise.resolve()).then(fn, fn); // run even if the previous send failed
  locks[k] = p.catch(() => {});
  return p;
}

const sentToday = (k) => {
  const now = Date.now();
  sent[k] = sent[k].filter((x) => now - x.t < DAY);
  return sent[k].reduce((s, x) => s + x.amount, 0n);
};
const recent = (id) => {
  const t = lastDrip.get(id);
  return t && Date.now() - t < DAY ? t : null;
};

function clientIp(req) {
  // Behind Render's proxy: prefer the proxy-set client IP headers; else the right-most X-Forwarded-For hop.
  const cf = req.headers['cf-connecting-ip'] || req.headers['true-client-ip'];
  if (cf) return String(cf).trim();
  const xff = String(req.headers['x-forwarded-for'] || '').split(',').map((s) => s.trim()).filter(Boolean);
  return xff.length ? xff[xff.length - 1] : req.socket.remoteAddress || 'unknown';
}

async function drip(k, to, ip) {
  const c = CHAINS[k];
  const idA = `${k}|addr|${to.toLowerCase()}`;
  const idI = `${k}|ip|${ip}`;
  const t = recent(idA) || recent(idI);
  if (t) return { status: 429, error: `already dripped on ${c.name}; try again in ${Math.ceil((t + DAY - Date.now()) / 3_600_000)} h` };
  if (sentToday(k) + DRIP > DAILY_CAP) return { status: 429, error: `${c.name} daily cap reached; try again later` };
  lastDrip.set(idA, Date.now()); // reserve before the async work so parallel requests can't double-drip
  lastDrip.set(idI, Date.now());
  try {
    if ((await c.provider.getBalance(to)) >= MAX_RECIPIENT) {
      throw Object.assign(new Error(`wallet already holds ≥ ${ethers.formatEther(MAX_RECIPIENT)} ETH on ${c.name}`), { status: 400 });
    }
    const w = wallets[k];
    if ((await c.provider.getBalance(faucetAddress)) < DRIP) throw Object.assign(new Error(`faucet is empty on ${c.name}`), { status: 503 });
    const tx = await serial(k, async () => {
      try {
        return await w.sendTransaction({ to, value: DRIP });
      } catch (e) {
        w.reset(); // resync the nonce from the chain after a failed send
        throw e;
      }
    });
    sent[k].push({ t: Date.now(), amount: DRIP });
    return { status: 200, chain: k, name: c.name, amount: ethers.formatEther(DRIP), tx: tx.hash, explorer: `${c.explorer}/tx/${tx.hash}` };
  } catch (e) {
    lastDrip.delete(idA); // nothing was sent: release the reservation
    lastDrip.delete(idI);
    return { status: e.status || 502, error: e.status ? e.message : `send failed on ${c.name}: ${e.shortMessage || e.message}` };
  }
}

async function status() {
  const chains = {};
  for (const [k, c] of Object.entries(CHAINS)) {
    let balance = null;
    if (faucetAddress) balance = await c.provider.getBalance(faucetAddress).then(ethers.formatEther).catch(() => null);
    chains[k] = { name: c.name, chainId: c.id, balance, sentToday: ethers.formatEther(sentToday(k)), dailyCap: ethers.formatEther(DAILY_CAP) };
  }
  return { configured: Boolean(key), faucetAddress, drip: ethers.formatEther(DRIP), chains };
}

function send(res, code, body, origin) {
  const headers = { 'content-type': 'application/json', 'cache-control': 'no-store', vary: 'Origin' };
  if (origin === ORIGIN) Object.assign(headers, { 'access-control-allow-origin': ORIGIN, 'access-control-allow-methods': 'GET, POST, OPTIONS', 'access-control-allow-headers': 'content-type' });
  res.writeHead(code, headers);
  res.end(JSON.stringify(body));
}

const server = http.createServer(async (req, res) => {
  const origin = req.headers.origin;
  const url = new URL(req.url, 'http://x');
  try {
    if (req.method === 'OPTIONS') return send(res, 204, {}, origin);
    if (req.method === 'GET' && url.pathname === '/health') return send(res, 200, { ok: true }, origin);
    if (req.method === 'GET' && url.pathname === '/status') return send(res, 200, await status(), origin);
    if (req.method === 'POST' && url.pathname === '/drip') {
      if (origin !== ORIGIN) return send(res, 403, { error: 'origin not allowed' }, origin);
      if (!key) return send(res, 503, { error: 'faucet not configured yet' }, origin);
      let raw = '';
      for await (const chunk of req) {
        raw += chunk;
        if (raw.length > 1024) return send(res, 413, { error: 'body too large' }, origin);
      }
      let body;
      try { body = JSON.parse(raw || '{}'); } catch { return send(res, 400, { error: 'invalid JSON' }, origin); }
      const to = String(body.address || '');
      if (!ethers.isAddress(to) || to === ethers.ZeroAddress) return send(res, 400, { error: 'invalid address' }, origin);
      const chains = body.chain ? [String(body.chain)] : Object.keys(CHAINS);
      if (chains.some((k) => !CHAINS[k])) return send(res, 400, { error: `chain must be one of ${Object.keys(CHAINS).join(', ')}` }, origin);
      const ip = clientIp(req);
      const results = [];
      for (const k of chains) results.push(await drip(k, ethers.getAddress(to), ip));
      const ok = results.some((r) => r.status === 200);
      return send(res, ok ? 200 : results[0].status, { results }, origin);
    }
    return send(res, 404, { error: 'not found' }, origin);
  } catch (e) {
    return send(res, 500, { error: 'internal error' }, origin);
  }
});

const port = Number(process.env.PORT || 8080);
server.listen(port, () => console.log(`faucet on :${port}, origin ${ORIGIN}, ${key ? `wallet ${faucetAddress}` : 'NOT CONFIGURED (set FAUCET_PRIVATE_KEY)'}`));
export { server };
