import Foundation
import CoreGraphics
// 設計：§B.8 局部 OCR。**macOS 內建 Vision 直接辨識**，不經 sidecar——
// 日常使用（觀察 + OCR + 敘事）因此零外部服務依賴：使用者只要開 app，不必自己跑 Python。
// （sidecar 保留給 /vlm 視覺語意——那才是只有 Python/MLX 生態能做的事。）
// 省掉「存 PNG → HTTP → 解析 JSON」整條，延遲與 I/O 都更低。

/// 直接對記憶體中的影像做文字辨識（不落地存檔）。
public protocol ImageTextRecognizing: Sendable {
    func recognize(image: CGImage, languages: [String]) async throws -> [OCRSegment]
}

#if canImport(Vision)
import Vision

/// macOS Vision（VNRecognizeTextRequest）實作。`.accurate` + zh-Hant/en，語言校正開啟。
/// bbox 沿用 Vision 慣例：正規化 [x, y, w, h]、**左下原點**（與 OCRRegionMapper 一致）。
public struct VisionTextRecognizer: ImageTextRecognizing {
    public let recognitionLevel: VNRequestTextRecognitionLevel
    public let usesLanguageCorrection: Bool

    public init(recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
                usesLanguageCorrection: Bool = true) {
        self.recognitionLevel = recognitionLevel
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    public func recognize(image: CGImage, languages: [String] = ["zh-Hant", "en-US"]) async throws -> [OCRSegment] {
        let level = recognitionLevel
        let correction = usesLanguageCorrection
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let segments = observations.compactMap { obs -> OCRSegment? in
                    guard let best = obs.topCandidates(1).first else { return nil }
                    let b = obs.boundingBox   // 正規化、左下原點
                    return OCRSegment(text: best.string,
                                      confidence: Double(best.confidence),
                                      bbox: [Double(b.origin.x), Double(b.origin.y),
                                             Double(b.width), Double(b.height)])
                }
                continuation.resume(returning: segments)
            }
            request.recognitionLevel = level
            request.usesLanguageCorrection = correction
            request.recognitionLanguages = languages

            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif
