// Deploy + wire Bushido testnet solving on Base Sepolia (home: tUSDC collateral) and Arbitrum Sepolia (synthetic).
//   PRIVATE_KEY=0x… node deploy.mjs deployments.testnet.json            # live testnets (Hyperlane default ISM)
//   ANVIL=1 BASE_RPC=… ARB_RPC=… node deploy.mjs deployments.fork.json --fork   # local forks (test ISM)
// Optional: SOLVER=0x… (defaults to the deployer).
import { C, CHAINS, PAIR, U, b32, log, saveJson, signerFor, at, deploy, send, warpGas } from './lib.mjs';

const out = process.argv[2] || 'deployments.testnet.json';
const fork = process.argv.includes('--fork');
const [homeKey, remoteKey] = PAIR;
const TH = { selfSolve: 1_000n * U, bridge: 2_000n * U, maxFill: 500n * U }; // testnet thresholds

const sH = await signerFor(homeKey);
const sR = await signerFor(remoteKey);
const owner = await sH.getAddress();
const solver = process.env.SOLVER || owner;
const H = { key: homeKey, domain: CHAINS[homeKey].hyperlane.domain, mailbox: CHAINS[homeKey].hyperlane.mailbox };
const R = { key: remoteKey, domain: CHAINS[remoteKey].hyperlane.domain, mailbox: CHAINS[remoteKey].hyperlane.mailbox };
log(`deployer ${owner}, solver ${solver}, ${fork ? 'FORK (test ISM)' : 'LIVE (default ISM)'}`);

log(`${CHAINS[homeKey].name}: deploying`);
H.token = await deploy('MockUSDC', [], sH);
H.route = await deploy('HypERC20Collateral', [H.token, 1, 1, H.mailbox], sH);
await send(at('HypERC20Collateral', H.route, sH).initialize(ethers0(), ethers0(), owner), 'route.initialize');
H.vault = await deploy('BushidoFeeVault', [H.token, owner, TH.selfSolve, TH.bridge, TH.maxFill], sH);
H.bridge = await deploy('WarpInventoryBridge', [H.vault, H.route, owner, 100_000n * U], sH);
H.settler = await deploy('IntentSettler', [H.mailbox, H.route, owner], sH);

log(`${CHAINS[remoteKey].name}: deploying`);
R.route = await deploy('HypERC20', [6, 1, 1, R.mailbox], sR);
await send(at('HypERC20', R.route, sR).initialize(0, 'Bushido Test USDC', 'tUSDC', ethers0(), ethers0(), owner), 'route.initialize');
R.token = R.route; // the synthetic route is the token
R.vault = await deploy('BushidoFeeVault', [R.token, owner, TH.selfSolve, TH.bridge, TH.maxFill], sR);
R.bridge = await deploy('WarpInventoryBridge', [R.vault, R.route, owner, 100_000n * U], sR);
R.settler = await deploy('IntentSettler', [R.mailbox, R.route, owner], sR);

for (const [A, B, s, routeName] of [[H, R, sH, 'HypERC20Collateral'], [R, H, sR, 'HypERC20']]) {
  log(`${CHAINS[A.key].name}: wiring`);
  await send(at(routeName, A.route, s).enrollRemoteRouter(B.domain, b32(B.route)), 'route.enrollRemoteRouter');
  const v = at('BushidoFeeVault', A.vault, s);
  await send(v.setRebalancer(A.bridge), 'vault.setRebalancer');
  await send(v.setSolver(solver), 'vault.setSolver');
  await send(at('WarpInventoryBridge', A.bridge, s).setRemoteVault(B.domain, B.vault), 'bridge.setRemoteVault');
  await send(at('IntentSettler', A.settler, s).setPeer(B.domain, B.settler, B.vault), 'settler.setPeer');
  if (fork) {
    A.ism = await deploy('TestIsm', [], s);
    await send(at(routeName, A.route, s).setInterchainSecurityModule(A.ism), 'route.setISM(test)');
    await send(at('IntentSettler', A.settler, s).setInterchainSecurityModule(A.ism), 'settler.setISM(test)');
  }
}

log('Funding: mint 20,000 tUSDC, seed home vault 12,000, ship 6,000 to the remote vault');
const token = at('MockUSDC', H.token, sH);
await send(token.mint(owner, 20_000n * U), 'mint');
await send(token.approve(H.vault, 12_000n * U), 'approve');
await send(at('BushidoFeeVault', H.vault, sH).seedInventory(12_000n * U), 'vault.seedInventory');
const gas = await warpGas(at('HypERC20Collateral', H.route, sH), R.domain, R.vault, 6_000n * U);
await send(sH.sendTransaction({ to: H.bridge, value: gas * 3n }), 'fund bridge gas');
await send(at('WarpInventoryBridge', H.bridge, sH).rebalance(R.domain, 6_000n * U), 'bridge.rebalance → remote');

saveJson(out, { fork, owner, solver, thresholds: TH, chains: { [homeKey]: H, [remoteKey]: R } });
log(`saved ${out}. Next: once the 6,000 tUSDC lands on ${CHAINS[remoteKey].name}, run bootstrap (absorb + graduate).`);

function ethers0() {
  return '0x0000000000000000000000000000000000000000';
}
