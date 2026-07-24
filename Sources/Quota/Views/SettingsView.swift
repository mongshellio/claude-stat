import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: UsageModel
    @ObservedObject var prefs: Preferences

    private let intervals = [180, 300, 600, 900]

    var body: some View {
        Form {
            Section("메뉴바") {
                // Live preview of the bar content with the current settings.
                LabeledContent("미리보기") {
                    MenuBarContent(fiveHourUsed: model.snapshot.fiveHourPercent,
                                   weeklyUsed: model.snapshot.weeklyAllPercent,
                                   showRemaining: prefs.showRemaining,
                                   colorCoding: prefs.colorCoding,
                                   showPercent: prefs.showPercent,
                                   fiveHourReset: TimeText.clockShort(model.snapshot.fiveHourResetAt),
                                   weeklyReset: TimeText.weekdayClockShort(model.snapshot.weeklyResetAt))
                }

                Toggle("사용량 3단계 색상", isOn: $prefs.colorCoding)
                Toggle("퍼센트 텍스트 표시", isOn: $prefs.showPercent)
                Toggle("남은 양으로 표시 (기본: 사용한 양)", isOn: $prefs.showRemaining)
                Toggle("90% 이상일 때 아이콘 맥동", isOn: $prefs.pulseWhenCritical)
            }

            Section("업데이트") {
                Picker("폴링 간격", selection: $prefs.pollIntervalSeconds) {
                    ForEach(intervals, id: \.self) { s in
                        Text(s < 600 ? "\(s / 60)분\(s % 60 == 0 ? "" : "")" : "\(s / 60)분").tag(s)
                    }
                }
                Text("최소 3분 — 더 짧으면 서버가 요청을 제한합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("25/50/75/90% 도달 알림", isOn: $prefs.notifyThresholds)
            }

            Section("계정") {
                accountRow
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 460)
    }

    @ViewBuilder private var accountRow: some View {
        switch model.loadState {
        case .loaded(.oauthLogin):
            LabeledContent("상태", value: "로그인됨 (OAuth)")
            Button("로그아웃") { model.signOut() }
        case .loaded(.claudeCodeCLI):
            LabeledContent("상태", value: "Claude Code 계정 사용 중")
            Button("이 앱 계정으로 로그인") { Task { await model.signIn() } }
        default:
            LabeledContent("상태", value: "로그아웃됨")
            Button("Claude 계정으로 로그인") { Task { await model.signIn() } }
        }
    }
}
