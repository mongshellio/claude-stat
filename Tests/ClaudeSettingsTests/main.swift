import Foundation

// Regression tests for the ~/.claude/settings.json read/write path.
//
// These cover one invariant above all: **the app must never destroy settings it
// cannot see.** That file is the user's real Claude Code config, shared with the
// CLI, and a bad save costs them permission rules and plugin config this app
// doesn't even know exist. Both holes fixed in review — a failed read being
// downgraded to "empty file", and a key of an unexpected type being deleted as
// if the user had cleared it — are pinned here.
//
// Run with `./scripts/test.sh`, which compiles this against the real sources.
// There is no SwiftPM test target: `swift test` needs XCTest or swift-testing
// and neither ships with the Command Line Tools this project builds against.
//
// Every case runs against a throwaway file via MONGSHELL_CLAUDE_SETTINGS.
// Nothing here touches the real ~/.claude.

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "  ok  " : " FAIL ") \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
    if !ok { failures.append(label) }
}

func checkThrows(_ label: String, _ body: () throws -> Void) {
    do {
        try body()
        check(label, false, "오류가 발생해야 하는데 성공했습니다")
    } catch {
        check(label, true)
    }
}

/// Stands in for a lived-in settings file: our five keys plus a pile of keys
/// the app has no idea about.
let fixture = """
{
  "model": "opus",
  "permissions": {
    "defaultMode": "auto",
    "allow": ["Bash(git status)", "Bash(npm test *)", "Read(~/.zshrc)"],
    "additionalDirectories": ["/tmp/a", "/tmp/b"]
  },
  "enabledPlugins": { "some-plugin@vendor": false },
  "extraKnownMarketplaces": { "vendor": { "source": { "repo": "vendor/plugins" } } },
  "skipWorkflowUsageWarning": true
}
"""

