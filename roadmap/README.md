# Bushido roadmap

Bushido's path from routing trades, to solving them with its own capital, to running its own cross-chain bridge:
the fee vault and contracts, a testnet solver, a burner-wallet test page, and a Streamlit map of the architecture.
**Testnet and simulation only. The contracts are unaudited.** Working rules: [`CLAUDE.md`](CLAUDE.md).
Mechanism design and economics: [`docs/onchain-mechanisms.md`](docs/onchain-mechanisms.md).

| Folder | What's in it |
|---|---|
| `contracts/` | Foundry project: `BushidoFeeVault`, `X402Forwarder`, price oracles, `OracleSwap`, `WarpInventoryBridge`, `IntentSettler` |
| `testnet/` | Burner-wallet page, the chain registry `chains.json`, page contract artifacts |
| `solver/` | Solver bot, deploy and order scripts, fork relay, `price-check.mjs` |
| `app.py` | Streamlit roadmap app (simulated, no real funds) |
| `docs/` | Design and economics |

## Live prices: testnet tied to mainnet

Every test token trades at the real market price. There are no hard-coded or manually updated prices anywhere.

```
mainnet market ──► Chainlink oracle network ──► testnet Chainlink feed ──► ChainlinkFeedOracle ──► OracleSwap
 (real trading)      (same price data)           (on the test chain)        (reads it per trade)    (tAVAX/tETH ⇄ tUSDC)
```

| Test token | Chain | Prices from (testnet feed) | Tied to (mainnet reference feed) |
|---|---|---|---|
| tAVAX | Avalanche Fuji | Chainlink AVAX/USD `0x5498…06aD` | Chainlink AVAX/USD on Avalanche C-Chain `0x0A77…6156` |
| tETH | Base Sepolia | Chainlink ETH/USD `0x4aDC…7cb1` | Chainlink ETH/USD on Base `0x7104…Bb70` |
| tETH | Arbitrum Sepolia | Chainlink ETH/USD `0xd30e…5165` | Chainlink ETH/USD on Base `0x7104…Bb70` |
| tUSDC | all | priced at 1 USD (the quote currency) | — |

**How prices update.** Nothing needs updating by hand. Chainlink pushes a new testnet answer whenever the real
market moves past the feed's deviation threshold or its heartbeat expires (10 minutes for Fuji AVAX/USD, 20 minutes
for Base Sepolia ETH/USD, 2 minutes for Arbitrum Sepolia ETH/USD). `ChainlinkFeedOracle` reads the latest answer on
every quote and swap, so the next trade always uses the newest price.

**Stale-price guard.** If a testnet feed hasn't updated within the market's `maxStaleness` (1 hour), the oracle
reverts and the market stops quoting. A frozen or broken feed can't trade at an old price.

**Checking the tie.** `price-check.mjs` reads each testnet feed next to its mainnet reference and reports the gap:

```bash
cd roadmap/solver && npm ci
node price-check.mjs                  # exits 1 if any gap > 1% or a testnet feed is stale
MAX_GAP_BPS=50 node price-check.mjs   # tighter: 0.5%
```

```
OK   tETH   Base Sepolia      $1,725.9682 (1 min)    vs Base mainnet $1,725.9589 (1 min)    gap 0.00%
OK   tETH   Arbitrum Sepolia  $1,726.197  (0 min)    vs Base mainnet $1,725.9589 (1 min)    gap 0.01%
OK   tAVAX  Avalanche Fuji    $6.8052     (9 min)    vs Avalanche C-Chain mainnet $6.8029     (1 min)    gap 0.03%
```

CI runs this check, so a testnet feed that drifts from mainnet or goes stale fails the build.

**On mainnet forks** (anvil `--fork-url https://mainnet.base.org`), `UniV3ChainlinkOracle` prices tWETH from the
live Uniswap v3 WETH/USDC 30-minute TWAP on Base. It cross-checks that against Chainlink and reverts if the two
differ by more than 2%.

**Adding or changing a market.** Edit `testnet/chains.json`, the single source of truth:
1. Under the chain, add the feed to `chainlink` and a `market` with `name`, `symbol`, `feed` and `maxStaleness`.
2. Add `market.mainnetReference`: the mainnet chain, its public RPC, and the same asset's Chainlink feed there.
3. Verify both feeds live: the right `description()` and a recent `updatedAt` (see `CLAUDE.md`).
4. Run `node price-check.mjs`. The burner page picks the market up automatically.

## Burner-wallet test page (`testnet/`)

Open `testnet/index.html` in the browser inside the wallet app that holds your burner. The wallet only signs and
sends; reads, gas estimates and receipts go through the chain's public RPC. Choose a network with `?chain=`:
`base-sepolia` (default), `arbitrum-sepolia`, `avalanche-fuji`, and the other chains in `chains.json`.
`?chain=local` uses a local anvil chain.

- **Steps 1–5:** deploy tUSDC, the vault and the x402 forwarder; mint; pay x402 jobs; flush into the vault; seed and
  graduate.
- **M1–M3 (chains with a market):** deploy the test token, the live-price oracle and the market; then sell and buy
  at the live price. Every swap pays the 25 bps execution fee into the vault.

- **Networks:** every testnet in `chains.json` gets its own **➕ Add** button (chain ID, verified RPC, gas token,
  explorer), plus **Add all networks**. The top button adds the selected network and switches the wallet to it.
