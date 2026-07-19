"""sidecar /ocr 合約測試（注入 fake 後端，不碰真 ocrmac / Vision）。"""
from fastapi.testclient import TestClient

from copartner_sidecar import server
from copartner_sidecar.server import app

client = TestClient(app)


def _fake_backend(image_path, languages):
    return [{"text": "hello", "confidence": 0.9, "bbox": [0.1, 0.2, 0.3, 0.4]}]


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_ocr_returns_segments(monkeypatch, tmp_path):
    img = tmp_path / "frame.png"
    img.write_bytes(b"fake")
    monkeypatch.setattr(server, "ocr_backend", _fake_backend)
    resp = client.post("/ocr", json={"image_path": str(img)})
    assert resp.status_code == 200
    segments = resp.json()["segments"]
    assert segments[0]["text"] == "hello"
    assert segments[0]["confidence"] == 0.9


def test_ocr_missing_file_returns_404():
    resp = client.post("/ocr", json={"image_path": "/nonexistent/xyz.png"})
    assert resp.status_code == 404


def test_ocr_backend_error_returns_500(monkeypatch, tmp_path):
    img = tmp_path / "f.png"
    img.write_bytes(b"x")

    def boom(image_path, languages):
        raise RuntimeError("vision failed")

    monkeypatch.setattr(server, "ocr_backend", boom)
    resp = client.post("/ocr", json={"image_path": str(img)})
    assert resp.status_code == 500
    assert "vision failed" in resp.json()["detail"]


def test_ocr_uses_default_languages(monkeypatch, tmp_path):
    img = tmp_path / "f.png"
    img.write_bytes(b"x")
    captured = {}

    def capture(image_path, languages):
        captured["languages"] = languages
        return []

    monkeypatch.setattr(server, "ocr_backend", capture)
    client.post("/ocr", json={"image_path": str(img)})
    assert captured["languages"] == ["zh-Hant", "en-US"]
