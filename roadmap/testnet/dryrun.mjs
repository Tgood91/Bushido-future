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

// Dojo Pass DNA (soulbound, gated, 0.0001 mint), steps D1-D4
const tryErr = async (fn) => { try { await fn(); return 'no revert'; } catch (e) { return F.explain(e); } };
const dnaTx = (fn, args, value = 0n) => signer.sendTransaction({ to: st.dna, data: new ethers.Interface(C.DojoPassDNA.abi).encodeFunctionData(fn, args), value });
await F.deployDna(ethers, C, signer, st, log);
let d = await F.dnaStatus(ethers, C, read, st, me);
assert(!d.paused && d.price === '0.0001' && d.supply === '0' && d.hasPass, `DNA open at 0.0001, burner holds a test Dojo Pass (paused=${d.paused} price=${d.price} pass=${d.hasPass})`);
const under = await tryErr(() => dnaTx('mint', [], 1n));
assert(under === 'WrongMintPrice(1, 100000000000000)', `wrong price refused (got ${under})`);
const id = await F.mintDna(ethers, C, signer, st, log);
d = await F.dnaStatus(ethers, C, read, st, me);
assert(id === BigInt(me) && d.supply === '1' && d.mine === '1', `tokenId = uint160(burner) (got ${id})`);
assert(d.fees === '0.0001', `contract holds the 0.0001 fee (got ${d.fees})`);
const again = await tryErr(() => dnaTx('mint', [], ethers.parseEther('0.0001')));
assert(/already minted/.test(again), `second mint refused: one per wallet (got ${again})`);
const xfer = await tryErr(() => dnaTx('transferFrom', [me, '0x000000000000000000000000000000000000dEaD', id]));
assert(xfer === 'Soulbound()', `transfer refused (got ${xfer})`);
const other = ethers.Wallet.createRandom().address;
await read.send('anvil_setBalance', [other, '0xde0b6b3a7640000']); // 1 coin, so only the gate can refuse
const gated = await tryErr(() => read.call({ from: other, to: st.dna, data: new ethers.Interface(C.DojoPassDNA.abi).encodeFunctionData('mint', []), value: ethers.parseEther('0.0001') }));
assert(gated === 'NoDojoPass()', `wallet without a Dojo Pass refused (got ${gated})`);
assert(d.uri === '', 'tokenURI empty before base URI');
await F.setDnaBaseURI(ethers, C, signer, st, 'https://example.invalid/api/dojo-pass/test/', log);
d = await F.dnaStatus(ethers, C, read, st, me);
assert(d.uri === `https://example.invalid/api/dojo-pass/test/${id}`, `tokenURI = base + uint160(holder) (got ${d.uri})`);
await F.withdrawDna(ethers, C, signer, st, log);
d = await F.dnaStatus(ethers, C, read, st, me);
assert(d.fees === '0.0', `fees withdrawn (got ${d.fees})`);
console.log('\nDry run passed.', st);
