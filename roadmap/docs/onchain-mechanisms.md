# Onchain mechanisms — Goal #1: retain enough fees to solve our own DEX bridge

## The path
| Phase | What Bushido does | Unlocks when | Fills allowed |
|---|---|---|---|
| `ROUTING` | Routes every intent to external solvers (aggregators / NEAR Intents). Earns fees, retains them. | start | none |
| `SELF_SOLVE` | Fills **same-chain** intents from its own inventory, captures the solver spread. | retained capital ≥ **6,250 USDC** | ≤ 500 USDC each |
| `BRIDGE` | Fills **cross-chain** intents on the destination chain, repaid from the origin chain. | retained capital ≥ **25,000 USDC** | ≤ 500 USDC each |

Promotion is permissionless and purely threshold-gated (`advancePhase()`); the owner can only **demote**.
Any fill that isn't settled in time is written off by anyone (`markDefault`) and forces the vault back to `ROUTING`.

## Fee sources → `BushidoFeeVault` (Base, USDC)
1. **x402 job fee** — 0.01 USDC per request, paid to `X402Forwarder` (see below), which batches and forwards to the vault.
2. **Execution fee** — bps of routed notional (default 25 bps), charged by the router and forwarded via `collectFee(EXECUTION, amt)`.
3. **Solver spread** — once self-solving, any repayment above principal in `settleFill` is profit and is re-split automatically.

Every fee is split **70% inventory / 10% loss reserve / 20% ops**. The contract enforces a retention floor:
inventory ≥ 50% and reserve ≥ 5% of every fee; the owner can't redirect fees to ops above that.

## Why these thresholds
- `SELF_SOLVE` = max fill 500 × 10 concurrent fills ÷ 80% max utilisation = **6,250 USDC**.
- `BRIDGE` = cross-chain fills stay outstanding for minutes–hours until origin-side repayment, across Base / Monad / NEAR, so ~4× the self-solve float.
All tunable via `setThresholds` / `setRisk`.

## Solver risk limits (enforced onchain)
- Per-fill cap (`maxFillSize`, default 500 USDC = the guardrail spend cap).
- Utilisation cap: outstanding ≤ 80% of capital.
- Daily fill cap (default 20 × max fill).
- Timeouts: 15 min same-chain, 6 h cross-chain → default → reserve absorbs loss → back to `ROUTING`.
- Fill IDs can't be reused; the solver address can't be changed while fills are open.
- Inventory and reserve can only be withdrawn in `ROUTING` with zero outstanding.

## Honest economics (default projection in the app)
200 trades/day × 250 USDC avg, 25 bps execution fee, 5 bps spread once self-solving:
- Retained/day in ROUTING: 200 × (0.01 + 0.625) × 0.7 ≈ **89 USDC** → ~**70 days** to `SELF_SOLVE`.
- After that spread compounds too: ≈ 106 USDC/day → ~**247 days** total to `BRIDGE`.
- **x402 fees alone are negligible** (1M jobs = 7,000 USDC retained). Execution bps on notional is the real engine.
  A founder seed via `seedInventory()` shortens this linearly.

## X402Forwarder — the x402 `payTo`
Flow: agent calls a paid endpoint → server answers **HTTP 402** with payment requirements → agent signs an
EIP-3009 `TransferWithAuthorization` → facilitator settles on Base with `to = X402Forwarder` → USDC batches up →
anyone (keeper / cron) calls `flush()` once `flushable()` → vault `collectFee(X402, amount)` → 70/10/20 split.

- `payTo` in your x402 payment requirements = **the forwarder address** (scheme `exact`, network `base`, asset = Base USDC, amount `10000` = 0.01 USDC).
- `minFlush` (default 1 USDC ≈ 100 jobs) stops dust-sized flushes; gas is paid by whoever flushes.
- USDC can **only** go to the immutable vault: no owner withdrawal, and `rescue()` refuses USDC.
- If the vault revokes the forwarder's collector rights, `flush()` reverts and funds stay in the forwarder.

Deploy (simulate first, then add `--rpc-url ... --account ... --broadcast`):
```bash
cd contracts
USDC=<base usdc> DEPLOYER=<signer addr> OWNER=<multisig> forge script script/Deploy.s.sol:Deploy
```
Then `OWNER` must call `vault.acceptOwnership()`.

## Real prices: `UniV3ChainlinkOracle` + `OracleSwap` (tWETH ↔ tUSDC)
- **Price** = Uniswap v3 WETH/USDC **30-min TWAP** on Base (0.05% pool `0xd0b5…F224`), tick → price via
  `exp(tick·ln 1.0001)` (Solady `expWad`). **Cross-checked** against Chainlink ETH/USD (`0x7104…Bb70`):
  `price()` reverts if Chainlink is older than 1 h or the two differ by more than 2%.
- **OracleSwap** swaps test tokens at that price from its own inventory and sends a 25 bps execution fee to the
  vault as `EXECUTION`. This is the router fee hook: every swap compounds solver inventory.
