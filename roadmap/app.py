import time
import streamlit as st

# --- PAGE CONFIGURATION ---
st.set_page_config(
    page_title="BUSHIDO • AI Roadmap & Architecture Map",
    page_icon="⛩️",
    layout="wide",
)

# --- DARK & GOLD BUSHIDO THEME STYLING ---
st.markdown(
    """
    <style>
    .stApp {
        background-color: #0B0C0E;
        color: #E5D3B3;
        font-family: 'Courier New', Courier, monospace;
    }
    .bushido-header {
        text-align: center;
        border-bottom: 1px solid rgba(200, 157, 84, 0.35);
        padding-bottom: 16px;
        margin-bottom: 24px;
    }
    .bushido-title {
        font-size: 42px;
        font-weight: 800;
        letter-spacing: 0.25em;
        color: #E6B86A;
        margin: 0;
    }
    .bushido-subtitle {
        font-size: 12px;
        letter-spacing: 0.22em;
        color: #A38F6D;
        margin-top: 6px;
    }
    .bushido-card {
        background-color: #121418;
        border: 1px solid rgba(200, 157, 84, 0.45);
        border-radius: 8px;
        padding: 16px;
        margin-bottom: 14px;
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.6);
    }
    .card-label {
        font-size: 11px;
        text-transform: uppercase;
        letter-spacing: 0.12em;
        color: #E6B86A;
        font-weight: bold;
    }
    .card-value {
        font-size: 22px;
        font-weight: bold;
        color: #FFFFFF;
        margin: 6px 0;
    }
    .card-meta {
        font-size: 11px;
        color: #A38F6D;
    }
    .badge-live {
        color: #34D399;
        font-weight: bold;
    }
    .torii-hub {
        background: radial-gradient(circle, rgba(230,184,106,0.18) 0%, rgba(18,20,24,1) 75%);
        border: 2px solid #E6B86A;
        border-radius: 50%;
        width: 210px;
        height: 210px;
        margin: 10px auto;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        text-align: center;
        box-shadow: 0 0 30px rgba(230, 184, 106, 0.25);
    }
    .console-box {
        background-color: #07080A;
        border: 1px solid rgba(200, 157, 84, 0.35);
        border-radius: 6px;
        padding: 14px;
        font-size: 12px;
        line-height: 1.6;
        color: #D4C3A3;
        min-height: 160px;
    }
    div.stButton > button {
        background-color: #16191F;
        color: #E6B86A;
        border: 1px solid rgba(200, 157, 84, 0.5);
        font-family: 'Courier New', Courier, monospace;
        font-weight: bold;
        width: 100%;
    }
    div.stButton > button:hover {
        background-color: #C89D54;
        color: #0B0C0E;
        border-color: #E6B86A;
    }
    </style>
    """,
    unsafe_allow_html=True,
)

# --- ARCHITECTURE NODE DATA ---
NODES = {
    "Solver": {
        "role": "AI AGENT • SOLVER",
        "status": "IN DEVELOPMENT",
        "summary": "Constructs optimal execution calldata and routes cross-chain intents to the Guardrail Wallet.",
        "specs": ["Intent Matching", "Sub-second Calldata Assembly", "MEV-Protected Routing"],
    },
    "x402 Trader": {
        "role": "AI AGENT • X402 TRADER",
        "status": "LIVE",
        "summary": "Autonomous execution agent gated by HTTP 402 pay-per-request USDC micropayments.",
        "specs": ["0.01 USDC / Job", "Base L2 Settlement", "Automated Header Proofing"],
    },
    "Data Oracle": {
        "role": "AI AGENT • DATA ORACLE",
        "status": "LIVE",
        "summary": "Ingests real-time DEX liquidity depth, 24h volatility, and onchain price feeds.",
        "specs": ["Liquidity Scoring (0-100)", "Volatility Telemetry", "Pyth / Chainlink Sync"],
    },
    "Trend Strategist": {
        "role": "AI AGENT • TREND STRATEGIST",
        "status": "LIVE",
        "summary": "Synthesizes oracle telemetry into directional trade theses with confidence scoring.",
        "specs": ["Confidence Threshold >= 80%", "Dynamic Position Sizing", "Regime Detection"],
    },
    "Liquidity Router": {
        "role": "AI AGENT • LIQUIDITY ROUTER",
        "status": "BUILDING",
        "summary": "Selects optimal settlement rails across Base L2, Monad L1, and NEAR Intents.",
        "specs": ["Cross-Chain Slippage Check", "Base / Monad / NEAR Rails", "Sub-second Finality"],
    },
    "Guardrail Analyst": {
        "role": "AI AGENT • GUARDRAIL ANALYST",
        "status": "LIVE",
        "summary": "Enforces hard pre-execution discipline: spend caps, router allowlists, and risk vetoes.",
        "specs": ["Max Spend: 500 USDC / Tx", "Whitelisted Routers Only", "Real-Time Safety Veto"],
    },
}

