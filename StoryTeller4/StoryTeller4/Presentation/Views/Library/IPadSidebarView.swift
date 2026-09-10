import SwiftUI

// MARK: - iPad Sidebar View
struct IPadSidebarView: View {
    @Environment(AppStateManager.self) private var appState
    @Environment(DependencyContainer.self) private var dependencies
    
    let library: LibraryViewModel
    let series: SeriesViewModel
    let downloads: DownloadsViewModel
    
    private var downloadManager: DownloadManager { dependencies.downloadManager }

    var body: some View {
        List {
            Section {
                sidebarButton(title: "Explore", icon: "sharedwithyou", tab: .home)
                sidebarButton(title: "Library", icon: "books.vertical.fill", tab: .library)
                sidebarButton(title: "Series", icon: "play.square.stack.fill", tab: .series)
                
                Button(action: { appState.selectedTab = .downloads }) {
                    HStack {
                        Label("Downloads", systemImage: "arrow.down.circle.fill")
                        Spacer()
                        if downloadManager.downloadedBooks.count > 0 {
                            Text("\(downloadManager.downloadedBooks.count)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(appState.selectedTab == .downloads ? Color.accentColor.opacity(0.15) : Color.clear)
            }

            Section("Quick Actions") {
                Button(action: { appState.showingSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }

                if appState.selectedTab == .library || appState.selectedTab == .series {
                    Button(action: {
                        NotificationCenter.default.post(name: .refreshCurrentView, object: nil)
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }

            if appState.selectedTab == .library {
                LibrarySidebarFilters(viewModel: library)
            } else if appState.selectedTab == .series {
                SeriesSidebarSort(viewModel: series)
            }

            if appState.selectedTab == .library || appState.selectedTab == .series || appState.selectedTab == .downloads {
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
        Section("Filters & Sorting") {
            Menu {
                ForEach(LibrarySortOption.allCases) { option in
                    Button {
                        viewModel.filterState.selectedSortOption = option
                        viewModel.filterState.saveToDefaults()
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if viewModel.filterState.selectedSortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Sort: \(viewModel.filterState.selectedSortOption.rawValue)")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }

            Button {
                viewModel.filterState.sortAscending.toggle()
                viewModel.filterState.saveToDefaults()
            } label: {
                HStack {
                    Image(systemName: viewModel.filterState.sortAscending ? "arrow.up" : "arrow.down")
                    Text(viewModel.filterState.sortAscending ? "Ascending" : "Descending")
                    Spacer()
                }
            }

            Button { viewModel.toggleDownloadFilter() } label: {
                HStack {
                    Label("Downloaded Only", systemImage: "arrow.down.circle")
                    Spacer()
                    if viewModel.filterState.showDownloadedOnly {
                        Image(systemName: "checkmark").foregroundColor(.accentColor)
                    }
                }
            }

            Button { viewModel.toggleSeriesMode() } label: {
                HStack {
                    Label("Group Series", systemImage: "square.stack.3d.up")
                    Spacer()
                    if viewModel.filterState.showSeriesGrouped {
                        Image(systemName: "checkmark").foregroundColor(.accentColor)
                    }
                }
            }

            if viewModel.filterState.hasActiveFilters {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.3)) { viewModel.resetFilters() }
                } label: {
                    Label("Reset Filters", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }
}

// MARK: - Series Sidebar Sort
struct SeriesSidebarSort: View {
    @Bindable var viewModel: SeriesViewModel

    var body: some View {
        Section("Sorting") {
            Menu {
                ForEach(SeriesSortOption.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.filterState.selectedSortOption = option
                        }
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if viewModel.filterState.selectedSortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Sort: \(viewModel.filterState.selectedSortOption.rawValue)")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}