- 0x was not used: its prices come from an offchain API (needs a key), whereas Uniswap/Chainlink are readable onchain.

On an **anvil fork of Base mainnet** the test tokens trade at the live market price:
```bash
anvil --fork-url https://mainnet.base.org          # terminal 1 (wait for it to finish loading)
cd contracts && npm ci                              # terminal 2
D=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266        # anvil's unlocked account 0
DEPLOYER=$D forge script script/DeployOracleMarket.s.sol:DeployOracleMarket \
  --rpc-url http://127.0.0.1:8545 --broadcast --unlocked --sender $D
```
Fork test (real state, no deploy): `BASE_RPC_URL=https://mainnet.base.org forge test --match-path 'test/fork/*' -vvvv`.

## DEXes: `DeployDexV2` and `DeployDexV3` (test token ↔ tUSDC at the live price)
Two unaudited, testnet-only AMMs. `DeployDexV2` deploys `DexFactory` + `DexRouter` and seeds a constant-product
pair. `DeployDexV3` deploys `DexV3Factory` + `DexV3Router`, then creates a 0.25% pool and gives `DEPLOYER` two
positions: one full range and one about ±10% around the price (`RANGE_TICKS`, default 1000). The V3 contracts are
GPL-2.0-or-later because their math is ported from Uniswap v3-core.

Pools start at the **live** price: `ORACLE` (an existing `IPriceOracle`) or `FEED` (the chain's Chainlink feed from
`testnet/chains.json`, which deploys a `ChainlinkFeedOracle` with `MAX_STALENESS`). Each script checks the seeded
pool against the oracle before finishing. They refuse non-testnet chain ids; set `ALLOW_FORK=1` for an anvil mainnet fork.

| Env | Default | |
|---|---|---|
| `DEPLOYER` | required | signer address; sign with `--account`/`--ledger` (`--unlocked` on anvil), never a raw key |
| `FEED` or `ORACLE` | one required | live price source |
| `TOKEN`, `USDC` | new `TestToken` / `MockUSDC` | existing test tokens (18 / 6 dp); the deployer's shortfall is minted |
| `SEED_TOKENS` | 100 | whole test tokens seeded; the tUSDC side is sized from the price |
| `TOKEN_NAME`, `TOKEN_SYMBOL` | `Bushido Test ETH`, `tETH` | for a new test token (e.g. `tAVAX` on Fuji) |
| `FEE` (V3) | 2500 | 100, 500, 2500, 3000 or 10000 |

```bash
cd contracts
# Base Sepolia: simulate first, then add --account <name> --broadcast
DEPLOYER=<addr> USDC=<tUSDC> FEED=0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1 \
  forge script script/DeployDexV3.s.sol:DeployDexV3 --rpc-url https://sepolia.base.org
# Arbitrum Sepolia: FEED=0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165 --rpc-url https://sepolia-rollup.arbitrum.io/rpc
# V2: same env, script/DeployDexV2.s.sol:DeployDexV2
```

## Cross-chain inventory: `WarpInventoryBridge` (Hyperlane, open source)
One vault per EVM chain. Inventory moves between them over a **Hyperlane warp route**: open source (Apache-2.0)
and permissionless, so we deploy our own routes for our own test tokens on any EVM chain.
- Home chain (Base Sepolia) holds tUSDC as collateral in a `HypERC20Collateral` route; every other chain has a
  synthetic tUSDC `HypERC20`, and that synthetic is the vault token on that chain.
- `rebalance(domain, amount)` (owner or keeper) → `vault.sendInventory(amount)` → `transferRemote` straight to the
  **destination vault**. A relayer delivers; anyone then calls `vault.absorbSurplus()` to credit it to inventory.
  No callback is involved, so the same vault works with any bridge that delivers tokens to an address.
- Vault guardrails: only the registered rebalancer can pull, only idle inventory, utilisation cap holds, and the
  source vault demotes itself if capital drops below its phase threshold. Routes that charge token fees are refused;
  the relay fee is paid in native gas from the bridge's balance.
- Cross-chain balances are reconciled **offchain** from `InventoryShipped` and `SurplusAbsorbed` events.

Tests use Hyperlane's real warp-route contracts with its `MockMailbox`, including the in-flight state
(`test/WarpInventoryBridge.t.sol`). Deploying the routes on testnets is done with the open-source Hyperlane CLI.

## EVM testnets (`testnet/chains.json`)
Verified live on 2026-11-23: each RPC returns the chain ID and each Hyperlane Mailbox reports the matching domain.

| Chain | Chain ID / domain | Hyperlane |
|---|---|---|
| Base Sepolia (home) | 84532 | yes |
| Sepolia | 11155111 | yes |
| Arbitrum Sepolia | 421614 | yes |
| OP Sepolia | 11155420 | yes |
| Unichain Sepolia | 1301 | yes |
| Linea Sepolia | 59141 | yes (no gas paymaster listed) |
| Polygon Amoy | 80002 | yes |
| BSC testnet | 97 | yes |
| Avalanche Fuji | 43113 | yes |
| Monad testnet | 10143 | **no**: registry Mailbox address has no contract; vault-only |

