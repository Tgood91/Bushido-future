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
