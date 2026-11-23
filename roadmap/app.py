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

# --- FEE VAULT MODEL (mirrors contracts/src/BushidoFeeVault.sol) ---
MAX_SPEND_USDC = 500.0          # guardrail cap == vault maxFillSize
X402_FEE_USDC = 0.01
SPLIT = {"inventory": 0.70, "reserve": 0.10, "ops": 0.20}
SELF_SOLVE_THRESHOLD = 6_250.0  # 500 max fill x 10 concurrent fills / 80% utilisation
BRIDGE_THRESHOLD = 25_000.0
PHASES = ["ROUTING", "SELF_SOLVE", "BRIDGE"]

if "vault" not in st.session_state:
    st.session_state.vault = {
        "inventory": 0.0, "reserve": 0.0, "ops": 0.0, "phase": 0,
        "collected": {"X402": 0.0, "EXECUTION": 0.0, "SOLVER_SPREAD": 0.0},
    }


def collect_fee(source: str, amount: float) -> None:
    v = st.session_state.vault
    inv, res = amount * SPLIT["inventory"], amount * SPLIT["reserve"]
    v["inventory"] += inv
    v["reserve"] += res
    v["ops"] += amount - inv - res
    v["collected"][source] += amount


def try_advance(logs: list, ts: str) -> None:
    v = st.session_state.vault
    thresholds = [SELF_SOLVE_THRESHOLD, BRIDGE_THRESHOLD]
    while v["phase"] < 2 and v["inventory"] >= thresholds[v["phase"]]:
        v["phase"] += 1
        logs.append(f"[{ts}] [VAULT] ⬆ Graduated to {PHASES[v['phase']]} (capital ≥ {thresholds[v['phase'] - 1]:,.0f}).")


# --- LIVE GUARDRAIL CONSOLE (SIMULATED) ---
st.markdown("---")
st.markdown("#### 🖥️ GUARDRAIL CONSOLE")

c1, c2 = st.columns([1, 2])
with c1:
    trade_amount = st.number_input(
        "Simulated trade size (USDC)", min_value=1.0, max_value=5000.0, value=250.0, step=25.0
    )
    confidence = st.slider("Strategist confidence (%)", 0, 100, 85)
    exec_fee_bps = st.slider("Execution fee (bps of notional)", 0, 50, 10)
    spread_bps = st.slider("Self-solve spread captured (bps)", 0, 30, 5)
    cross_chain = st.checkbox("Cross-chain intent (needs BRIDGE)")
    run_sim = st.button("⚔️ RUN GUARDED EXECUTION")
    b1, b2 = st.columns(2)
    if b1.button("🌱 SEED 1,000"):
        st.session_state.vault["inventory"] += 1_000.0
        try_advance(st.session_state.logs, time.strftime("%H:%M:%S"))
    if b2.button("🧹 CLEAR"):
        st.session_state.logs = st.session_state.logs[:2]

if run_sim:
    ts = time.strftime("%H:%M:%S")
    logs = st.session_state.logs
    v = st.session_state.vault
    logs.append(f"[{ts}] [X402] Paid {X402_FEE_USDC:.2f} USDC job fee → vault.")
    st.session_state.wallet_balance -= X402_FEE_USDC
    collect_fee("X402", X402_FEE_USDC)
    logs.append(f"[{ts}] [STRATEGIST] Thesis confidence: {confidence}%.")

    if confidence < 80:
        logs.append(f"[{ts}] [GUARDRAIL] VETO: confidence {confidence}% < 80% threshold.")
    elif trade_amount > MAX_SPEND_USDC:
        logs.append(
            f"[{ts}] [GUARDRAIL] VETO: {trade_amount:,.2f} USDC exceeds {MAX_SPEND_USDC:,.0f} USDC cap."
        )
        st.session_state.virtue_score = min(1000, st.session_state.virtue_score + 2)
    else:
        fee = trade_amount * exec_fee_bps / 10_000
        collect_fee("EXECUTION", fee)
        required = 2 if cross_chain else 1
        if v["phase"] >= required:
            spread = trade_amount * spread_bps / 10_000
            collect_fee("SOLVER_SPREAD", spread)
            logs.append(f"[{ts}] [SOLVER] Self-filled {trade_amount:,.2f} USDC from vault inventory (+{spread:.4f} spread).")
        else:
            logs.append(f"[{ts}] [ROUTER] {PHASES[v['phase']]}: routed to external solver.")
            logs.append(f"[{ts}] [SOLVER] Executed {trade_amount:,.2f} USDC • finality < 1s.")
        logs.append(f"[{ts}] [VAULT] Execution fee {fee:.4f} USDC retained 70/10/20.")
        st.session_state.virtue_score = min(1000, st.session_state.virtue_score + 5)
    try_advance(logs, ts)
    st.rerun()

