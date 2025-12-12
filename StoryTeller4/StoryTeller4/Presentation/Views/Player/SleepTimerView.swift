import SwiftUI

struct SleepTimerView: View {
    // FIX: Use @Environment(Type.self)
    @Environment(SleepTimerService.self) var sleepTimer
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if sleepTimer.isTimerActive {
                    activeTimerSection
                }
                
                Section {
                    Button(action: {
                        sleepTimer.startTimer(mode: .endOfChapter)
                        dismiss()
                    }) {
                        HStack {
                            Text("End of Chapter")
                            Spacer()
                            if sleepTimer.currentMode == .endOfChapter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button(action: {
                        sleepTimer.startTimer(mode: .endOfBook)
                        dismiss()
                    }) {
                        HStack {
                            Text("End of Book")
                            Spacer()
                            if sleepTimer.currentMode == .endOfBook {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } header: {
                    Text("Smart Timer")
                }
                
                Section {
                    ForEach(sleepTimer.timerOptionsArray, id: \.self) { minutes in
                        Button(action: {
                            sleepTimer.startTimer(mode: .duration(minutes: minutes))
                            dismiss()
                        }) {
                            HStack {
                                Text("\(minutes) Minutes")
                                Spacer()
                                if case .duration(let m) = sleepTimer.currentMode, m == minutes {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Duration")
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var activeTimerSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading) {
                    Text("Timer Active")
                        .font(.headline)
                    Text("Stops in \(TimeFormatter.formatTime(sleepTimer.remainingTime))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                
                Spacer()
                
                Button(role: .destructive, action: {
                    Task {
                        await sleepTimer.cancelTimer()
                    }
                }) {
                    Text("Cancel")
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }
}
