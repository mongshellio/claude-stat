import SwiftUI

/// The Claude spark mark, drawn in code (no logo asset in the repo).
/// Twelve tapered rays of slightly varying length radiate from the center,
/// filled with Claude's terracotta — instantly reads as "Claude" in the bar.
struct ClaudeMarkView: View {
    var color: Color = Palette.claudeOrange

    /// Outer radius of each ray in the 24pt design space; the alternation
    /// keeps the burst organic instead of gear-like.
    private static let rayLengths: [CGFloat] = [
        11.2, 8.6, 10.2, 8.9, 11.2, 8.4, 10.6, 8.9, 11.2, 8.6, 10.2, 8.9
    ]

    var body: some View {
        Canvas { ctx, size in
            let unit = min(size.width, size.height) / 24
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let baseHalfWidth = 1.7 * unit
            let baseRadius = 1.2 * unit

            for (i, length) in Self.rayLengths.enumerated() {
                let tip = length * unit
                // Ray pointing up (-y) in local space, then rotated into place.
                var ray = Path()
                ray.move(to: CGPoint(x: -baseHalfWidth, y: -baseRadius))
                ray.addQuadCurve(to: CGPoint(x: 0, y: -tip),
                                 control: CGPoint(x: -baseHalfWidth * 0.5, y: -tip * 0.7))
                ray.addQuadCurve(to: CGPoint(x: baseHalfWidth, y: -baseRadius),
                                 control: CGPoint(x: baseHalfWidth * 0.5, y: -tip * 0.7))
                ray.closeSubpath()

                let transform = CGAffineTransform(translationX: center.x, y: center.y)
                    .rotated(by: CGFloat(i) * .pi / 6)
                ctx.fill(ray.applying(transform), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}
