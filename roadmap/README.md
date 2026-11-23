# Bushido AI Roadmap (Streamlit)

Interactive architecture map of the Bushido agent stack, plus a **simulated**
guardrail console. No real funds, wallets or onchain transactions are involved.

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
docker build -t bushido-roadmap roadmap
docker run -p 8501:8501 bushido-roadmap
```

## Deploy (Render)
`render.yaml` at the repo root defines a Docker web service rooted at `roadmap/`.
In Render: **New → Blueprint**, pick this repo, and apply. Health check: `/_stcore/health`.
Only changes under `roadmap/` trigger redeploys.
