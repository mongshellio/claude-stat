import SwiftUI

/// The `Claude Code` section of the settings window — a thin renderer over
/// `ClaudeSettingsModel`, which owns every read and write of the real file.
///
/// Every row carries a Korean caption: these keys are Claude Code's, not this
/// app's, and their names ("추론 강도", "권한 기본 모드") don't explain
/// themselves. The parenthesised raw value in each option label is deliberate —
/// it's what you need to search the docs or compare against the CLI.
struct ClaudeSettingsSection: View {
    @ObservedObject var claude: ClaudeSettingsModel

    var body: some View {
        if !claude.isInstalled {
            Text("Claude Code가 설치되어 있지 않습니다")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        Text("~/.claude/settings.json 을 직접 수정합니다. 대부분 즉시 반영되고, 모델만 새 세션부터 적용됩니다.")
            .font(.caption)
            .foregroundStyle(.secondary)

        if let error = claude.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }

        Picker("기본 모델", selection: claude.binding(\.model)) {
            options(ClaudeChoices.models, current: claude.settings.model, empty: "기본값")
        }
        Text("새 세션부터 적용됩니다 — 실행 중인 세션은 `/model` 로 바꾸세요.")
            .font(.caption).foregroundStyle(.secondary)

        Picker("추론 강도", selection: claude.binding(\.effortLevel)) {
            options(ClaudeChoices.efforts, current: claude.settings.effortLevel, empty: "기본값")
        }
        Text("답하기 전 생각하는 깊이입니다. 높을수록 어려운 문제에 정확하지만 느리고 사용량을 더 씁니다.")
            .font(.caption).foregroundStyle(.secondary)

        Picker("대체 모델 1차", selection: claude.binding(\.fallbackPrimary)) {
            options(ClaudeChoices.models, current: claude.settings.fallbackPrimary, empty: "없음")
        }
        Picker("대체 모델 2차", selection: claude.binding(\.fallbackSecondary)) {
            options(ClaudeChoices.models, current: claude.settings.fallbackSecondary, empty: "없음")
        }
        Text("기본 모델이 과부하일 때 순서대로 대신 사용합니다.")
            .font(.caption).foregroundStyle(.secondary)

        Toggle("컨텍스트 자동 압축", isOn: claude.binding(\.autoCompact))
        Text("대화가 한도에 가까워지면 자동으로 요약해 이어갑니다. 끄면 긴 세션이 한도에서 멈춥니다.")
            .font(.caption).foregroundStyle(.secondary)

        Picker("권한 기본 모드", selection: claude.binding(\.permissionMode)) {
            options(ClaudeChoices.permissionModes, current: claude.settings.permissionMode, empty: "기본값")
        }
        Text("도구 실행을 어떻게 승인할지 정합니다. 즉시 반영됩니다.")
            .font(.caption).foregroundStyle(.secondary)
    }

    /// Picker rows for a choice list, including the "key absent" entry and any
    /// unrecognised value already in the file.
    @ViewBuilder private func options(_ known: [ClaudeChoice],
                                      current: String,
                                      empty: String) -> some View {
        ForEach(ClaudeChoices.options(known, current: current, emptyLabel: empty)) { choice in
            Text(choice.label).tag(choice.value)
        }
    }
}
