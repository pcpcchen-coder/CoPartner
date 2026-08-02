import XCTest
import CoPartnerCore
import MemoryStore

/// MemoryStore 檢索（§C / v2.1 §3）：注入 3 維假 embedder（依 app 關鍵字給正交向量），驗語意排序。
final class MemoryStoreTests: XCTestCase {
    private struct FakeEmbedder: TextEmbedder {
        let dimension = 3
        func embed(_ text: String) -> [Float] {
            if text.contains("Xcode") { return [1, 0, 0] }
            if text.contains("Safari") { return [0, 1, 0] }
            return [0, 0, 1]
        }
    }

    private func step(app: String, goal: String) -> ActionStep {
        ActionStep(startedAt: Date(timeIntervalSince1970: 1_000_000), app: app, category: "x",
                   whatHappened: "y", inferredGoal: goal, confidence: 0.5, artifacts: [], openLoop: false)
    }

    private func makeStore() -> MemoryStore {
        MemoryStore(index: InMemoryVectorIndex(dimension: 3), embedder: FakeEmbedder())
    }

    func testInsertThenSearchFindsStep() async {
        let store = makeStore()
        let xcode = step(app: "Xcode", goal: "修 build")
        await store.insert(step: xcode)
        await store.insert(step: step(app: "Safari", goal: "查文件"))
        let hits = await store.search(query: "Xcode 除錯", k: 1)
        XCTAssertEqual(hits.first?.id, xcode.id)
    }

    func testSearchRanksBySimilarity() async {
        let store = makeStore()
        let xcode = step(app: "Xcode", goal: "a")
        let safari = step(app: "Safari", goal: "b")
        await store.insert(step: xcode)
        await store.insert(step: safari)
        let hits = await store.search(query: "Safari 分頁", k: 2)
        XCTAssertEqual(hits.first?.id, safari.id)   // Safari 最近
    }

    func testSearchKLimit() async {
        let store = makeStore()
        for _ in 0..<5 { await store.insert(step: step(app: "Xcode", goal: "g")) }
        let hits = await store.search(query: "Xcode", k: 2)
        XCTAssertEqual(hits.count, 2)
    }

    func testEmptyStoreReturnsEmpty() async {
        let store = makeStore()
        let hits = await store.search(query: "anything", k: 5)
        XCTAssertTrue(hits.isEmpty)
    }
}
