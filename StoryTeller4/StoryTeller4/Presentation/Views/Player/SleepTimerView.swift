import SwiftUI

struct SleepTimerView: View {
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
                        
                        // Haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("End of Chapter")
                                    .foregroundColor(.primary)
                                Text("Stops when current chapter finishes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if sleepTimer.currentMode == .endOfChapter {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    
                    Button(action: {
                        sleepTimer.startTimer(mode: .endOfBook)
                        
                        // Haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("End of Book")
                                    .foregroundColor(.primary)
                                Text("Stops when book finishes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if sleepTimer.currentMode == .endOfBook {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                } header: {
                    Text("Smart Timer")
                } footer: {
                    Text("Timer will pause playback automatically")
                        .font(.caption)
                }
                
                Section {
                    ForEach(sleepTimer.timerOptionsArray, id: \.self) { minutes in
                        Button(action: {
                            sleepTimer.startTimer(mode: .duration(minutes: minutes))
                            
                            // Haptic feedback
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                            
                            dismiss()
                        }) {
                            HStack {
                                Text("\(minutes) Minutes")
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if case .duration(let m) = sleepTimer.currentMode, m == minutes {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Duration")
                } footer: {
                    Text("Choose a time limit for playback")
                        .font(.caption)
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
    
    // MARK: - Active Timer Section
    
    private var activeTimerSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "moon.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .symbolEffect(.pulse, options: .repeating)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Timer Active")
                        .font(.headline)
                    
                    HStack(spacing: 4) {
                        Text("Stops in")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(TimeFormatter.formatTime(sleepTimer.remainingTime))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                            .monospacedDigit()
                    }
                    
                    if case .endOfChapter = sleepTimer.currentMode {
                        Text("At end of chapter")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if case .endOfBook = sleepTimer.currentMode {
                        Text("At end of book")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(role: .destructive, action: {
                    Task {
                        await sleepTimer.cancelTimer()
                        
                        // Haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.warning)
                    }
                }) {
                    Text("Cancel")
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.vertical, 8)
        } header: {
            Text("Active Timer")
        }
    }
}
