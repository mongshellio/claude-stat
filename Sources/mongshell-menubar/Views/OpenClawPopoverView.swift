import SwiftUI

/// Dropdown for the openclaw status item: current health + PID + actions.
/// A small SwiftUI popover in the spirit of `PopoverView`, but adaptive
/// (no forced light scheme) since it's a compact utility panel.
struct OpenClawPopoverView: View {
    @ObservedObject var model: OpenClawModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let detail = model.health.detailText {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let pid = model.pid {
                Text("PID \(pid)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            Divider()

            actions
        }
        .padding(16)
        .frame(width: 248)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.health.dotColor)
                .frame(width: 9, height: 9)
            Text("openclaw")
                .font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 8)
            Text(model.health.shortLabel)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("새로고침") { model.refreshNow() }
                Button("지금 재시작") { model.hardRestart() }
            }
            HStack(spacing: 8) {
                Button("대시보드 열기") { model.openDashboard() }
                Button("로그 열기") { model.openLog() }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity)
    }
}
