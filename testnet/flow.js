// Bushido fee vault + x402 forwarder testnet run, step by step. Used by index.html (your burner signs)
// and by dryrun.mjs (local anvil). Each step reads/writes `st` so the page can resume after a reload.

export const CFG = {
  selfSolve: 6_250_000_000n, // 6,250 tUSDC (6 decimals)
  bridge: 25_000_000_000n, // 25,000 tUSDC
  maxFill: 500_000_000n, // 500 tUSDC
  minFlush: 1_000_000n, // 1 tUSDC = 100 x402 jobs
  mint: 10_000_000_000n, // 10,000 tUSDC to the burner
  jobFee: 10_000n, // 0.01 tUSDC
};
export const PHASES = ['ROUTING', 'SELF_SOLVE', 'BRIDGE'];

// Reads, gas estimates and receipts go through a public RPC (setRead); the wallet only signs and sends.
// Some wallet in-app browsers refuse eth_estimateGas / eth_call / receipt lookups.
let READ = null;
export function setRead(provider) { READ = provider; }
const reader = (signer) => READ || signer.provider;

async function send(ethers, signer, req, log) {
  const rp = reader(signer);
  const from = await signer.getAddress();
  const gas = await rp.estimateGas({ ...req, from });
  const fee = await rp.getFeeData();
  const tx = { ...req, from, gasLimit: (gas * 12n) / 10n + 20000n };
  if (fee.maxFeePerGas) Object.assign(tx, { maxFeePerGas: fee.maxFeePerGas * 2n, maxPriorityFeePerGas: fee.maxPriorityFeePerGas ?? 1n });
  log?.('  confirm it in your wallet…');
  const hash = await signer.sendUncheckedTransaction(tx);
  log?.(`  sent ${hash.slice(0, 14)}…, waiting for the chain`);
  let rc = null;
  for (let i = 0; i < 90 && !rc; i++) {
    rc = await rp.getTransactionReceipt(hash).catch(() => null);
    if (!rc) await new Promise((r) => setTimeout(r, 2000));
  }
  if (!rc) throw new Error(`not confirmed after 3 minutes (tx ${hash}); check your wallet's activity`);
  if (rc.status !== 1) throw new Error(`reverted on-chain (tx ${hash})`);
  return rc;
}
const callTx = (ethers, C, name, to, fn, args) => ({ to, data: new ethers.Interface(C[name].abi).encodeFunctionData(fn, args) });

export function attach(ethers, C, st, runner) {
  const at = (name, key) => (st[key] ? new ethers.Contract(st[key], C[name].abi, runner) : null);
  return { usdc: at('TestUSDC', 'usdc'), vault: at('BushidoFeeVault', 'vault'), fwd: at('X402Forwarder', 'fwd') };
}

/** Step 1: deploy tUSDC, the vault and the forwarder; whitelist the forwarder as a fee collector. */
export async function deployAll(ethers, C, signer, st, log) {
  const me = await signer.getAddress();
  const deploy = async (name, args, key) => {
    if (st[key]) return log(`${name} already at ${st[key]}`);
    log(`Deploying ${name}…`);
    const req = await new ethers.ContractFactory(C[name].abi, C[name].bytecode).getDeployTransaction(...args);
    const rc = await send(ethers, signer, { data: req.data }, log);
    st[key] = rc.contractAddress;
    log(`${name}: ${st[key]}`);
  };
  await deploy('TestUSDC', [], 'usdc');
  await deploy('BushidoFeeVault', [st.usdc, me, CFG.selfSolve, CFG.bridge, CFG.maxFill], 'vault');
  await deploy('X402Forwarder', [st.vault, me, CFG.minFlush], 'fwd');
  const { vault } = attach(ethers, C, st, reader(signer));
  if (!(await vault.isCollector(st.fwd))) {
    log('Making the forwarder a vault fee collector…');
    await send(ethers, signer, callTx(ethers, C, 'BushidoFeeVault', st.vault, 'setCollector', [st.fwd, true]), log);
  }
  st.deployed = true;
}

/** Step 2: mint test USDC to the burner. */
export async function mint(ethers, C, signer, st, log) {
  const me = await signer.getAddress();
  log(`Minting ${ethers.formatUnits(CFG.mint, 6)} tUSDC…`);
  await send(ethers, signer, callTx(ethers, C, 'TestUSDC', st.usdc, 'mint', [me, CFG.mint]), log);
}

