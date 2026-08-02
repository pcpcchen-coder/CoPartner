//
//  TileHash.metal — per-tile dHash compute kernel（§B.2）
//
//  設計原則：GPU 只做「產 hash」這一件笨事；「兩幀 hash 差多少、算不算真的變」的
//  判斷全在 CPU 端 TileHashDiff（可單元測試）。這維持 ✅/🔒 切分：本檔案由 CI
//  編譯把關語法/型別，但「hash 算得對不對」只能在真機驗（step 18）。
//
//  演算法（classic dHash，per 128px tile）：
//    1. 把 tile 降採樣成 9×8 的亮度格（Rec.709 luma，對 sRGB 編碼值直接算——
//       感知 hash 不需要色度學上的線性正確，穩定與便宜優先）。
//    2. 每列相鄰比較：bit(row,col) = lum[row][col] > lum[row][col+1]，
//       8 列 × 8 個比較 = 64 bit。bit 序：bitIndex = row*8 + col（LSB 起）。
//       只要跨幀一致即可，CPU 端只看 Hamming distance，不解讀個別 bit。
//    3. 未變的像素 → 必然相同的 hash（決定性）；任何 distance>0 都代表真實像素變化。
//
//  Host 端 dispatch 契約（TileHashComputer.swift 必須完全遵守）：
//    - threadsPerThreadgroup   = (9, 8, 1)   ← 一個 thread 算一個亮度格 cell
//    - threadgroupsPerGrid     = (cols, rows, 1) ← 一個 threadgroup 算一個 tile
//    - texture(0)：BGRA8Unorm 幀（access::read；Metal 以 rgba 語意呈現，讀 .r/.g/.b 即可）
//                  座標系：左上原點、y 向下——與 TileGrid 一致（SCStream 幀亦同）。
//    - buffer(0)：device ulong[cols*rows]，輸出，index = tileY*cols + tileX。
//                  每 tile 恰一個 writer（thread (0,0)），不需 atomics。
//    - buffer(1)：constant TileHashParams（五個 uint32，共 20 bytes，自然對齊，
//                  Swift 端以五個 UInt32 的 struct 鏡射，layout 恰好相同）。
//
//  刻意的取捨（除錯前先讀）：
//    - 單執行緒（thread 0,0）組裝 64 bit：每 tile 只 64 次迴圈，代價可忽略，
//      換來零 atomics、零 SIMD 依賴的絕對正確性。若日後量測顯示瓶頸在此，
//      可改 simd_ballot 類 reduction——先讓它對，再讓它快。
//    - cell 取「全平均」而非抽樣：change-detection 要穩定；抽樣是之後的優化旋鈕。
//    - 邊緣 tile（不滿 128px）：cell 邊界以「實際 tile 尺寸」整數等分；
//      空 cell（tile 太窄）亮度記 0——跨幀仍決定性，比較依然有效。
//
//  已知陷阱（寫這份骨架時就防掉）：
//    - uint 減法 underflow：frameWidth - originX 在 originX ≥ frameWidth 時會繞回
//      巨大正數 → 先比較再減。
//    - divergent barrier：越界 threadgroup 的 early-return 是「整組一起回」
//      （tileID 對整組同值），不會有部分執行緒缺席 barrier 的未定義行為。
//
#include <metal_stdlib>
using namespace metal;

struct TileHashParams {
    uint tileSize;      // 例 128
    uint cols;          // TileGrid.cols
    uint rows;          // TileGrid.rows
    uint frameWidth;    // 幀像素寬
    uint frameHeight;   // 幀像素高
};

constant uint kCellCols = 9;   // 亮度格欄數（dHash 需要 9 欄 → 每列 8 個相鄰比較）
constant uint kCellRows = 8;   // 亮度格列數

static inline float rec709Luma(float4 rgba) {
    return dot(rgba.rgb, float3(0.2126f, 0.7152f, 0.0722f));
}

kernel void tileDHash(
    texture2d<float, access::read> frame   [[texture(0)]],
    device ulong                  *hashes  [[buffer(0)]],
    constant TileHashParams       &params  [[buffer(1)]],
    uint2 tileID  [[threadgroup_position_in_grid]],
    uint2 localID [[thread_position_in_threadgroup]])
{
    // 越界防護（host 照契約 dispatch 恰好 cols×rows 時不會發生）。
    // tileID 對整個 threadgroup 同值 → 整組一起 return，barrier 安全。
    if (tileID.x >= params.cols || tileID.y >= params.rows) { return; }

    // 這個 tile 的實際像素範圍（邊緣 tile 可能不滿一格；防 uint underflow）。
    const uint originX = tileID.x * params.tileSize;
    const uint originY = tileID.y * params.tileSize;
    const uint tileW = (originX < params.frameWidth)  ? min(params.tileSize, params.frameWidth  - originX) : 0;
    const uint tileH = (originY < params.frameHeight) ? min(params.tileSize, params.frameHeight - originY) : 0;

    // 每 thread 平均自己那個 cell 的亮度。cell 邊界用整數等分（含不滿的餘數分配）。
    const uint col = localID.x;   // 0..<9
    const uint row = localID.y;   // 0..<8
    const uint x0 = col * tileW / kCellCols;
    const uint x1 = (col + 1) * tileW / kCellCols;
    const uint y0 = row * tileH / kCellRows;
    const uint y1 = (row + 1) * tileH / kCellRows;

    float sum = 0.0f;
    uint count = 0;
    for (uint y = y0; y < y1; ++y) {
        for (uint x = x0; x < x1; ++x) {
            sum += rec709Luma(frame.read(uint2(originX + x, originY + y)));
            ++count;
        }
    }

    threadgroup float cellLum[kCellRows][kCellCols];
    cellLum[row][col] = (count > 0) ? (sum / float(count)) : 0.0f;

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // 單一 writer 組裝 64-bit hash（見檔頭「刻意的取捨」）。
    if (localID.x == 0 && localID.y == 0) {
        ulong hash = 0;
        for (uint r = 0; r < kCellRows; ++r) {
            for (uint c = 0; c < kCellCols - 1; ++c) {
                if (cellLum[r][c] > cellLum[r][c + 1]) {
                    hash |= ulong(1) << (r * 8 + c);
                }
            }
        }
        hashes[tileID.y * params.cols + tileID.x] = hash;
    }
}
