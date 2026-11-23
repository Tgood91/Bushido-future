from pathlib import Path

from streamlit.testing.v1 import AppTest

APP = str(Path(__file__).resolve().parents[1] / "app.py")


def run_sim(amount=250.0, confidence=85):
    at = AppTest.from_file(APP, default_timeout=30).run()
    at.number_input[0].set_value(amount)
    at.slider[0].set_value(confidence)
    next(b for b in at.button if "RUN GUARDED" in b.label).click()
    return at.run()


def test_app_renders_without_errors():
    at = AppTest.from_file(APP, default_timeout=30).run()
    assert not at.exception


def test_inspector_switches_agent():
    at = AppTest.from_file(APP, default_timeout=30).run()
    at.button(key="btn_Solver").click().run()
    assert at.session_state.selected_node == "Solver"


def test_trade_within_guardrails_executes():
    at = run_sim(250.0, 85)
    assert not at.exception
    assert any("[SOLVER] Executed" in line for line in at.session_state.logs)
    assert at.session_state.virtue_score == 855


def test_low_confidence_is_vetoed():
    at = run_sim(250.0, 60)
    assert any("VETO: confidence" in line for line in at.session_state.logs)
    assert not any("[SOLVER]" in line for line in at.session_state.logs)


def test_over_cap_is_vetoed():
    at = run_sim(900.0, 90)
    assert any("exceeds 500 USDC cap" in line for line in at.session_state.logs)
    assert not any("[SOLVER]" in line for line in at.session_state.logs)


def test_executed_trade_retains_fees_70_10_20():
    at = run_sim(250.0, 85)
    v = at.session_state.vault
    total = 0.01 + 250.0 * 25 / 10_000  # x402 + 25 bps execution fee
    assert abs(v["inventory"] - total * 0.70) < 1e-9
    assert abs(v["reserve"] - total * 0.10) < 1e-9
    assert abs(v["ops"] - total * 0.20) < 1e-9
    assert v["phase"] == 0


def test_seeding_graduates_and_enables_self_fill():
    at = AppTest.from_file(APP, default_timeout=30).run()
    for _ in range(7):
        next(b for b in at.button if "SEED" in b.label).click()
        at.run()
    assert at.session_state.vault["phase"] == 1  # 7,000 >= 6,250
    next(b for b in at.button if "RUN GUARDED" in b.label).click()
    at.run()
    assert any("Self-filled" in line for line in at.session_state.logs)
    assert at.session_state.vault["collected"]["SOLVER_SPREAD"] > 0


def test_cross_chain_routes_externally_before_bridge():
    at = AppTest.from_file(APP, default_timeout=30).run()
    for _ in range(7):
        next(b for b in at.button if "SEED" in b.label).click()
        at.run()
    at.checkbox[0].check()
    next(b for b in at.button if "RUN GUARDED" in b.label).click()
    at.run()
    assert not any("Self-filled" in line for line in at.session_state.logs)
    assert any("routed to external solver" in line for line in at.session_state.logs)