with c2:
    log_html = "<br>".join(st.session_state.logs[-12:])
    st.markdown(f'<div class="console-box">{log_html}</div>', unsafe_allow_html=True)

# --- FEE RETENTION → SOLVER GRADUATION ---
st.markdown("---")
st.markdown("#### 🏯 FEE RETENTION → OWN SOLVER → OWN BRIDGE")
v = st.session_state.vault
m1, m2, m3, m4 = st.columns(4)
m1.metric("Phase", PHASES[v["phase"]])
m2.metric("Solver inventory", f"{v['inventory']:,.2f} USDC")
m3.metric("Loss reserve", f"{v['reserve']:,.2f} USDC")
m4.metric("Ops (withdrawable)", f"{v['ops']:,.2f} USDC")
st.progress(min(1.0, v["inventory"] / SELF_SOLVE_THRESHOLD), text=f"SELF_SOLVE gate: {v['inventory']:,.2f} / {SELF_SOLVE_THRESHOLD:,.0f}")
st.progress(min(1.0, v["inventory"] / BRIDGE_THRESHOLD), text=f"BRIDGE gate: {v['inventory']:,.2f} / {BRIDGE_THRESHOLD:,.0f}")

with st.expander("📈 Projection: how long until I can solve my own bridge?", expanded=True):
    p1, p2, p3 = st.columns(3)
    trades_per_day = p1.number_input("Executed trades / day", 1, 100_000, 200)
    avg_size = p2.number_input("Avg trade size (USDC)", 1.0, MAX_SPEND_USDC, 250.0)
    seed = p3.number_input("Founder seed (USDC)", 0.0, 1_000_000.0, 0.0, step=500.0)

    def days_to(target: float, phase_spread: bool) -> float:
        per_trade = X402_FEE_USDC + avg_size * exec_fee_bps / 10_000
        if phase_spread:
            per_trade += avg_size * spread_bps / 10_000
        daily = trades_per_day * per_trade * SPLIT["inventory"]
        return float("inf") if daily <= 0 else max(0.0, (target - seed) / daily)

    d1 = days_to(SELF_SOLVE_THRESHOLD, False)
    # after SELF_SOLVE, spread also compounds into inventory
    start2 = max(seed, SELF_SOLVE_THRESHOLD)
    d2 = d1 + days_to(BRIDGE_THRESHOLD - start2 + seed, True)
    daily_notional = trades_per_day * avg_size
    q1, q2, q3 = st.columns(3)
    q1.metric("Daily notional", f"${daily_notional:,.0f}")
    q2.metric("Days → SELF_SOLVE", "∞" if d1 == float("inf") else f"{d1:,.0f}")
    q3.metric("Days → BRIDGE", "∞" if d2 == float("inf") else f"{d2:,.0f}")
    st.caption(
        "Retained per trade = 70% × (0.01 x402 + execution bps × size [+ spread bps × size once self-solving]). "
        "x402 fees alone are negligible — execution bps on notional is what funds inventory."
    )

st.caption("Simulation only — no real funds, wallets, or onchain transactions are involved.")
