// Bushido testnet solver: fills cross-chain intents from vault inventory and settles them.
//   PRIVATE_KEY=0x… node solver.mjs deployments.testnet.json        # live (loops)
//   ANVIL=1 BASE_RPC=… ARB_RPC=… node solver.mjs deployments.fork.json --once
// Per order: (1) on dest: draw from the dest vault, fill() -> Hyperlane confirmation to origin
//            (2) on origin, once Filled: repay() -> deposit + 25 bps over the warp route to the dest vault
//            (3) on dest, once the repayment lands: settleFillFromBalance() -> fee split 70/10/20 in the vault
import { CHAINS, U, b32, log, sleep, loadJson, saveJson, signerFor, at, send, warpGas, params, ethers } from './lib.mjs';

const MIN_TIME_LEFT = 60; // seconds of deadline headroom required to start a fill
const LOG_CHUNK = 200; // public testnet RPCs (e.g. sepolia.base.org) cap eth_getLogs at 200 blocks

export async function makeSolver(deploymentsPath) {
  const D = loadJson(deploymentsPath);
  if (!D) throw new Error(`no deployments at ${deploymentsPath}`);
  const statePath = deploymentsPath.replace(/\.json$/, '.solver.state.json');
  const st = loadJson(statePath, { from: {}, orders: {} });
  const keys = Object.keys(D.chains);
  const net = {};
  for (const k of keys) {
    const s = await signerFor(k);
    const c = D.chains[k];
    const routeName = c.token === c.route ? 'HypERC20' : 'HypERC20Collateral';
    net[k] = { ...c, signer: s, settler: at('IntentSettler', c.settler, s), vault: at('BushidoFeeVault', c.vault, s),
      route: at(routeName, c.route, s), token: at('MockUSDC', c.token, s) };
  }
  const me = await net[keys[0]].signer.getAddress();
  const byDomain = Object.fromEntries(keys.map((k) => [net[k].domain, k]));
  const save = () => saveJson(statePath, st);

  async function scan(k) {
    const n = net[k];
    const latest = await n.signer.provider.getBlockNumber();
    let from = st.from[k] ?? latest - LOG_CHUNK;
    while (from <= latest) {
      const to = Math.min(from + LOG_CHUNK - 1, latest);
      for (const ev of await n.settler.queryFilter('Opened', from, to)) {
        const h = ev.args.orderHash;
        if (!st.orders[h]) {
          st.orders[h] = { stage: 'open', origin: k, dest: byDomain[Number(ev.args.params.dest)], params: params(ev.args.params) };
          log(`order ${h.slice(0, 10)} ${CHAINS[k].name} → ${CHAINS[st.orders[h].dest]?.name ?? '?'}: ${ethers.formatUnits(ev.args.params.amountOut, 6)} tUSDC`);
        }
      }
      from = to + 1;
    }
    st.from[k] = from;
  }

  async function advance(h, o) {
    const O = net[o.origin];
    const T = net[o.dest];
    const p = o.params;
    if (!T) return (o.stage = 'skipped');
    if (o.stage === 'open') {
      const now = (await T.signer.provider.getBlock('latest')).timestamp;
      if (now > Number(p.deadline) - MIN_TIME_LEFT) return (o.stage = 'expired');
      if (Number(await T.vault.phase()) < 2) return log(`  ${h.slice(0, 10)}: dest vault not in BRIDGE phase, waiting`);
      if ((await T.vault.inventory()) < BigInt(p.amountOut)) return log(`  ${h.slice(0, 10)}: dest vault short on inventory, waiting`);
      log(`fill ${h.slice(0, 10)} on ${CHAINS[o.dest].name}`);
      await send(T.vault.drawForFill(h, p.amountOut, true), 'vault.drawForFill');
      if ((await T.token.allowance(me, T.settler.target)) < BigInt(p.amountOut)) {
        await send(T.token.approve(T.settler.target, ethers.MaxUint256), 'approve settler');
      }
      const fee = await T.settler.quoteFill(p);
      await send(T.settler.fill(p, { value: fee }), 'settler.fill');
      o.stage = 'filled';
    }
    if (o.stage === 'filled') {
      const status = Number((await O.settler.orders(h)).status);
      if (status === 4) return (o.stage = 'lost-refunded');
      if (status === 3) o.stage = 'repaid';
      if (status === 2) {
        const gas = await warpGas(O.route, T.domain, T.vault.target, BigInt(p.amountIn));
        log(`repay ${h.slice(0, 10)} on ${CHAINS[o.origin].name}`);
        await send(O.settler.repay(h, { value: gas }), 'settler.repay');
        o.stage = 'repaid';
      }
    }
    if (o.stage === 'repaid') {
      const accounted = await T.vault.accounted();
      const bal = await T.token.balanceOf(T.vault.target);
      if (bal - accounted < BigInt(p.amountIn)) return; // repayment still in flight
      log(`settle ${h.slice(0, 10)} on ${CHAINS[o.dest].name}`);
      await send(T.vault.settleFillFromBalance(h, p.amountIn), 'vault.settleFillFromBalance');
      o.stage = 'settled';
    }
  }

  async function step() {
    for (const k of keys) await scan(k);
    for (const [h, o] of Object.entries(st.orders)) {
      if (['settled', 'expired', 'skipped', 'lost-refunded'].includes(o.stage)) continue;
      try {
        await advance(h, o);
      } catch (e) {
        log(`  ${h.slice(0, 10)} error: ${e.shortMessage || e.message}`);
      }
    }
    save();
    return st;
  }
  return { step, net, D, state: st };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const s = await makeSolver(process.argv[2] || 'deployments.testnet.json');
  const once = process.argv.includes('--once');
  log(`solver up on ${Object.keys(s.net).map((k) => CHAINS[k].name).join(' + ')}`);
  do {
    await s.step();
    if (!once) await sleep(Number(process.env.POLL_MS || 10_000));
  } while (!once);
}
export { U, b32 };
