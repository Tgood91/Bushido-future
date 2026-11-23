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
2. **Execution fee** — bps of routed notional (default modelled at 10 bps), charged by the router and forwarded via `collectFee(EXECUTION, amt)`.
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
200 trades/day × 250 USDC avg, 10 bps execution fee, 5 bps spread once self-solving:
- Retained/day in ROUTING: 200 × (0.01 + 0.25) × 0.7 ≈ **36 USDC** → ~**172 days** to `SELF_SOLVE`.
- After that spread compounds too: ≈ 54 USDC/day → ~**520 days** total to `BRIDGE`.
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

## Testnet run from the burner wallet
`testnet/` is a static page you open **inside the wallet app that holds your burner** (same pattern as the BTG
governance test). Your wallet only signs and sends; reads, gas estimates and receipts go through the public RPC.
Steps: deploy tUSDC + vault + forwarder → mint tUSDC → sign an x402 EIP-3009 payment to the forwarder and settle it
(the burner plays the facilitator) → flush → seed to 6,250 → graduate to `SELF_SOLVE`.
Base Sepolia by default; `?chain=monad-testnet` or `?chain=local` (anvil). Needs a little testnet gas in the burner.

Local dry run: `anvil` in one terminal, then `cd testnet && npm i && npm run dryrun`.

## Not built yet (next steps)
1. **x402 resource server + keeper**: the 402 middleware on the agent API pointing `payTo` at the forwarder, and a cron that calls `flush()`.
2. **Router fee hook** charging the execution fee on routed notional.
3. **Solver executor** (offchain) that draws, fills, settles, and is the only `solver` address.
4. **Bridge settlement verification** — in `BRIDGE` phase the vault currently trusts the solver to repay; loss is bounded
   only by caps, timeouts and the reserve. Next: repay against a verified origin-chain fill proof (e.g. NEAR Intents
   settlement / messaging-layer attestation) instead of solver honesty.
5. **Multi-chain inventory**: vault instances on Monad / NEAR plus a rebalancer.
6. **Audit** before any mainnet funds. This contract is unaudited.
