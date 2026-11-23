// Open a cross-chain intent as a user, and bootstrap helpers.
//   node open-order.mjs <deployments.json> <from-chain> <to-chain> <amount tUSDC> [recipient] [deadlineSeconds]
//   node open-order.mjs <deployments.json> bootstrap     # credit bridged inventory + graduate both vaults
import { CHAINS, U, log, loadJson, signerFor, at, send, ethers } from './lib.mjs';

export async function bootstrap(D) {
  for (const [k, c] of Object.entries(D.chains)) {
    const s = await signerFor(k);
    const v = at('BushidoFeeVault', c.vault, s);
    const got = await v.absorbSurplus.staticCall();
    if (got > 0n) await send(v.absorbSurplus(), `${CHAINS[k].name}: absorb ${ethers.formatUnits(got, 6)} bridged tUSDC`);
    for (let i = 0; i < 2 && Number(await v.phase()) < 2; i++) {
      try {
        await send(v.advancePhase(), `${CHAINS[k].name}: advancePhase`);
      } catch (e) {
        log(`${CHAINS[k].name}: can't advance yet (${e.shortMessage || e.message})`);
        break;
      }
    }
    log(`${CHAINS[k].name}: phase ${['ROUTING', 'SELF_SOLVE', 'BRIDGE'][Number(await v.phase())]}, inventory ${ethers.formatUnits(await v.inventory(), 6)}`);
  }
}

/** Get user funds on `from`: tUSDC is minted on the home chain; on the synthetic chain it must be bridged first. */
export async function openOrder(D, from, to, amount, recipient, ttl = 600) {
  const s = await signerFor(from);
  const me = await s.getAddress();
  const c = D.chains[from];
  const token = at('MockUSDC', c.token, s);
  const settler = at('IntentSettler', c.settler, s);
  const amountOut = ethers.parseUnits(String(amount), 6);
  const amountIn = amountOut + (await settler.feeFor(amountOut));
  if (c.token !== c.route && (await token.balanceOf(me)) < amountIn) await send(token.mint(me, amountIn), 'mint test tUSDC');
  await send(token.approve(c.settler, amountIn), 'approve settler');
  const now = (await s.provider.getBlock('latest')).timestamp;
  const rc = await send(settler.open(D.chains[to].domain, recipient || me, amountOut, now + ttl), 'settler.open');
  const ev = rc.logs.map((l) => { try { return settler.interface.parseLog(l); } catch { return null; } }).find((e) => e?.name === 'Opened');
  log(`opened ${ev.args.orderHash} : ${amount} tUSDC ${CHAINS[from].name} → ${CHAINS[to].name}, pays ${ethers.formatUnits(amountIn, 6)}`);
  return ev.args.orderHash;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const D = loadJson(process.argv[2]);
  if (process.argv[3] === 'bootstrap') await bootstrap(D);
  else await openOrder(D, process.argv[3], process.argv[4], process.argv[5], process.argv[6], Number(process.argv[7] || 600));
}
export { U };