- **Faucet:** **💧 Get 0.05 ETH on Sepolia + Base Sepolia** sends free gas to the connected burner. A brand-new empty
  burner can connect and tap it.

To test the page against a fork, add `?rpc=http://127.0.0.1:8545` so reads hit the fork too, and
`?faucet=http://127.0.0.1:8790` for a local faucet.

### Live testnet coverage

Every market chain below was run end to end with the burner wallet on the live testnet. The run covered Add
network, Connect, steps 1–5 (vault, mint, x402, flush, seed + graduate) and M1–M3 (deploy the live-priced market,
sell, buy). Each chain was also run first on a fork.

| Chain | Test token | Price feed (Chainlink) | Live burner test |
|---|---|---|---|
| Avalanche Fuji | tAVAX | AVAX/USD | ✅ |
| Ethereum Sepolia | tETH | ETH/USD | ✅ |
| Base Sepolia | tETH | ETH/USD | ✅ |
| Arbitrum Sepolia | tETH | ETH/USD | ✅ |
| OP Sepolia | tETH | ETH/USD | ✅ (after the RPC-lag fix) |
| Unichain Sepolia | tETH | ETH/USD (24 h heartbeat) | ✅ |
| Polygon Amoy | tETH | ETH/USD | ✅ |
| BSC testnet | tBNB | BNB/USD | ✅ |
| Monad testnet | tETH | ETH/USD (24 h heartbeat) | ✅ |
| Linea Sepolia | — | none (feed stale and 5% off mainnet) | vault and x402 only; not yet run (no gas) |

## Faucet (`faucet/`)

A small Node service (`solving-faucet` on Render) that sends **0.05 ETH on Ethereum Sepolia and on Base Sepolia**
to the connected wallet in one tap.
- **Who it serves:** only `/drip` calls from the burner page's origin (`ALLOWED_ORIGIN`).
- **Limits:**
  - one drip per address per chain and one per client IP per chain every 24 h;
  - a daily cap per chain (`DAILY_CAP_ETH`, default 2 ETH = 40 drips);
  - wallets already holding too much are refused: by default 0.5 ETH (`MAX_RECIPIENT_ETH`), with a per-chain
    override (`MAX_RECIPIENT_ETH_SEPOLIA`, `MAX_RECIPIENT_ETH_BASE_SEPOLIA`; `off` skips the check). Live:
    5 ETH on Sepolia, off on Base Sepolia.
- **Restarts:** limits are kept in memory, so a restart clears them. The daily cap and the faucet balance still
  bound what can be taken.
- **Key:** set `FAUCET_PRIVATE_KEY` in the Render dashboard (Environment), never in the repo. Then fund that
  wallet's address with ETH on both chains; `/status` shows the address and its balances.

```bash
cd roadmap/faucet && npm ci
npm test          # two local anvil chains with a random wallet: drips, limits, cap, concurrency
```

## Testnet solving (`solver/`)

Cross-chain transfer intents between Base Sepolia and Arbitrum Sepolia, solved from vault inventory and settled
over Hyperlane. The user pays `amountOut + 25 bps`; that 25 bps becomes vault profit.

```bash
cd roadmap/solver && npm ci
# Local forks of both testnets (real Hyperlane Mailboxes and gas paymasters, local relay):
anvil --fork-url https://sepolia.base.org --port 8545
anvil --fork-url https://sepolia-rollup.arbitrum.io/rpc --port 8546
ANVIL=1 BASE_RPC=http://127.0.0.1:8545 ARB_RPC=http://127.0.0.1:8546 node e2e-fork.mjs

# Live testnets: the bot needs its own key with ETH on both chains, in your environment only
PRIVATE_KEY=0x… node deploy.mjs deployments.testnet.json
PRIVATE_KEY=0x… node open-order.mjs deployments.testnet.json bootstrap
PRIVATE_KEY=0x… node solver.mjs deployments.testnet.json
PRIVATE_KEY=0x… node open-order.mjs deployments.testnet.json base-sepolia arbitrum-sepolia 100
```

Never paste a private key into chat or commit it.

## Contracts (`contracts/`)

```bash
cd roadmap/contracts && npm ci
forge test                                    # unit tests
BASE_RPC_URL=https://mainnet.base.org FUJI_RPC_URL=https://api.avax-test.network/ext/bc/C/rpc \
  forge test --match-path 'test/fork/*' -vv   # live-price fork tests
forge build --sizes --skip test --skip script # EIP-170 size check
```

## Roadmap app (`app.py`)

A simulated architecture map and fee projection. No real funds or onchain transactions.

```bash
cd roadmap
pip install -r requirements.txt
streamlit run app.py              # http://localhost:8501
pip install -r requirements-dev.txt && pytest -q
docker build -t bushido-roadmap roadmap && docker run -p 8501:8501 bushido-roadmap   # from the repo root
```

To deploy on Render: `render.yaml` at the repo root defines a free Docker web service rooted at `roadmap/`. In Render
choose **New → Blueprint**, pick this repo, and apply. The health check is `/_stcore/health`. Only changes under
`roadmap/` redeploy it.

## CI

`.github/workflows/roadmap.yml` runs on changes under `roadmap/`:
- **app tests**
- **contracts:** unit tests, size check, and the live-price fork tests on Base mainnet and Fuji
- **solver:** `npm ci`, script syntax, and the testnet-to-mainnet price check
- **faucet:** `npm ci`, audit, and the local two-chain faucet test
- **Docker build**
