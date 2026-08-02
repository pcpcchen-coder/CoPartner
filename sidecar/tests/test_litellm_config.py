"""infra/litellm/config.yaml 不變式測試（威脅模型 T10 / I10）：CI 擋掉靜默設定漂移。"""
import pathlib

import yaml

CONFIG = pathlib.Path(__file__).resolve().parents[2] / "infra" / "litellm" / "config.yaml"


def _load() -> dict:
    return yaml.safe_load(CONFIG.read_text())


def test_presidio_pre_call_present():
    cfg = _load()
    presidio = [g for g in cfg["guardrails"] if "presidio" in g["guardrail_name"]]
    assert presidio, "須有 presidio guardrail"
    assert presidio[0]["litellm_params"]["mode"] == "pre_call"


def test_daily_budget_set():
    assert _load()["litellm_settings"]["max_budget"] == 5


def test_pipl_local_only_route_exists():
    pipl = _load()["pipl_routing"]
    assert pipl["never_egress"] is True
    assert "local" in pipl["sensitive_model"] or "qwen" in pipl["sensitive_model"]


def test_model_list_has_local_backend():
    names = [m["model_name"] for m in _load()["model_list"]]
    assert any("qwen" in n or "local" in n for n in names)


def test_fallback_chain_no_cloud_for_local_only():
    cfg = _load()
    cloud = {"claude-sonnet", "claude-opus"}
    for entry in cfg["router_settings"]["fallbacks"]:
        for src, targets in entry.items():
            if "qwen" in src or "local" in src:
                assert not (set(targets) & cloud), f"local-only {src} 不得 fallback 回雲端"
