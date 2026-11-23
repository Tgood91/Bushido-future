// LOCAL FORKS ONLY: a minimal Hyperlane relayer between two anvil forks. Reads Mailbox Dispatch events on each
// chain and calls process() on the destination Mailbox. Works because fork deployments use a test ISM.
// On live testnets Hyperlane's own relayer and validators do this; don't run this there.
import { CHAINS, log, loadJson, saveJson, signerFor, at, send, ethers } from './lib.mjs';

export async function makeRelay(deploymentsPath) {
  const D = loadJson(deploymentsPath);
  if (!D?.fork) throw new Error('relay.mjs is for fork deployments only (deploy with --fork).');
  const keys = Object.keys(D.chains);
  const statePath = deploymentsPath.replace(/\.json$/, '.relay.state.json');
  const st = loadJson(statePath, { from: {} });
  const mb = {};
  for (const k of keys) {
    const s = await signerFor(k);
    mb[k] = { s, box: at('Mailbox', D.chains[k].mailbox, s), domain: D.chains[k].domain };
  }
  const byDomain = Object.fromEntries(keys.map((k) => [mb[k].domain, k]));

  async function step() {
    let relayed = 0;
    for (const k of keys) {
      const latest = await mb[k].s.provider.getBlockNumber();
      const events = [];
      for (let from = st.from[k] ?? latest - 199; from <= latest; from += 200) {
        events.push(...(await mb[k].box.queryFilter('Dispatch', from, Math.min(from + 199, latest)))); // RPCs cap getLogs at 200 blocks
      }
      for (const ev of events) {
        const destKey = byDomain[Number(ev.args.destination)];
        if (!destKey) continue;
        const id = ethers.keccak256(ev.args.message);
        if (await mb[destKey].box.delivered(id)) continue;
        await send(mb[destKey].box.process('0x', ev.args.message), `relay ${CHAINS[k].name} → ${CHAINS[destKey].name} ${id.slice(0, 10)}`);
        relayed++;
      }
      st.from[k] = latest + 1;
    }
    saveJson(statePath, st);
    return relayed;
  }
  return { step };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const r = await makeRelay(process.argv[2] || 'deployments.fork.json');
  const once = process.argv.includes('--once');
  do {
    const n = await r.step();
    if (n) log(`relayed ${n}`);
    if (!once) await new Promise((res) => setTimeout(res, 2_000));
  } while (!once);
}