# --- SESSION STATE ---
if "selected_node" not in st.session_state:
    st.session_state.selected_node = "Guardrail Analyst"
if "wallet_balance" not in st.session_state:
    st.session_state.wallet_balance = 24589.21
if "virtue_score" not in st.session_state:
    st.session_state.virtue_score = 850
if "logs" not in st.session_state:
    st.session_state.logs = [
        "[SYSTEM] ERC-8004 Identity #1219431 verified on Base (Soulbound).",
        "[GUARDRAIL] Multi-chain & sub-second finality checks active.",
    ]

# --- HEADER ---
st.markdown(
    """
    <div class="bushido-header">
        <div class="bushido-title">BUSHIDO</div>
        <div class="bushido-subtitle">
            AI ROADMAP • AI AGENTS. AUTONOMOUS PAYMENTS. VIRTUE-GUARDED TRADING.
        </div>
    </div>
    """,
    unsafe_allow_html=True,
)

# --- TOP AGENT RING (6 AGENTS) ---
st.markdown("#### ⚔️ CLICK AN AGENT NODE TO INSPECT ARCHITECTURE")
agent_cols = st.columns(6)
for idx, (agent_name, info) in enumerate(NODES.items()):
    with agent_cols[idx]:
        if st.button(f"{agent_name}\n[{info['status']}]", key=f"btn_{agent_name}"):
            st.session_state.selected_node = agent_name

# --- MAIN 3-COLUMN ARCHITECTURE MAP ---
left_col, center_col, right_col = st.columns([1.15, 1.3, 1.15])

# LEFT COLUMN: X402 MICROPAYMENTS & MULTI-CHAIN SETTLEMENT
with left_col:
    st.markdown(
        """
        <div class="bushido-card">
            <div class="card-label">⚡ X402 MICROPAYMENTS</div>
            <div class="card-value">0.01 USDC / JOB</div>
            <div class="card-meta">
                ✔ MICROPAYMENT CHANNEL<br>
                ✔ INSTANT SETTLEMENT • LOW FEE<br>
                ✔ HTTP 402 PAY-PER-REQUEST GATE
            </div>
        </div>
        <div class="bushido-card">
            <div class="card-label">🌐 MULTI-CHAIN SETTLEMENT</div>
            <div class="card-value">BASE • MONAD • NEAR</div>
            <div class="card-meta">
                ● <b>BASE L2</b> (Primary Registry & USDC)<br>
                ● <b>MONAD L1</b> (High-Throughput Execution)<br>
                ● <b>NEAR INTENTS</b> (Cross-Chain Finality)
            </div>
        </div>
        """,
        unsafe_allow_html=True,
    )

# CENTER COLUMN: TORII CORE HUB + SELECTED NODE INSPECTOR
with center_col:
    st.markdown(
        f"""
        <div class="torii-hub">
            <div style="font-size: 46px; color: #E6B86A;">⛩️</div>
            <div style="font-size: 13px; font-weight: bold; color: #E6B86A; letter-spacing: 0.15em;">
                BUSHIDO CORE
            </div>
            <div style="font-size: 11px; color: #A38F6D;">
                VIRTUE SCORE: {st.session_state.virtue_score} / 1000
            </div>
        </div>
        """,
        unsafe_allow_html=True,
    )

    active = NODES[st.session_state.selected_node]
    specs_html = "<br>".join([f"• {s}" for s in active["specs"]])
    st.markdown(
        f"""
        <div class="bushido-card">
            <div class="card-label">INSPECTING: {active['role']}</div>
            <div style="font-size: 13px; color: #FFFFFF; margin: 8px 0;">{active['summary']}</div>
            <div class="card-meta">{specs_html}</div>
        </div>
        """,
        unsafe_allow_html=True,
    )