let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("claude-settings-tests-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

var caseIndex = 0

/// Fresh temp file per case, pointed at by MONGSHELL_CLAUDE_SETTINGS. `seeded`
/// controls whether the fixture is written first.
func newCase(seeded: Bool = true) -> URL {
    caseIndex += 1
    let dir = root.appendingPathComponent("case-\(caseIndex)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("settings.json")
    if seeded { try! fixture.write(to: file, atomically: true, encoding: .utf8) }
    setenv("MONGSHELL_CLAUDE_SETTINGS", file.path, 1)
    return file
}

func allowCount(_ dict: [String: Any]) -> Int? {
    ((dict["permissions"] as? [String: Any])?["allow"] as? [Any])?.count
}

func permissions(_ dict: [String: Any]) -> [String: Any]? {
    dict["permissions"] as? [String: Any]
}

// MARK: - 읽기 실패는 절대 "빈 파일"이 되어선 안 된다

print("\n읽기 실패 처리")

_ = newCase(seeded: false)
check("파일이 아예 없으면 최초 실행으로 간주", (try? ClaudeSettingsStore.load())?.isEmpty == true)

do {
    let file = newCase()
    try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
    checkThrows("읽을 수 없는 파일은 오류") { _ = try ClaudeSettingsStore.load() }
    checkThrows("읽을 수 없는 파일에는 쓰지 않는다") {
        _ = try ClaudeSettingsStore.mutate { ClaudeSettingsModel.apply(ClaudeSettings(), to: &$0) }
    }
    try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    check("거부된 쓰기 이후에도 내용 온전", allowCount(try! ClaudeSettingsStore.load()) == 3)
}

do {
    let file = newCase(seeded: false)
    try! Data().write(to: file)
    checkThrows("0바이트 파일은 오류 (중단된 쓰기의 잔해)") { _ = try ClaudeSettingsStore.load() }
}

do {
    let file = newCase(seeded: false)
    try! "{ not json".write(to: file, atomically: true, encoding: .utf8)
    checkThrows("깨진 JSON 은 오류") { _ = try ClaudeSettingsStore.load() }
    checkThrows("깨진 JSON 에는 쓰지 않는다") { _ = try ClaudeSettingsStore.mutate { _ in } }
    check("깨진 파일은 손대지 않는다",
          (try? String(contentsOf: file, encoding: .utf8)) == "{ not json")
}

// MARK: - 앱이 모르는 키의 보존

print("\n모르는 키 보존")

do {
    _ = newCase()
    var s = ClaudeSettingsModel.parse(try! ClaudeSettingsStore.load())
    s.model = "sonnet"
    let after = try! ClaudeSettingsStore.mutate { ClaudeSettingsModel.apply(s, to: &$0) }

    check("우리 키는 갱신됨", after["model"] as? String == "sonnet")
    check("permissions.allow 보존", allowCount(after) == 3)
    check("permissions.additionalDirectories 보존",
          permissions(after)?["additionalDirectories"] as? [String] == ["/tmp/a", "/tmp/b"])
    check("enabledPlugins 보존", after["enabledPlugins"] != nil)
    check("extraKnownMarketplaces 보존", after["extraKnownMarketplaces"] != nil)
    check("그 외 top-level 키 보존", after["skipWorkflowUsageWarning"] as? Bool == true)
    check("백업 파일 생성", FileManager.default.fileExists(atPath: ClaudeSettingsStore.fileURL.path + ".bak"))
}

// 읽지 못한 값은 "사용자가 비웠다"와 구별되어야 한다.
do {
    var dict: [String: Any] = [
        "model": ["unexpected": "shape"],
        "effortLevel": 42,
        "fallbackModel": "sonnet",
        "autoCompactEnabled": "yes",
        "permissions": ["defaultMode": ["a"], "allow": ["Bash(ls)"]],
    ]
    ClaudeSettingsModel.apply(ClaudeSettings(), to: &dict)

    check("타입이 다른 model 은 삭제되지 않음", dict["model"] != nil)
    check("타입이 다른 effortLevel 은 삭제되지 않음", dict["effortLevel"] != nil)
    check("타입이 다른 fallbackModel 은 삭제되지 않음", dict["fallbackModel"] != nil)
    check("타입이 다른 autoCompactEnabled 는 삭제되지 않음", dict["autoCompactEnabled"] != nil)
    check("타입이 다른 defaultMode 는 삭제되지 않음", permissions(dict)?["defaultMode"] != nil)
    check("형제 allow 목록도 그대로", permissions(dict)?["allow"] != nil)
}

do {
    var dict: [String: Any] = ["permissions": "auto"]
    ClaudeSettingsModel.apply(ClaudeSettings(), to: &dict)
    check("객체가 아닌 permissions 는 건드리지 않음", dict["permissions"] as? String == "auto")
}

// MARK: - JSON ↔ 구조체 매핑

print("\n매핑")

do {
    _ = newCase()
    let s = ClaudeSettingsModel.parse(try! ClaudeSettingsStore.load())
    check("model 파싱", s.model == "opus", "got '\(s.model)'")
    check("permissions.defaultMode 파싱", s.permissionMode == "auto", "got '\(s.permissionMode)'")
    check("없는 키는 빈 값", s.effortLevel.isEmpty && s.fallbackPrimary.isEmpty)
    check("autoCompact 는 키 부재 시 켜짐 (Claude Code 기본값)", s.autoCompact)
}

do {
    _ = newCase()
    var s = ClaudeSettings()
    s.model = "haiku"
    s.effortLevel = "xhigh"
    s.fallbackPrimary = "opus"
    s.fallbackSecondary = "sonnet"
    s.autoCompact = false
    s.permissionMode = "ask"

    _ = try! ClaudeSettingsStore.mutate { ClaudeSettingsModel.apply(s, to: &$0) }
    check("쓰고 다시 읽으면 같은 값", ClaudeSettingsModel.parse(try! ClaudeSettingsStore.load()) == s)
}

do {
    _ = newCase()
    let after = try! ClaudeSettingsStore.mutate { ClaudeSettingsModel.apply(ClaudeSettings(), to: &$0) }
    check("기본값 복귀는 model 키 삭제", after["model"] == nil)
    check("기본값 복귀는 effortLevel 키 삭제", after["effortLevel"] == nil)
    check("기본값 복귀는 fallbackModel 키 삭제", after["fallbackModel"] == nil)
    check("autoCompact 켜짐은 키 삭제로 표현", after["autoCompactEnabled"] == nil)
    check("기본값 복귀는 defaultMode 만 삭제", permissions(after)?["defaultMode"] == nil)
    check("permissions 객체와 형제 키는 생존", allowCount(after) == 3)
}

do {
    var s = ClaudeSettings()
    s.fallbackSecondary = "sonnet"
    var dict: [String: Any] = [:]
    ClaudeSettingsModel.apply(s, to: &dict)
    check("1차가 비면 2차가 승격", dict["fallbackModel"] as? [String] == ["sonnet"])

    s.fallbackPrimary = "opus"
    s.fallbackSecondary = "opus"
    dict = [:]
    ClaudeSettingsModel.apply(s, to: &dict)
    check("중복 대체 모델은 하나로 합쳐짐", dict["fallbackModel"] as? [String] == ["opus"])
}

do {
    var dict: [String: Any] = ["permissions": ["defaultMode": "ask"]]
    ClaudeSettingsStore.setNested(&dict, "permissions", "defaultMode", nil) { $0 is String }
    check("비게 된 중첩 객체는 제거", dict["permissions"] == nil)
}

// MARK: - 선택지

print("\n선택지")

do {
    let opts = ClaudeChoices.options(ClaudeChoices.models, current: "claude-opus-4-1", emptyLabel: "기본값")
    check("파일에 있는 모르는 값도 선택지에 남는다", opts.contains { $0.value == "claude-opus-4-1" })
    let known = ClaudeChoices.options(ClaudeChoices.models, current: "opus", emptyLabel: "기본값")
    check("아는 값은 중복 노출되지 않는다", known.filter { $0.value == "opus" }.count == 1)
}

// MARK: - 결과

if failures.isEmpty {
    print("\n전부 통과 (\(caseIndex)개 케이스)")
    exit(0)
} else {
    print("\n실패 \(failures.count)건:")
    failures.forEach { print("  - \($0)") }
    exit(1)
}
