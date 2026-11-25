# Bushido roadmap: working rules

Standing instructions for anyone (human or Claude) working in `roadmap/`.

## Product rules
- **Test tokens trade at real market prices.** Every test asset (tAVAX, tETH, tWETH, ...) is priced from live market
  data, never a hard-coded number: on testnets, the chain's own Chainlink `<ASSET>/USD` feed via
  `ChainlinkFeedOracle`; on mainnet forks, the Uniswap v3 TWAP cross-checked with Chainlink via
  `UniV3ChainlinkOracle`. Feeds live in `testnet/chains.json` under `chainlink` and `market`.
- **Deploy and test on testnets with the burner wallet.** The page in `testnet/` runs in the burner's wallet
  in-app browser; the wallet only signs and sends, reads go through the public RPC. Never ask for, paste or commit a
  private key. Unattended bots (the solver) read `PRIVATE_KEY` from the environment on the owner's machine.
- **Execution fee is 25 bps.** Fees go to `BushidoFeeVault` and split 70% inventory / 10% reserve / 20% ops.
- **Cross-chain inventory moves over Hyperlane warp routes**; balances across chains are reconciled offchain.
- **Faucet:** `faucet/` sends 0.05 ETH on Ethereum Sepolia and Base Sepolia per tap, origin-locked, rate-limited per
  address and IP (24 h) with a daily cap. Its key lives only in Render's environment (`FAUCET_PRIVATE_KEY`).
- **Every network the user gives or we add** gets an Add-to-wallet button on the burner page via `chains.json`.
- **Solving pair today:** Base Sepolia (home, tUSDC collateral) ↔ Arbitrum Sepolia (synthetic). Avalanche Fuji
  is set up for the vault, x402 and the live-priced tAVAX market.

## Adding a chain
`testnet/chains.json` is the single source of truth. Before adding or changing an entry, verify live:
the RPC returns the chain ID, the Hyperlane Mailbox reports `localDomain() == domain` (and has code), and each
Chainlink feed has the right `description()` and a recent `updatedAt`.

## Lessons learned (don't repeat these)
- Public testnet RPCs cap `eth_getLogs` at 200 blocks: scan in chunks of at most 200.
- After changing `package.json`, regenerate the lockfile and confirm a clean `npm ci` before pushing.
- `forge build --sizes` must skip scripts and tests (`--skip test --skip script`): deploy scripts embed bytecode and
  exceed EIP-170 without being deployed.
- Don't filter a check's output in a way that hides its exit code or error line.
- Streamlit: never set `server.enableCORS = false` on a deployed app.
- `BushidoFeeVault.absorbSurplus` stays owner/solver/rebalancer-only, so nobody can absorb a fill repayment before
  `settleFillFromBalance` uses it.
- When a check fails, make one fix attempt; if it still fails, stop and report.
- Public test keys (anvil/hardhat account 0 etc.) carry strangers' EIP-7702 delegations on public testnets
  (code `0xef0100…`). On forks, `_safeMint`/receiver callbacks then run their delegate and can revert with no data:
  `dryrun.mjs` clears it with `anvil_setCode`. A real burner with a 7702 delegate that lacks `onERC721Received`
  will hit the same revert minting DojoPassDNA.
- Public RPCs can be load-balanced, so the node answering the next call may not have seen the tx just confirmed
  (OP Sepolia "Seed + graduate" reverted live this way; forks have one node and can't reproduce it). The page's
  `send()` waits for the read RPC to reach the receipt's block and retries reverting gas estimates. Every revert is
  decoded against all contract ABIs, never shown as "unknown custom error".
- Fork runs must cover every page step (1–5, M1–M3 and D1–D4), not just a subset.
- Keep `npm audit` at 0. Pin exact versions (ethers is 6.17.0 in `solver/`, `testnet/` and the page's CDN script;
  keep all three in step). `contracts/.npmrc` sets `legacy-peer-deps=true`: Hyperlane's peer deps (ethers v5 tooling,
  elliptic) are never used to compile its Solidity and only add vulnerable packages.
