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
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="CoPartner Sidecar")


class VLMRequest(BaseModel):
    image_path: str          # 焦點拼接圖（非全畫面）
    prompt: str
    max_tokens: int = 200


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/vlm")
def vlm(req: VLMRequest) -> dict:
    # TODO(M4): 載入 mlx-community/Qwen2.5-VL-7B-Instruct-4bit，generate
    # from mlx_vlm import load, generate ...
    return {"text": "", "note": "TODO: wire up mlx-vlm"}


@app.post("/ocr")
def ocr(req: VLMRequest) -> dict:
    # TODO(M2): ocrmac，regionOfInterest 對應 dirty tile
    return {"text": "", "note": "TODO: wire up ocrmac"}


def main() -> None:
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8765)


if __name__ == "__main__":
    main()