/**
 * Step 3: an x402 "exact" payment. The burner signs an EIP-3009 TransferWithAuthorization to the forwarder
 * (the payTo), then submits it itself, playing the facilitator. `jobs` x 0.01 tUSDC in one authorization.
 */
export async function payX402(ethers, C, signer, st, jobs, log) {
  const me = await signer.getAddress();
  const rp = reader(signer);
  const { usdc } = attach(ethers, C, st, rp);
  const value = CFG.jobFee * BigInt(jobs);
  const now = BigInt((await rp.getBlock('latest')).timestamp);
  const auth = { from: me, to: st.fwd, value, validAfter: now - 60n, validBefore: now + 3600n, nonce: ethers.hexlify(ethers.randomBytes(32)) };
  const domain = { name: await usdc.name(), version: await usdc.version(), chainId: (await rp.getNetwork()).chainId, verifyingContract: st.usdc };
  const types = { TransferWithAuthorization: [
    { name: 'from', type: 'address' }, { name: 'to', type: 'address' }, { name: 'value', type: 'uint256' },
    { name: 'validAfter', type: 'uint256' }, { name: 'validBefore', type: 'uint256' }, { name: 'nonce', type: 'bytes32' },
  ] };
  log(`Sign the x402 payment: ${jobs} job(s) = ${ethers.formatUnits(value, 6)} tUSDC to the forwarder…`);
  const sig = ethers.Signature.from(await signer.signTypedData(domain, types, auth));
  if (ethers.verifyTypedData(domain, types, auth, sig) !== me) throw new Error('signature did not recover to your address');
  log('Settling it as the facilitator (transferWithAuthorization)…');
  await send(ethers, signer, callTx(ethers, C, 'TestUSDC', st.usdc, 'transferWithAuthorization',
    [auth.from, auth.to, auth.value, auth.validAfter, auth.validBefore, auth.nonce, sig.v, sig.r, sig.s]), log);
}

/** Step 4: anyone flushes the forwarder's batch into the vault (split 70/10/20). */
export async function flush(ethers, C, signer, st, log) {
  const { fwd } = attach(ethers, C, st, reader(signer));
  if (!(await fwd.flushable())) throw new Error(`forwarder holds under ${ethers.formatUnits(CFG.minFlush, 6)} tUSDC: pay more jobs first`);
  log(`Flushing ${ethers.formatUnits(await fwd.pending(), 6)} tUSDC into the vault…`);
  await send(ethers, signer, callTx(ethers, C, 'X402Forwarder', st.fwd, 'flush', []), log);
}

/** Step 5: seed inventory up to the SELF_SOLVE gate, then advance the phase (permissionless). */
export async function seedAndAdvance(ethers, C, signer, st, log) {
  const { vault } = attach(ethers, C, st, reader(signer));
  const cap = await vault.capital();
  const need = cap >= CFG.selfSolve ? 0n : CFG.selfSolve - cap;
  if (need > 0n) {
    log(`Approving ${ethers.formatUnits(need, 6)} tUSDC for the vault…`);
    await send(ethers, signer, callTx(ethers, C, 'TestUSDC', st.usdc, 'approve', [st.vault, need]), log);
    log('Seeding inventory…');
    await send(ethers, signer, callTx(ethers, C, 'BushidoFeeVault', st.vault, 'seedInventory', [need]), log);
  }
  log('Advancing phase…');
  await send(ethers, signer, callTx(ethers, C, 'BushidoFeeVault', st.vault, 'advancePhase', []), log);
}

/** Read everything the page shows. */
export async function status(ethers, C, read, st, me) {
  const { usdc, vault, fwd } = attach(ethers, C, st, read);
  if (!usdc || !vault || !fwd) return null;
  const f = (x) => ethers.formatUnits(x, 6);
  const [bal, pending, inv, res, ops, phase, x402] = await Promise.all([
    usdc.balanceOf(me), fwd.pending(), vault.inventory(), vault.reserve(), vault.ops(), vault.phase(), vault.totalCollected(0),
  ]);
  return { bal: f(bal), pending: f(pending), inventory: f(inv), reserve: f(res), ops: f(ops), phase: PHASES[Number(phase)], x402: f(x402), raw: { pending, inv, res, ops, phase: Number(phase) } };
}
