// Shared helpers for the Bushido testnet solver, deploy and relay scripts.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { ethers } from 'ethers';

export { ethers };
export const C = JSON.parse(readFileSync(new URL('./contracts.json', import.meta.url))).contracts;
export const CHAINS = JSON.parse(readFileSync(new URL('../testnet/chains.json', import.meta.url))).chains;
export const PAIR = ['base-sepolia', 'arbitrum-sepolia']; // [home (collateral), remote (synthetic)]
export const U = 1_000_000n;
export const b32 = (a) => ethers.zeroPadValue(a, 32);
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
export const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

const big = (_, v) => (typeof v === 'bigint' ? v.toString() : v);
export const loadJson = (p, d) => (existsSync(p) ? JSON.parse(readFileSync(p, 'utf8')) : d);
export const saveJson = (p, v) => writeFileSync(p, JSON.stringify(v, big, 2));

/** RPC per chain: env override (e.g. a local anvil fork) else chains.json. */
export function rpcFor(key) {
  const env = { 'base-sepolia': 'BASE_RPC', 'arbitrum-sepolia': 'ARB_RPC' }[key];
  return process.env[env] || CHAINS[key].rpc;
}

/**
 * Signer: PRIVATE_KEY from the environment (your own testnet hot key; never commit it), or, for local anvil
 * forks only, ANVIL=1 uses anvil's unlocked account 0.
 */
export async function signerFor(key) {
  const provider = new ethers.JsonRpcProvider(rpcFor(key), CHAINS[key].id, { staticNetwork: true });
  provider.pollingInterval = 1000;
  if (process.env.PRIVATE_KEY) return new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  if (process.env.ANVIL === '1') return provider.getSigner(0);
  throw new Error('Set PRIVATE_KEY (testnet hot key) or ANVIL=1 (local forks only).');
}

export const at = (name, addr, runner) => new ethers.Contract(addr, C[name].abi, runner);

export async function deploy(name, args, signer) {
  const c = await new ethers.ContractFactory(C[name].abi, C[name].bytecode, signer).deploy(...args);
  await c.waitForDeployment();
  return c.getAddress();
}

export async function send(promise, label) {
  const tx = await promise;
  const rc = await tx.wait();
  if (rc.status !== 1) throw new Error(`${label} reverted (${tx.hash})`);
  if (label) log(`  ${label}: ${tx.hash.slice(0, 12)}…`);
  return rc;
}

/** Native gas a warp route needs for transferRemote. */
export async function warpGas(route, domain, recipient, amount) {
  const quotes = await route.quoteTransferRemote(domain, b32(recipient), amount);
  return quotes.filter((q) => q.token === ethers.ZeroAddress).reduce((s, q) => s + q.amount, 0n);
}

/** Order params as a plain object (round-trips into fill()). */
export const params = (p) => ({ origin: p.origin, dest: p.dest, nonce: p.nonce, user: p.user, recipient: p.recipient,
  amountIn: p.amountIn, amountOut: p.amountOut, deadline: p.deadline });
