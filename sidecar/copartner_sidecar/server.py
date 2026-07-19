"""
本地推理 sidecar：提供給 Swift 主程序透過 HTTP 呼叫。
設計：docs/design/v2_smart-capture-engine.md §D（本地模型餵圖策略）

職責：
  - /vlm   : Qwen2.5-VL（MLX）對「焦點 + dirty tiles 拼接圖」做視覺語意（僅在需要時）
  - /ocr   : Vision OCR，只跑 dirty tiles（zh-Hant + en）
  - /health
意圖分類 / L1 敘事優先用 Swift 端的 Apple FoundationModels（免費、低延遲），
本 sidecar 只承擔 FoundationModels 不適合的視覺重活。
"""
import os

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="CoPartner Sidecar")


class VLMRequest(BaseModel):
    image_path: str          # 焦點拼接圖（非全畫面）
    prompt: str
    max_tokens: int = 200


class OCRRequest(BaseModel):
    image_path: str                              # 待辨識圖（dirty tile 裁切 or 焦點圖）
    languages: list[str] = ["zh-Hant", "en-US"]  # zh-Hant + en


def _ocrmac_backend(image_path: str, languages: list[str]) -> list[dict]:
    """真 OCR：macOS Vision（經 ocrmac）。延遲 import 避免非 mac / CI 環境載入失敗。"""
    from ocrmac import ocrmac

    annotations = ocrmac.OCR(image_path, language_preference=languages).recognize()
    # ocrmac 回 (text, confidence, bbox) tuples → 正規化 dict。
    return [
        {"text": text, "confidence": conf, "bbox": list(bbox)}
        for (text, conf, bbox) in annotations
    ]


# 可注入的 OCR 後端；測試以 fake 取代，真機用 ocrmac。
ocr_backend = _ocrmac_backend


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/vlm")
def vlm(req: VLMRequest) -> dict:
    # TODO(M4): 載入 mlx-community/Qwen2.5-VL-7B-Instruct-4bit，generate
    # from mlx_vlm import load, generate ...
    return {"text": "", "note": "TODO: wire up mlx-vlm"}


@app.post("/ocr")
def ocr(req: OCRRequest) -> dict:
    if not os.path.exists(req.image_path):
        raise HTTPException(status_code=404, detail="image not found")
    try:
        segments = ocr_backend(req.image_path, req.languages)
    except Exception as exc:  # 後端失敗（模型/Vision 問題）→ 500，含訊息
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    return {"segments": segments}


def main() -> None:
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8765)


if __name__ == "__main__":
    main()
