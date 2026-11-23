// End-to-end testnet solving on LOCAL FORKS of Base Sepolia and Arbitrum Sepolia (real Hyperlane Mailboxes and
// gas paymasters, test ISM + local relay). Start the forks first:
//   anvil --fork-url https://sepolia.base.org --port 8545
//   anvil --fork-url https://sepolia-rollup.arbitrum.io/rpc --port 8546
//   ANVIL=1 BASE_RPC=http://127.0.0.1:8545 ARB_RPC=http://127.0.0.1:8546 node e2e-fork.mjs
import { execFileSync } from 'node:child_process';
import { rmSync } from 'node:fs';
import { log, loadJson, signerFor, at, ethers } from './lib.mjs';
import { makeRelay } from './relay.mjs';
import { makeSolver } from './solver.mjs';
import { bootstrap, openOrder } from './open-order.mjs';

const path = 'deployments.fork.json';
for (const f of [path, 'deployments.fork.solver.state.json', 'deployments.fork.relay.state.json']) rmSync(f, { force: true });
const fail = (m) => { console.error('FAIL:', m); process.exit(1); };
const ok = (c, m) => (c ? log(`  ✔ ${m}`) : fail(m));

execFileSync('node', ['deploy.mjs', path, '--fork'], { stdio: 'inherit', env: process.env });
const D = loadJson(path);
const relay = await makeRelay(path);
ok((await relay.step()) >= 1, 'inventory shipment relayed Base Sepolia → Arbitrum Sepolia');
await bootstrap(D);

const base = D.chains['base-sepolia'];
const arb = D.chains['arbitrum-sepolia'];
const sArb = await signerFor('arbitrum-sepolia');
const vaultArb = at('BushidoFeeVault', arb.vault, sArb);
ok(Number(await vaultArb.phase()) === 2, 'Arbitrum Sepolia vault graduated to BRIDGE on bridged inventory');

const recipient = ethers.Wallet.createRandom().address;
const before = { inv: await vaultArb.inventory(), res: await vaultArb.reserve(), ops: await vaultArb.ops() };
const h = await openOrder(D, 'base-sepolia', 'arbitrum-sepolia', 100, recipient);

const solver = await makeSolver(path);
for (let i = 0; i < 8 && solver.state.orders[h]?.stage !== 'settled'; i++) {
  await solver.step();
  await relay.step();
}
const stage = solver.state.orders[h]?.stage;
ok(stage === 'settled', `order settled (stage: ${stage})`);
const syn = at('MockUSDC', arb.token, sArb);
ok((await syn.balanceOf(recipient)) === 100_000_000n, 'recipient received 100 tUSDC on Arbitrum Sepolia');
ok((await vaultArb.outstanding()) === 0n, 'no open fills left');
ok((await vaultArb.inventory()) - before.inv === 175_000n, 'vault inventory +0.175 (70% of the 0.25 fee)');
ok((await vaultArb.reserve()) - before.res === 25_000n, 'reserve +0.025');
ok((await vaultArb.ops()) - before.ops === 50_000n, 'ops +0.05');
ok((await syn.balanceOf(arb.vault)) === (await vaultArb.accounted()), 'vault fully accounted');
const sBase = await signerFor('base-sepolia');
const settlerBase = at('IntentSettler', base.settler, sBase);
ok(Number((await settlerBase.orders(h)).status) === 3, 'origin order marked Repaid');
log('E2E PASSED');
