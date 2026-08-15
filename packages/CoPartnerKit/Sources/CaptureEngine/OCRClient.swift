import Foundation
// 設計：docs/design/v2_smart-capture-engine.md §B.8 + sidecar /ocr（step 27/28 合約已 pytest 驗過）。
// Swift 端呼叫 sidecar /ocr 的 client：請求組裝 + 回應解析 CI 可測（注入式 sender）；
// 真 URLSession 網路呼叫 🔒（需 sidecar 起著，step 29 真機）。

/// 一段 OCR 結果（對映 sidecar 回傳 {text, confidence, bbox}）。
public struct OCRSegment: Codable, Equatable, Sendable {
    public let text: String
    public let confidence: Double
    public let bbox: [Double]
    public init(text: String, confidence: Double, bbox: [Double]) {
        self.text = text
        self.confidence = confidence
        self.bbox = bbox
    }
}

struct OCRRequestBody: Codable, Equatable {
    let imagePath: String
    let languages: [String]
    enum CodingKeys: String, CodingKey {
        case imagePath = "image_path"
        case languages
    }
}

struct OCRResponseBody: Codable {
    let segments: [OCRSegment]
}

public enum OCRClientError: Error, Equatable {
    case notFound          // 404：sidecar 找不到圖檔
    case http(Int)         // 其他非 2xx
    case badResponse       // 無法解析
}

/// 螢幕文字辨識縫合點。CI 用假 recognizer / 假 sender；真機接 sidecar。
public protocol ScreenTextRecognizer: Sendable {
    func recognize(imagePath: String, languages: [String]) async throws -> [OCRSegment]
}

/// 呼叫本機 sidecar /ocr 的實作。sender 注入——CI 驗請求組裝/回應解析，真網路 🔒。
public struct SidecarOCRRecognizer: ScreenTextRecognizer {
    public typealias Sender = @Sendable (URLRequest) async throws -> (Data, Int)   // (body, statusCode)
    let baseURL: URL
    let sender: Sender

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8765")!,
                sender: @escaping Sender = SidecarOCRRecognizer.urlSessionSender) {
        self.baseURL = baseURL
        self.sender = sender
    }

    public static let urlSessionSender: Sender = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, code)
    }

    public func recognize(imagePath: String,
                          languages: [String] = ["zh-Hant", "en-US"]) async throws -> [OCRSegment] {
        var request = URLRequest(url: baseURL.appendingPathComponent("ocr"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OCRRequestBody(imagePath: imagePath, languages: languages))

        let (data, code) = try await sender(request)
        switch code {
        case 200:
            guard let decoded = try? JSONDecoder().decode(OCRResponseBody.self, from: data) else {
                throw OCRClientError.badResponse
            }
            return decoded.segments
        case 404:
            throw OCRClientError.notFound
        default:
            throw OCRClientError.http(code)
        }
    }
}
