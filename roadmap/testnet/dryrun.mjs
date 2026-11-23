// Local dry run of flow.js against anvil (start it with: anvil). Uses anvil's unlocked account 0 through the
// same JSON-RPC signer path a browser wallet uses (eth_signTypedData_v4 + eth_sendTransaction).
import { readFileSync } from 'node:fs';
import { ethers } from 'ethers';
import * as F from './flow.js';

const rpc = process.env.RPC_URL || 'http://127.0.0.1:8545';
const read = new ethers.JsonRpcProvider(rpc);
F.setRead(read);
const signer = await read.getSigner(0);
const me = await signer.getAddress();
const C = JSON.parse(readFileSync(new URL('./contracts.json', import.meta.url))).contracts;
const st = {};
const log = (m) => console.log(m);
const assert = (c, m) => { if (!c) { console.error('FAIL:', m); process.exit(1); } console.log('  ✔', m); };

await F.deployAll(ethers, C, signer, st, log);
await F.mint(ethers, C, signer, st, log);
await F.payX402(ethers, C, signer, st, 100, log);
let s = await F.status(ethers, C, read, st, me);
assert(s.pending === '1.0', `forwarder holds 1.0 tUSDC after 100 jobs (got ${s.pending})`);
await F.flush(ethers, C, signer, st, log);
s = await F.status(ethers, C, read, st, me);
assert(s.inventory === '0.7' && s.reserve === '0.1' && s.ops === '0.2', `split 0.7/0.1/0.2 (got ${s.inventory}/${s.reserve}/${s.ops})`);
assert(s.x402 === '1.0', 'vault tagged 1.0 as X402');
assert(s.pending === '0.0', 'forwarder emptied');
let replay = false;
try { await F.flush(ethers, C, signer, st, log); } catch { replay = true; }
assert(replay, 'empty flush refused');
await F.seedAndAdvance(ethers, C, signer, st, log);
s = await F.status(ethers, C, read, st, me);
assert(s.phase === 'SELF_SOLVE', `graduated to SELF_SOLVE (got ${s.phase})`);
console.log('\nDry run passed.', st);
