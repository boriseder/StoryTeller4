import SwiftUI

// MARK: - iPad Sidebar View
struct IPadSidebarView: View {
    @Environment(AppStateManager.self) private var appState
    @Environment(DependencyContainer.self) private var dependencies
    
    let library: LibraryViewModel
    
    private var downloadManager: DownloadManager { dependencies.downloadManager }

    var body: some View {
        List {
            Section {
                sidebarButton(title: "Explore", icon: "sharedwithyou", tab: .home)
                sidebarButton(title: "Library", icon: "books.vertical.fill", tab: .library)
                sidebarButton(title: "Authors", icon: "person.2.fill", tab: .authors)
            }

            Section("Quick Actions") {
                Button(action: { appState.showingSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }

                if appState.selectedTab == .library {
                    Button(action: {
                        NotificationCenter.default.post(name: .refreshCurrentView, object: nil)
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }

            if appState.selectedTab == .library {
                LibrarySidebarFilters(viewModel: library)
            }

            if appState.selectedTab == .library {
                Section("Library Info") {
                    HStack {
                        Image(systemName: "books.vertical.fill").foregroundColor(.blue)
                        Text("Books")
                        Spacer()
                        Text("\(library.totalBooksCount)").foregroundColor(.secondary)
                    }
                    HStack {
                        Image(systemName: "arrow.down.circle").foregroundColor(.green)
                        Text("Downloaded")
                        Spacer()
                        Text("\(downloadManager.downloadedBooks.count)").foregroundColor(.secondary)
                    }
                    HStack {
                        Image(systemName: appState.isDeviceOnline ? "icloud" : "icloud.slash")
                            .foregroundColor(appState.isDeviceOnline ? .green : .red)
                        Text("Status")
                        Spacer()
                        Text(appState.isDeviceOnline ? "Online" : "Offline").foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .navigationTitle("StoryTeller")
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func sidebarButton(title: String, icon: String, tab: TabIndex) -> some View {
        Button(action: { appState.selectedTab = tab }) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .listRowBackground(appState.selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
    }
}

// MARK: - Library Sidebar Filters
struct LibrarySidebarFilters: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
        LibraryFilterControls(viewModel: viewModel)
    }
}
