import Foundation
import Metal
// 🔒 真機膠水：TileHash.metal 的 host 端 dispatcher。CI 只把關編譯；
// 「hash 算得對不對 / 效能」於 M0 真機驗收（step 18）。
// dispatch 契約以代碼固定（而非只寫在註解），與 TileHash.metal 檔頭一一對應。

/// 對一張幀計算所有 tile 的 dHash（GPU）。比對/分級在 CPU 端 TileHashDiff。
public final class TileHashComputer {
    public enum InitError: Swift.Error {
        case metalUnavailable        // 無 Metal 裝置（如 headless VM）
        case kernelNotFound          // library 內找不到 tileDHash
    }

    /// 與 TileHash.metal 的 `TileHashParams` 完全同 layout（五個 uint32，20 bytes）。
    private struct Params {
        var tileSize: UInt32
        var cols: UInt32
        var rows: UInt32
        var frameWidth: UInt32
        var frameHeight: UInt32
    }

    public let grid: TileGrid
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    public init(grid: TileGrid) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { throw InitError.metalUnavailable }
        // SPM/Xcode 會把 target 內的 .metal 自動編成 default.metallib 放進 module bundle。
        let library = try device.makeDefaultLibrary(bundle: Bundle.module)
        guard let function = library.makeFunction(name: "tileDHash") else { throw InitError.kernelNotFound }
        self.grid = grid
        self.device = device
        self.queue = queue
        self.pipeline = try device.makeComputePipelineState(function: function)
    }

    /// 同步計算整幀的 per-tile hash（index = tileY*cols + tileX）。
    /// 骨架先用同步 API 求正確；串進擷取迴圈後改 async + 雙緩衝（TODO(step 18)）。
    public func computeHashes(for frame: MTLTexture) throws -> [UInt64] {
        let tileCount = grid.cols * grid.rows
        guard tileCount > 0 else { return [] }
        guard let buffer = device.makeBuffer(length: tileCount * MemoryLayout<UInt64>.stride,
                                             options: .storageModeShared),
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else { return [] }

        var params = Params(tileSize: UInt32(grid.tileSize),
                            cols: UInt32(grid.cols),
                            rows: UInt32(grid.rows),
                            frameWidth: UInt32(frame.width),
                            frameHeight: UInt32(frame.height))
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(frame, index: 0)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 1)
        // 契約（見 TileHash.metal 檔頭）：一 threadgroup 一 tile、一 thread 一亮度格。
        encoder.dispatchThreadgroups(MTLSize(width: grid.cols, height: grid.rows, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: 9, height: 8, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()

        let pointer = buffer.contents().bindMemory(to: UInt64.self, capacity: tileCount)
        return Array(UnsafeBufferPointer(start: pointer, count: tileCount))
    }
}
