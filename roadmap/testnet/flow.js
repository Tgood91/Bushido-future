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

// Every custom error from every page contract, so a revert reads "ThresholdNotMet(…)" instead of
// "unknown custom error" (txs are sent as raw requests, without a contract interface attached).
let ERRORS = null;
export function setContracts(ethers, C) {
  const seen = new Set();
  const frags = [];
  for (const c of Object.values(C)) {
    for (const f of c.abi) {
      if (f.type !== 'error') continue;
      const sig = `${f.name}(${(f.inputs || []).map((i) => i.type).join(',')})`;
      if (!seen.has(sig)) { seen.add(sig); frags.push(f); }
    }
  }
  ERRORS = new ethers.Interface(frags);
}
export function explain(e) {
  const data = e?.data || e?.info?.error?.data || e?.error?.data;
  if (ERRORS && typeof data === 'string' && data.length >= 10) {
    try {
      const d = ERRORS.parseError(data);
      if (d) return `${d.name}(${d.args.map(String).join(', ')})`;
    } catch {}
  }
  return e?.shortMessage || e?.reason || e?.message || String(e);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function send(ethers, signer, req, log) {
  const rp = reader(signer);
  const from = await signer.getAddress();
  // Public RPCs can sit behind several nodes: right after our previous tx, a node that hasn't seen it yet makes
  // this estimate revert (e.g. advancePhase before the seed is visible). Retry a few times before giving up.
  let gas;
  for (let i = 0; ; i++) {
    try {
      gas = await rp.estimateGas({ ...req, from });
      break;
    } catch (e) {
      if (i >= 4 || e?.code !== 'CALL_EXCEPTION') throw new Error(explain(e));
      log?.(`  RPC not caught up yet (${explain(e)}); retrying…`);
      await sleep(2500);
    }
  }
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
  // Read-your-writes: don't start the next step until the read RPC reports this tx's block.
  for (let i = 0; i < 15 && (await rp.getBlockNumber().catch(() => 0)) < rc.blockNumber; i++) await sleep(1000);
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

// ------------------------------------------------------------------------------------------------
// Live-priced test market: a test token (tAVAX on Fuji, tETH on the Sepolias) priced by the chain's own
// Chainlink <ASSET>/USD feed, i.e. real market data. Swaps pay the 25 bps execution fee into the vault.
export const MARKET_FEE_BPS = 25;

/** Step M1: deploy the test asset, the feed oracle and the market; fund liquidity. Needs step 1 (vault). */
export async function deployMarket(ethers, C, signer, st, chain, log) {
  if (!st.vault) throw new Error('deploy the vault first (step 1)');
  const m = chain.market;
  const feed = chain.chainlink[m.feed];
  const me = await signer.getAddress();
  const deploy = async (name, args, key) => {
    if (st[key]) return log(`${name} already at ${st[key]}`);
    log(`Deploying ${name}…`);
    const req = await new ethers.ContractFactory(C[name].abi, C[name].bytecode).getDeployTransaction(...args);
    st[key] = (await send(ethers, signer, { data: req.data }, log)).contractAddress;
    log(`${name}: ${st[key]}`);
  };
  await deploy('TestToken', [m.name, m.symbol, 18], 'asset');
  await deploy('ChainlinkFeedOracle', [feed, m.maxStaleness], 'oracle');
  await deploy('OracleSwap', [st.asset, st.oracle, st.vault, me, MARKET_FEE_BPS], 'market');
  const vault = new ethers.Contract(st.vault, C.BushidoFeeVault.abi, reader(signer));
  if (!(await vault.isCollector(st.market))) {
    log('Letting the market pay execution fees into the vault…');
    await send(ethers, signer, callTx(ethers, C, 'BushidoFeeVault', st.vault, 'setCollector', [st.market, true]), log);
  }
  log('Funding market liquidity and your test balance…');
  await send(ethers, signer, callTx(ethers, C, 'TestUSDC', st.usdc, 'mint', [st.market, 50_000_000_000n]), log); // 50,000 tUSDC
  await send(ethers, signer, callTx(ethers, C, 'TestToken', st.asset, 'mint', [st.market, ethers.parseEther('1000')]), log);
  await send(ethers, signer, callTx(ethers, C, 'TestToken', st.asset, 'mint', [me, ethers.parseEther('10')]), log);
  st.marketReady = true;
}

/** Step M2: sell `amount` of the test asset for tUSDC at the live feed price (0.5% slippage guard). */
export async function sellAsset(ethers, C, signer, st, amount, log) {
  const wei = ethers.parseEther(String(amount));
  const market = new ethers.Contract(st.market, C.OracleSwap.abi, reader(signer));
  const [out, fee, px] = await market.quoteSellWeth(wei);
  log(`Live price ${ethers.formatUnits(px, 6)} USDC; selling ${amount} for ${ethers.formatUnits(out, 6)} tUSDC (fee ${ethers.formatUnits(fee, 6)})`);
  await send(ethers, signer, callTx(ethers, C, 'TestToken', st.asset, 'approve', [st.market, wei]), log);
  await send(ethers, signer, callTx(ethers, C, 'OracleSwap', st.market, 'sellWeth', [wei, (out * 995n) / 1000n]), log);
}

/** Step M3: buy the test asset with `usdc` tUSDC at the live feed price. */
export async function buyAsset(ethers, C, signer, st, usdc, log) {
  const units = ethers.parseUnits(String(usdc), 6);
  const market = new ethers.Contract(st.market, C.OracleSwap.abi, reader(signer));
  const [out, fee, px] = await market.quoteBuyWeth(units);
  log(`Live price ${ethers.formatUnits(px, 6)} USDC; ${usdc} tUSDC buys ${ethers.formatEther(out)} (fee ${ethers.formatUnits(fee, 6)})`);
  await send(ethers, signer, callTx(ethers, C, 'TestUSDC', st.usdc, 'approve', [st.market, units]), log);
  await send(ethers, signer, callTx(ethers, C, 'OracleSwap', st.market, 'buyWeth', [units, (out * 995n) / 1000n]), log);
}

export async function marketStatus(ethers, C, read, st, me) {
  if (!st.marketReady) return null;
  const oracle = new ethers.Contract(st.oracle, C.ChainlinkFeedOracle.abi, read);
  const asset = new ethers.Contract(st.asset, C.TestToken.abi, read);
  const vault = new ethers.Contract(st.vault, C.BushidoFeeVault.abi, read);
  const [[px, updated], bal, fees, now] = await Promise.all([
    oracle.price(), asset.balanceOf(me), vault.totalCollected(1), read.getBlock('latest').then((b) => b.timestamp),
  ]);
  return { price: ethers.formatUnits(px, 6), ageMin: Math.max(0, Math.round((now - Number(updated)) / 60)), bal: ethers.formatEther(bal), fees: ethers.formatUnits(fees, 6) };
}

// Dojo Pass DNA: a living, soulbound Dojo Pass (Zerion DNA as the template). Mint is gated on the Dojo Pass
// registry and costs DojoPassDNA.mintPrice (0.0001 of the chain's coin at deploy); tokenId = uint160(holder), one
// per wallet. The live registry exists only on Base/Monad mainnet, so on testnets D1 deploys a TestDojoPass stand-in
// that grants the burner a pass. Traits come from the base URI (D3), recomputed off-chain. Independent of the vault.

/** Step D1: deploy the registry stand-in + DojoPassDNA (it deploys paused, like Zerion DNA) and open minting. */
export async function deployDna(ethers, C, signer, st, log) {
  const me = await signer.getAddress();
  const deploy = async (name, args, key) => {
    if (st[key]) return log(`${name} already at ${st[key]}`);
    log(`Deploying ${name}…`);
    const req = await new ethers.ContractFactory(C[name].abi, C[name].bytecode).getDeployTransaction(...args);
    st[key] = (await send(ethers, signer, { data: req.data }, log)).contractAddress;
    log(`${name}: ${st[key]}`);
  };
  await deploy('TestDojoPass', [me, 0n, me], 'dnaPass'); // testnet registry; you hold the first pass
  await deploy('DojoPassDNA', [st.dnaPass], 'dna');
  const dna = new ethers.Contract(st.dna, C.DojoPassDNA.abi, reader(signer));
  if (await dna.paused()) {
    log('Opening minting (unpause)…');
    await send(ethers, signer, callTx(ethers, C, 'DojoPassDNA', st.dna, 'unpause', []), log);
  }
  st.dnaOpen = true;
}

/** Step D2: mint my pass (tokenId = my address as a number), paying exactly the current mint price. */
export async function mintDna(ethers, C, signer, st, log) {
  const dna = new ethers.Contract(st.dna, C.DojoPassDNA.abi, reader(signer));
  const price = await dna.mintPrice();
  log(`Minting your Dojo Pass DNA for ${ethers.formatEther(price)}…`);
  await send(ethers, signer, { ...callTx(ethers, C, 'DojoPassDNA', st.dna, 'mint', []), value: price }, log);
  const id = await dna.tokenIdOf(await signer.getAddress());
  log(`Minted Dojo Pass DNA #${id}`);
  return id;
}

/** Step D3: point every tokenURI at the trait service (tokenURI = baseURI + tokenId). */
export async function setDnaBaseURI(ethers, C, signer, st, uri, log) {
  log(`Setting base URI to ${uri || '(empty)'}…`);
  await send(ethers, signer, callTx(ethers, C, 'DojoPassDNA', st.dna, 'setBaseURI', [uri]), log);
}

/** Step D4: send collected mint fees to the owner (me). */
export async function withdrawDna(ethers, C, signer, st, log) {
  log('Withdrawing mint fees to the owner…');
  await send(ethers, signer, callTx(ethers, C, 'DojoPassDNA', st.dna, 'withdraw', []), log);
}

export async function dnaStatus(ethers, C, read, st, me) {
  if (!st.dna) return null;
  const dna = new ethers.Contract(st.dna, C.DojoPassDNA.abi, read);
  const reg = new ethers.Contract(await dna.dojoPass(), C.TestDojoPass.abi, read);
  const [supply, price, mine, fees, paused, owner, hasPass, id] = await Promise.all([
    dna.totalSupply(), dna.mintPrice(), dna.balanceOf(me), read.getBalance(st.dna), dna.paused(), dna.owner(),
    reg.hasDojoPass(me), dna.tokenIdOf(me),
  ]);
  const uri = mine > 0n ? await dna.tokenURI(id).catch(() => '') : '';
  return { supply: supply.toString(), price: ethers.formatEther(price), mine: mine.toString(), fees: ethers.formatEther(fees),
    paused, owner, hasPass, id: id.toString(), uri, raw: { price, fees, mine } };
}
