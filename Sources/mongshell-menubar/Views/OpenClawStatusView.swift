import SwiftUI

/// The second status item's content: a standalone colored dot for openclaw
/// health. Deliberately kept separate from the usage icon — never mixed in.
struct OpenClawStatusView: View {
    @ObservedObject var model: OpenClawModel

    var body: some View {
        Image(systemName: model.health.symbolName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(model.health.dotColor)
            .frame(width: 18, height: 18)
    }
}
