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
F.setContracts(ethers, C);
// Anvil's account 0 is a public test key; on public testnets strangers have attached EIP-7702 delegations to it
// (code 0xef0100…). On a fork that would make the run test their delegate, not our contracts: clear it.
if ((await read.getCode(me)) !== '0x') { await read.send('anvil_setCode', [me, '0x']); console.log('  (cleared a stray EIP-7702 delegation on the public test account)'); }
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

// Dojo Pass DNA (Zerion DNA clone), steps D1-D4
await F.deployDna(ethers, C, signer, st, log);
let d = await F.dnaStatus(ethers, C, read, st, me);
assert(!d.paused && d.price === '0.0001' && d.supply === '0', `DNA deployed open at 0.0001 (got paused=${d.paused} price=${d.price})`);
const id0 = await F.mintDna(ethers, C, signer, st, log);
const id1 = await F.mintDna(ethers, C, signer, st, log);
d = await F.dnaStatus(ethers, C, read, st, me);
assert(id0 === 0n && id1 === 1n && d.supply === '2' && d.mine === '2', `sequential ids 0,1 (got ${id0},${id1}, supply ${d.supply})`);
assert(d.fees === '0.0002', `contract holds 2 x 0.0001 (got ${d.fees})`);
assert(d.uri === '', 'tokenURI empty before base URI');
await F.setDnaBaseURI(ethers, C, signer, st, 'https://example.invalid/api/dojo-pass-dna/', log);
d = await F.dnaStatus(ethers, C, read, st, me);
assert(d.uri === 'https://example.invalid/api/dojo-pass-dna/1', `tokenURI = base + id (got ${d.uri})`);
let underpaid = false;
try { await signer.sendTransaction({ to: st.dna, data: new ethers.Interface(C.DojoPassDNA.abi).encodeFunctionData('mint', []), value: 1n }); } catch (e) { underpaid = F.explain(e); }
assert(/^WrongMintPrice\(1, 100000000000000\)$/.test(underpaid), `wrong mint price refused as WrongMintPrice (got ${underpaid})`);
await F.withdrawDna(ethers, C, signer, st, log);
d = await F.dnaStatus(ethers, C, read, st, me);
assert(d.fees === '0.0', `fees withdrawn (got ${d.fees})`);
console.log('\nDry run passed.', st);