# RIGHT COLUMN: AUTONOMOUS WALLET, GUARDRAILS, ERC-8004 IDENTITY
with right_col:
    st.markdown(
        f"""
        <div class="bushido-card">
            <div class="card-label">🔐 AUTONOMOUS WALLET</div>
            <div class="card-value">${st.session_state.wallet_balance:,.2f} USD</div>
            <div class="card-meta">
                <span class="badge-live">● 0x7A...3F21 • AUTHENTICATED</span><br>
                PROTECTED MULTI-SIG • AGENT-CONTROLLED
            </div>
        </div>
        <div class="bushido-card">
            <div class="card-label">🛡️ INSTANT GUARDRAIL ANALYST</div>
            <div class="card-meta">
                ✔ MULTI-CHAIN & MULTI-ASSET<br>
                ✔ SUB-SECOND FINALITY<br>
                ✔ MAX SPEND CAP: 500 USDC / TX
            </div>
        </div>
        <div class="bushido-card">
            <div class="card-label">🪪 ERC-8004 AGENT IDENTITY</div>
            <div class="card-value">ID #1219431</div>
            <div class="card-meta">
                SOULBOUND • REGISTERED ON BASE<br>
                REPUTATION & VIRTUE VERIFIED
            </div>
        </div>
        """,
        unsafe_allow_html=True,
    )

# --- ROADMAP TIMELINE BAR ---
st.markdown("---")
r1, r2, r3 = st.columns(3)
with r1:
    st.markdown(
        """
        <div class="bushido-card">
            <div class="card-label badge-live">▶ LIVE</div>
            <div style="font-weight:bold; color:#FFF; margin:4px 0;">X402 AGENT + GUARDRAILS</div>
            <div class="card-meta">DEPLOYED • REAL-TIME SAFETY ACTIVE</div>
        </div>
        """,
        unsafe_allow_html=True,
    )
with r2:
    st.markdown(
        """
        <div class="bushido-card">
            <div class="card-label">⚙ BUILDING</div>
            <div style="font-weight:bold; color:#FFF; margin:4px 0;">BUSHIDO SOLVER + AGENTIC WALLETS</div>
            <div class="card-meta">IN DEVELOPMENT • SOLVER ENGINE</div>
        </div>
        """,
        unsafe_allow_html=True,
    )
with r3:
    st.markdown(
        """
        <div class="bushido-card">
            <div class="card-label">📅 Q1 2027</div>
            <div style="font-weight:bold; color:#FFF; margin:4px 0;">CROSS-CHAIN INTENT SETTLEMENT</div>
            <div class="card-meta">PLANNED • MONAD + NEAR INTENTS ROLLOUT</div>
        </div>
        """,
        unsafe_allow_html=True,
    )

# --- LIVE GUARDRAIL CONSOLE (SIMULATED) ---
st.markdown("---")
st.markdown("#### 🖥️ GUARDRAIL CONSOLE")

MAX_SPEND_USDC = 500.0
X402_FEE_USDC = 0.01

c1, c2 = st.columns([1, 2])
with c1:
    trade_amount = st.number_input(
        "Simulated trade size (USDC)", min_value=1.0, max_value=5000.0, value=250.0, step=25.0
    )
    confidence = st.slider("Strategist confidence (%)", 0, 100, 85)
    run_sim = st.button("⚔️ RUN GUARDED EXECUTION")
    if st.button("🧹 CLEAR CONSOLE"):
        st.session_state.logs = st.session_state.logs[:2]

if run_sim:
    ts = time.strftime("%H:%M:%S")
    logs = st.session_state.logs
    logs.append(f"[{ts}] [X402] Paid {X402_FEE_USDC:.2f} USDC job fee (HTTP 402 cleared).")
    st.session_state.wallet_balance -= X402_FEE_USDC
    logs.append(f"[{ts}] [ORACLE] Liquidity + volatility telemetry ingested.")
    logs.append(f"[{ts}] [STRATEGIST] Thesis confidence: {confidence}%.")

    if confidence < 80:
        logs.append(f"[{ts}] [GUARDRAIL] VETO: confidence {confidence}% < 80% threshold.")
    elif trade_amount > MAX_SPEND_USDC:
        logs.append(
            f"[{ts}] [GUARDRAIL] VETO: {trade_amount:,.2f} USDC exceeds {MAX_SPEND_USDC:,.0f} USDC cap."
        )
        st.session_state.virtue_score = min(1000, st.session_state.virtue_score + 2)
    else:
        logs.append(f"[{ts}] [ROUTER] Routed via Base L2 (whitelisted router).")
        logs.append(f"[{ts}] [SOLVER] Executed {trade_amount:,.2f} USDC • finality < 1s.")
        st.session_state.virtue_score = min(1000, st.session_state.virtue_score + 5)
    st.rerun()

with c2:
    log_html = "<br>".join(st.session_state.logs[-12:])
    st.markdown(f'<div class="console-box">{log_html}</div>', unsafe_allow_html=True)

st.caption("Simulation only — no real funds, wallets, or onchain transactions are involved.")