Scroll Sepolia is omitted because no public RPC answered. The burner-wallet page builds its network list from this file.

## Testnet solving: `IntentSettler` + solver bot (Base Sepolia ↔ Arbitrum Sepolia)
Cross-chain transfer intents, solved from vault inventory and settled over Hyperlane:
1. **Open (origin):** the user deposits `amountOut + 25 bps` and names a recipient on the destination chain.
2. **Fill (destination):** the solver draws `amountOut` from the destination vault (`drawForFill`, BRIDGE phase),
   pays the recipient through `IntentSettler.fill`, which sends a Hyperlane message to the origin settler.
3. **Confirm (origin):** `handle` accepts it only from the enrolled peer settler on that chain and only if the
   order hash matches what the user opened (recipient, amounts, deadline). A tampered fill is ignored.
4. **Repay (origin, permissionless):** the deposit goes over the warp route to the destination vault.
5. **Settle (destination):** the solver calls `vault.settleFillFromBalance`; the 25 bps is profit, split 70/10/20.

User safety: unfilled orders refund after deadline + 1 hour. `absorbSurplus` is owner/solver/rebalancer only, so
nobody can absorb a repayment before the solver settles with it.

`roadmap/solver/`: `deploy.mjs` (both chains, wiring, funding), `solver.mjs` (the bot), `open-order.mjs`
(open an order; `bootstrap` credits bridged inventory and graduates the vaults), `relay.mjs` and `e2e-fork.mjs`
(local forks only). Testnet thresholds: SELF_SOLVE 1,000 / BRIDGE 2,000 / max fill 500 tUSDC.

Fork end-to-end run (passes): forks of both testnets with their real Hyperlane Mailboxes and gas paymasters,
a test ISM and a local relay. A 100 tUSDC order Base Sepolia → Arbitrum Sepolia is filled, confirmed, repaid and
settled; the recipient gets 100 tUSDC and the Arbitrum vault keeps +0.175 inventory / +0.025 reserve / +0.05 ops.
```bash
anvil --fork-url https://sepolia.base.org --port 8545
anvil --fork-url https://sepolia-rollup.arbitrum.io/rpc --port 8546
cd roadmap/solver && npm ci
ANVIL=1 BASE_RPC=http://127.0.0.1:8545 ARB_RPC=http://127.0.0.1:8546 node e2e-fork.mjs
```
Live testnets (needs ETH on both chains; the key stays on your machine, never in the repo):
```bash
PRIVATE_KEY=0x… node deploy.mjs deployments.testnet.json   # then wait for Hyperlane to deliver the 6,000 tUSDC
PRIVATE_KEY=0x… node open-order.mjs deployments.testnet.json bootstrap
PRIVATE_KEY=0x… node solver.mjs deployments.testnet.json     # leave running
PRIVATE_KEY=0x… node open-order.mjs deployments.testnet.json base-sepolia arbitrum-sepolia 100
```

## Testnet run from the burner wallet
`testnet/` is a static page you open **inside the wallet app that holds your burner** (same pattern as the BTG
governance test). Your wallet only signs and sends; reads, gas estimates and receipts go through the public RPC.
Steps: deploy tUSDC + vault + forwarder → mint tUSDC → sign an x402 EIP-3009 payment to the forwarder and settle it
(the burner plays the facilitator) → flush → seed to 6,250 → graduate to `SELF_SOLVE`.
Base Sepolia by default; `?chain=monad-testnet` or `?chain=local` (anvil). Needs a little testnet gas in the burner.

Local dry run: `anvil` in one terminal, then `cd testnet && npm i && npm run dryrun`.

## Not built yet (next steps)
1. **x402 resource server + keeper**: the 402 middleware on the agent API pointing `payTo` at the forwarder, and a cron that calls `flush()`.
2. **Router fee hook on a real router** (OracleSwap does it for the test market; production routing still needs it).
3. **Solver executor** (offchain) that draws, fills, settles, and is the only `solver` address.
4. **Bridge settlement verification** — in `BRIDGE` phase the vault currently trusts the solver to repay; loss is bounded
   only by caps, timeouts and the reserve. Next: repay against a verified origin-chain fill proof (e.g. NEAR Intents
   settlement / messaging-layer attestation) instead of solver honesty.
5. **Deploy the warp routes**: Hyperlane CLI `warp deploy` with tUSDC collateral on Base Sepolia and synthetics on the other chains, then a vault + `WarpInventoryBridge` per chain. Monad testnet needs Hyperlane core deployed first (permissionless) or another bridge. An offchain reconciler for shipped vs absorbed inventory.
6. **Audit** before any mainnet funds. This contract is unaudited.
