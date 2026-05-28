import SwiftUI

struct PlaybackSpeedView: View {
    let player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    private let rates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            Text("\(player.playbackRate, specifier: "%.2f")x")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .padding(.bottom, 16)

            HStack {
                Text("0.5x").font(.caption).foregroundColor(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(player.playbackRate) },
                        set: { player.setPlaybackRate($0) }
                    ),
                    in: 0.5...2.0,
                    step: 0.05
                ) { editing in
                    if !editing { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                }
                .tint(.accentColor)
                Text("2.0x").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, DSLayout.screenPadding)
            .padding(.bottom, 16)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                spacing: 10
            ) {
                ForEach(rates, id: \.self) { rate in
                    let isSelected = abs(Double(player.playbackRate) - rate) < 0.01
                    Button(action: {
                        player.setPlaybackRate(rate)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        // Replace DispatchQueue.main.asyncAfter with a structured
                        // Task — cancellable, no hardcoded GCD queue capture.
                        Task {
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            dismiss()
                        }
                    }) {
                        Text(formatRate(rate))
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected
                                          ? Color.accentColor
                                          : Color(.secondarySystemGroupedBackground))
                            )
                            .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, DSLayout.screenPadding)

            Spacer(minLength: 28)
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
    }

    private func formatRate(_ rate: Double) -> String {
        rate.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(rate))x"
            : String(format: "%.2fx", rate)
    }
}
