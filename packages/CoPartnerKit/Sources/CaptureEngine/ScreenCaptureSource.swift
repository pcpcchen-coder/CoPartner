import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
@preconcurrency import ScreenCaptureKit
// 🔒 真機膠水：SCStream 擷取，從每幀 attachments 解出 status/dirtyRects/contentRect
// 交給 handler（→ DirtyRegionResolver）。需 Screen Recording 權限；實際擷取與
// dirtyRects 解碼、座標慣例於 step 18 真機驗（CI 只保證編譯）。設計：§B.1。

/// FrameInfoProviding 的具體值（由 SCK 每幀屬性解出）。
public struct SCKFrameInfo: FrameInfoProviding, Sendable {
    public let status: FrameStatus
    public let dirtyRects: [CGRect]
    public let contentRect: CGRect
    public init(status: FrameStatus, dirtyRects: [CGRect], contentRect: CGRect) {
        self.status = status; self.dirtyRects = dirtyRects; self.contentRect = contentRect
    }
}

public final class ScreenCaptureSource: NSObject, SCStreamOutput {
    // 非 @Sendable：handler 在 SCK sample queue（單一序列）呼叫，可捕捉非 Sendable 的 hasher。
    public typealias Handler = (SCKFrameInfo, CVPixelBuffer) -> Void

    private let handler: Handler
    private var stream: SCStream?

    public init(handler: @escaping Handler) {
        self.handler = handler
        super.init()
    }

    /// 建立並啟動擷取。filter / configuration 由呼叫端（step 14）依螢幕組出。
    public func start(filter: SCContentFilter, configuration: SCStreamConfiguration) throws {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        self.stream = stream
        stream.startCapture(completionHandler: { _ in })
    }

    public func stop() {
        stream?.stopCapture(completionHandler: { _ in })
        stream = nil
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                       of type: SCStreamOutputType) {
        guard type == .screen,
              let info = Self.frameInfo(from: sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        handler(info, pixelBuffer)
    }

    /// 從 CMSampleBuffer attachments 解出 SCK 每幀資訊。
    /// TODO(step 18): 真機確認 dirtyRects/contentRect 的字典編碼與座標慣例。
    private static func frameInfo(from sampleBuffer: CMSampleBuffer) -> SCKFrameInfo? {
        guard let raw = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let attach = raw.first else { return nil }

        let status: FrameStatus
        if let rawStatus = attach[.status] as? Int, let sck = SCFrameStatus(rawValue: rawStatus) {
            status = FrameStatus(sck)
        } else {
            status = .idle
        }

        let dirtyRects: [CGRect] = (attach[.dirtyRects] as? [[String: CGFloat]])?
            .compactMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? []

        let contentRect: CGRect = (attach[.contentRect] as? [String: CGFloat])
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero

        return SCKFrameInfo(status: status, dirtyRects: dirtyRects, contentRect: contentRect)
    }
}

private extension FrameStatus {
    init(_ status: SCFrameStatus) {
        switch status {
        case .complete:  self = .complete
        case .idle:      self = .idle
        case .blank:     self = .blank
        case .suspended: self = .suspended
        case .started:   self = .started
        case .stopped:   self = .stopped
        @unknown default: self = .idle
        }
    }
}
