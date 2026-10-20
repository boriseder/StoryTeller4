import SwiftUI

struct SleepTimerView: View {
    @Environment(SleepTimerService.self) var sleepTimer
    @Environment(\.dismiss) private var dismiss

    private let durationOptions: [Int] = [5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            if sleepTimer.isTimerActive {
                activeTimerBanner
                    .padding(.horizontal, DSLayout.screenPadding)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack {
                Text("Sleep Timer")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, DSLayout.screenPadding)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                SmartTimerButton(
                    label: "End of Chapter",
                    icon: "text.book.closed",
                    isSelected: sleepTimer.currentMode == .endOfChapter
                ) {
                    sleepTimer.startTimer(mode: .endOfChapter)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
                SmartTimerButton(
                    label: "End of Book",
                    icon: "books.vertical",
                    isSelected: sleepTimer.currentMode == .endOfBook
                ) {
                    sleepTimer.startTimer(mode: .endOfBook)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            }
            .padding(.horizontal, DSLayout.screenPadding)
            .padding(.bottom, 10)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                spacing: 10
            ) {
                ForEach(durationOptions, id: \.self) { minutes in
                    let isSelected: Bool = {
                        if case .duration(let m) = sleepTimer.currentMode { return m == minutes }
                        return false
                    }()
                    Button(action: {
                        sleepTimer.startTimer(mode: .duration(minutes: minutes))
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }) {
                        Text("\(minutes)m")
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
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: sleepTimer.isTimerActive)
        .presentationDetents([.height(sleepTimer.isTimerActive ? 360 : 280)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Active Timer Banner

    private var activeTimerBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.fill")
                .font(.body)
                .foregroundColor(.accentColor)
                .symbolEffect(.pulse, options: .repeating)

            VStack(alignment: .leading, spacing: 2) {
                // Fixed: was "Stops in end of chapter" (grammatically broken).
                // Now correctly reads "Stops at end of chapter" or "Stops in 12:34".
                Text(stopsBannerLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(modeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                Task {
                    await sleepTimer.cancelTimer()
                    // Cancellation is a neutral/warning action, not a success.
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
            }) {
                Text("Cancel")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // "Stops in 12:34" for countdown modes,
    // "Stops at end of chapter / end of book" for content-boundary modes.
    private var stopsBannerLabel: String {
        switch sleepTimer.currentMode {
        case .endOfChapter: return "Stops at end of chapter"
        case .endOfBook:    return "Stops at end of book"
        default:            return "Stops in \(TimeFormatter.formatTime(sleepTimer.remainingTime))"
        }
    }

    // Secondary line shown below the main label — empty for countdown modes
    // since the time is already in the headline.
    private var modeDescription: String {
        switch sleepTimer.currentMode {
        case .endOfChapter, .endOfBook: return ""
        default: return ""
        }
    }
}

// MARK: - Smart Timer Button

private struct SmartTimerButton: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.subheadline)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
