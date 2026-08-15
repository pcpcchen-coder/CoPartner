import XCTest
import CaptureEngine

/// file-scope（不在 @Sendable 閉包捕捉 self）。
private func ocrJSON(_ s: String) -> Data { Data(s.utf8) }

/// sidecar /ocr client（step 29）：請求組裝 + 回應解析 + 狀態碼映射（注入式 sender，不碰真網路）。
final class OCRClientTests: XCTestCase {
    // @unchecked：測試單執行緒寫入，安全。
    private final class RequestBox: @unchecked Sendable { var request: URLRequest? }

    private func recognizer(box: RequestBox = RequestBox(),
                            respond: @escaping @Sendable () throws -> (Data, Int)) -> SidecarOCRRecognizer {
        SidecarOCRRecognizer(baseURL: URL(string: "http://127.0.0.1:8765")!,
                             sender: { req in box.request = req; return try respond() })
    }

    func testBuildsPostToOcrWithJSONBody() async throws {
        let box = RequestBox()
        let r = recognizer(box: box) { (ocrJSON(#"{"segments":[]}"#), 200) }
        _ = try await r.recognize(imagePath: "/tmp/frame.png", languages: ["zh-Hant", "en-US"])
        let req = try XCTUnwrap(box.request)
        XCTAssertEqual(req.url?.path, "/ocr")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(req.httpBody)
        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: body)
        XCTAssertEqual(decoded["image_path"], .string("/tmp/frame.png"))   // snake_case 對得上 sidecar
    }

    func testParsesSegments() async throws {
        let r = recognizer { (ocrJSON(#"{"segments":[{"text":"你好","confidence":0.9,"bbox":[0.1,0.2,0.3,0.4]}]}"#), 200) }
        let segments = try await r.recognize(imagePath: "/tmp/f.png", languages: ["zh-Hant"])
        XCTAssertEqual(segments, [OCRSegment(text: "你好", confidence: 0.9, bbox: [0.1, 0.2, 0.3, 0.4])])
    }

    func testMissingFileMapsTo404() async {
        let r = recognizer { (ocrJSON(#"{"detail":"image not found"}"#), 404) }
        await assertThrows(.notFound) { try await r.recognize(imagePath: "/nope.png", languages: []) }
    }

    func testBackendErrorMapsToHTTP() async {
        let r = recognizer { (ocrJSON(#"{"detail":"vision failed"}"#), 500) }
        await assertThrows(.http(500)) { try await r.recognize(imagePath: "/tmp/f.png", languages: []) }
    }

    func testGarbageResponseIsBadResponse() async {
        let r = recognizer { (ocrJSON("not json"), 200) }
        await assertThrows(.badResponse) { try await r.recognize(imagePath: "/tmp/f.png", languages: []) }
    }

    private func assertThrows(_ expected: OCRClientError, _ body: () async throws -> [OCRSegment],
                              file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await body(); XCTFail("應丟 \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? OCRClientError, expected, file: file, line: line) }
    }
}

/// 極簡 JSON 值（只為驗 body 的 image_path，不引第三方）。
private enum JSONValue: Decodable, Equatable {
    case string(String), other
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s) } else { self = .other }
    }
}
