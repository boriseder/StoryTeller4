import SwiftUI

// MARK: - Private PreferenceKeys
// File-scoped to avoid name collisions when multiple modules define width keys.

private struct ContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // Take the largest reported value across the layout tree.
        // This is safe for single-instance use and correct for multi-instance.
        value = max(value, nextValue())
    }
}

private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - MarqueeText

struct MarqueeText: View {
    let text: String
    let font: Font

    // How fast the text scrolls, in points per second.
    var speed: Double = 50

    // How long to pause (seconds) at the start before scrolling begins,
    // and again after each full loop. Matches the Apple Music feel.
    var pauseDuration: Double = 2.0

    // Width of the soft fade mask on each edge, in points.
    var fadeWidth: CGFloat = 20

    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0

    // Whether the text currently overflows its container.
    private var isOverflowing: Bool { textWidth > containerWidth && containerWidth > 0 }

    // The gap between the trailing end of one copy and the leading start of the next.
    private var loopSpacing: CGFloat { DSLayout.largeGap }

    // Total distance for one full scroll loop.
    private var loopWidth: Double { Double(textWidth + loopSpacing) }

    // Total duration of one loop cycle: pause + scroll + pause.
    // The second pause is baked into the fmod so it feels symmetric.
    private var loopDuration: Double {
        guard speed > 0 else { return pauseDuration }
        return pauseDuration + loopWidth / speed + pauseDuration
    }

    var body: some View {
        // The invisible ghost text drives the container height and measures
        // its own unconstrained width via a PreferenceKey — not onAppear,
        // so the measurement is always from the current layout pass.
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity)
            // Measure container width
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ContainerWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(ContainerWidthKey.self) { containerWidth = $0 }
            // Measure unconstrained text width
            .background(
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: TextWidthKey.self, value: geo.size.width)
                        }
                    )
            )
            .onPreferenceChange(TextWidthKey.self) { textWidth = $0 }
            // Render the visible scrolling content on top
            .overlay(alignment: .leading) {
                if isOverflowing {
                    scrollingContent
                        .frame(width: containerWidth, alignment: .leading)
                        .clipped()
                        .overlay(edgeFadeMask)
                } else {
                    // Static, centered — no TimelineView, no battery cost.
                    Text(text)
                        .font(font)
                        .lineLimit(1)
                        .frame(width: containerWidth, alignment: .center)
                }
            }
            .clipped()
    }

    // MARK: - Scrolling Content

    private var scrollingContent: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            // Map continuous time into [0, loopDuration) cycles.
            let cycleTime = fmod(time, loopDuration)
            // Pause at start, then scroll, then the remaining time is the
            // trailing pause (offset stays at loopWidth, text is out of view,
            // then snaps back to 0 at the cycle boundary — invisible due to clip).
            let scrollTime = max(0, cycleTime - pauseDuration)
            let rawOffset = scrollTime * speed
            // Clamp so it doesn't overshoot during the trailing pause.
            let offset = CGFloat(min(rawOffset, loopWidth))

            HStack(spacing: loopSpacing) {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                // Second copy seamlessly follows the first.
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .offset(x: -offset)
        }
    }

    // MARK: - Edge Fade Mask

    private var edgeFadeMask: some View {
        HStack(spacing: 0) {
            // Leading fade — hides the snap-reset moment and looks premium.
            LinearGradient(
                colors: [DSColor.background, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)

            Spacer()

            // Trailing fade — soft exit as text scrolls off the right edge.
            LinearGradient(
                colors: [.clear, DSColor.background],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
        }
        .allowsHitTesting(false)
    }
}
