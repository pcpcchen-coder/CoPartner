"""sidecar /vlm 合約測試（注入 fake 後端，不碰真 mlx-vlm）。"""
from fastapi.testclient import TestClient

from copartner_sidecar import server
from copartner_sidecar.server import app

client = TestClient(app)


def _fake_backend(image_path, prompt, max_tokens):
    return f"desc:{prompt}:{max_tokens}"


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_vlm_returns_text(monkeypatch, tmp_path):
    img = tmp_path / "frame.png"
    img.write_bytes(b"fake")
    monkeypatch.setattr(server, "vlm_backend", _fake_backend)
    resp = client.post("/vlm", json={"image_path": str(img), "prompt": "描述畫面"})
    assert resp.status_code == 200
    assert resp.json()["text"].startswith("desc:描述畫面")


def test_vlm_missing_file_returns_404():
    resp = client.post("/vlm", json={"image_path": "/nonexistent/xyz.png", "prompt": "p"})
    assert resp.status_code == 404


def test_vlm_backend_error_returns_500(monkeypatch, tmp_path):
    img = tmp_path / "f.png"
    img.write_bytes(b"x")

    def boom(image_path, prompt, max_tokens):
        raise RuntimeError("vlm failed")

    monkeypatch.setattr(server, "vlm_backend", boom)
    resp = client.post("/vlm", json={"image_path": str(img), "prompt": "p"})
    assert resp.status_code == 500
    assert "vlm failed" in resp.json()["detail"]


def test_vlm_passes_prompt_and_max_tokens(monkeypatch, tmp_path):
    img = tmp_path / "f.png"
    img.write_bytes(b"x")
    captured = {}

    def capture(image_path, prompt, max_tokens):
        captured["prompt"] = prompt
        captured["max_tokens"] = max_tokens
        return ""

    monkeypatch.setattr(server, "vlm_backend", capture)
    client.post("/vlm", json={"image_path": str(img), "prompt": "hi", "max_tokens": 42})
    assert captured == {"prompt": "hi", "max_tokens": 42}
