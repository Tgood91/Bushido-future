# Bushido AI Roadmap (Streamlit)

Interactive architecture map of the Bushido agent stack, plus a **simulated**
guardrail console. No real funds, wallets or onchain transactions are involved.

## Onchain: `BushidoFeeVault`
`contracts/` holds the fee-retention vault that funds Bushido's path from routing → own solver → own bridge.
Design and economics: [`docs/onchain-mechanisms.md`](docs/onchain-mechanisms.md). **Unaudited.**
```bash
cd contracts && forge test
```

## Run locally
```bash
cd roadmap
pip install -r requirements.txt
streamlit run app.py          # http://localhost:8501
```

## Test
```bash
pip install -r requirements-dev.txt
pytest -q
```

## Docker
```bash
docker build -t bushido-roadmap roadmap   # from the repo root
docker run -p 8501:8501 bushido-roadmap
```

## Deploy (Render)
`render.yaml` at the repo root defines a free Docker web service rooted at `roadmap/`; only changes under `roadmap/` redeploy it.
In Render: **New → Blueprint**, pick this repo, and apply. Health check: `/_stcore/health`.
