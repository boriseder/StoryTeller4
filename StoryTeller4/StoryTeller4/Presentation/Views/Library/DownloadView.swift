import SwiftUI

struct DownloadsView: View {
    @StateObject private var viewModel: DownloadsViewModel = DependencyContainer.shared.downloadsViewModel
    @EnvironmentObject private var appState: AppStateManager
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var dependencies: DependencyContainer

    @State private var showingStorageInfo = false
    
    @AppStorage("open_fullscreen_player") private var playerMode = false
    @AppStorage("auto_play_on_book_tap") private var autoPlay = false

    var body: some View {
        ZStack {
            if theme.backgroundStyle == .dynamic {
                Color.accent.ignoresSafeArea()
            }

            contentView()
                .transition(.opacity)

        }
        .navigationTitle("Downloaded")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                toolbarButtons
            }
        }
        .alert("Delete book", isPresented: $viewModel.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                viewModel.confirmDeleteBook()
            }
        } message: {
            if let book = viewModel.bookToDelete {
                Text("Are you sure? '\(book.title)' will be deleted.")
            }
        }
        .sheet(isPresented: $showingStorageInfo) {
            storageInfoSheet
        }
        .alert("Error", isPresented: $viewModel.showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }
    
    private func contentView() -> some View {
        
        ZStack {
            if theme.backgroundStyle == .dynamic {
                DynamicBackground()
            }
            
            if viewModel.showStorageWarning {
                VStack {
                    storageWarningBanner
                        .padding(.horizontal, DSLayout.screenPadding)
                    Spacer()
                }
            }
            
            ScrollView {
                downloadStatsCard
                    .padding(.bottom, DSLayout.contentPadding)

                LazyVGrid(columns: DSGridColumns.two, alignment: .center, spacing: DSLayout.contentGap) {
                    ForEach(viewModel.downloadedBooks) { book in
                        
                        BookCardView(
                            viewModel: BookCardViewModel(book: book, container: dependencies),
                            api: viewModel.api,
                            onTap: {
                                Task {
                                    await viewModel.playBook(
                                        book,
                                        autoPlay: autoPlay
                                    )
                                }
                            },
                            onDownload: {
                                Task {
                                    await viewModel.downloadManager.downloadBook(book, api: viewModel.api)
                                }
                            },
                            onDelete: {
                                viewModel.requestDeleteBook(book)
                            }
                        )
                    }
                }
                
                Spacer()
                    .frame(height: DSLayout.miniPlayerHeight)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, DSLayout.screenPadding)
        }
    }
    
    private var storageWarningBanner: some View {
        HStack(spacing: DSLayout.contentGap) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: DSLayout.tightGap) {
                Text("Low Storage")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text("Less than \(viewModel.formatBytes(viewModel.storageThreshold)) available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                showingStorageInfo = true
            }) {
                Text("Manage")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, DSLayout.screenPadding)
        .padding(.vertical, DSLayout.comfortPadding)
        .background(Color.orange.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.orange.opacity(0.3)),
            alignment: .bottom
        )
    }
    
    private var downloadStatsCard: some View {
        VStack(spacing: DSLayout.elementGap) {
            
            HStack(spacing: DSLayout.tightGap) {
                VStack(spacing: 0) {
                    Text("\(viewModel.downloadedBooks.count) \(viewModel.downloadedBooks.count == 1 ? "book" : "books") available offline")
                        .font(DSText.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, DSLayout.elementPadding)
                
                Spacer()
                
                Button(action: {
                    showingStorageInfo = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: DSLayout.icon))
                        .frame(width: DSLayout.largeIcon, height: DSLayout.largeIcon)
                        .foregroundColor(.blue)
                }
            }
            
            Divider()
            
            HStack(spacing: DSLayout.elementGap) {
                StatItem(
                    icon: "externaldrive.fill",
                    title: "Storage Used",
                    value: viewModel.formatBytes(viewModel.totalStorageUsed),
                    color: .blue
                )
                .frame(maxWidth: .infinity, alignment: .center)
                
                Divider()
                    .frame(height: 40)
                
                StatItem(
                    icon: "externaldrive.badge.checkmark",
                    title: "Available",
                    value: viewModel.formatBytes(viewModel.availableStorage),
                    color: viewModel.availableStorage < viewModel.storageThreshold ? .orange : .green
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.vertical, DSLayout.elementPadding)
        .padding(.horizontal, DSLayout.elementPadding)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.element))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private var toolbarButtons: some View {
        HStack(spacing: DSLayout.contentGap) {
            Button(action: {
                NotificationCenter.default.post(name: .init("ShowSettings"), object: nil)
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
            }
        }
    }
    
    private var storageInfoSheet: some View {
        NavigationStack {
            List {
                Section {
                    StorageRow(
                        title: "Total Storage Used",
                        value: viewModel.formatBytes(viewModel.totalStorageUsed),
                        icon: "externaldrive.fill",
                        color: .blue
                    )
                    
                    StorageRow(
                        title: "Available Storage",
                        value: viewModel.formatBytes(viewModel.availableStorage),
                        icon: "externaldrive.badge.checkmark",
                        color: viewModel.availableStorage < viewModel.storageThreshold ? .orange : .green
                    )
                    
                    StorageRow(
                        title: "Downloaded Books",
                        value: "\(viewModel.downloadedBooks.count)",
                        icon: "books.vertical.fill",
                        color: .purple
                    )
                } header: {
                    Label("Storage Overview", systemImage: "chart.pie.fill")
                }
                
                if !viewModel.downloadedBooks.isEmpty {
                    Section {
                        ForEach(viewModel.downloadedBooks) { book in
                            HStack {
                                VStack(alignment: .leading, spacing: DSLayout.tightGap) {
                                    Text(book.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    
                                    if let author = book.author {
                                        Text(author)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: DSLayout.tightGap) {
                                    Text(viewModel.getBookStorageSize(book))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    
                                    Button(action: {
                                        viewModel.requestDeleteBook(book)
                                        showingStorageInfo = false
                                    }) {
                                        Text("Delete")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    } header: {
                        Label("Downloaded Books", systemImage: "arrow.down.circle.fill")
                    }
                }
                
                Section {
                    TipRow(
                        icon: "lightbulb.fill",
                        title: "Manage Storage",
                        description: "Delete books you've finished to free up space"
                    )
                    
                    TipRow(
                        icon: "wifi",
                        title: "Stream Instead",
                        description: "Use streaming when online to save storage"
                    )
                    
                    TipRow(
                        icon: "arrow.down.circle",
                        title: "Selective Downloads",
                        description: "Only download books you plan to listen to offline"
                    )
                } header: {
                    Label("Storage Tips", systemImage: "info.circle")
                }
                
                if !viewModel.downloadedBooks.isEmpty {
                    Section {
                        Button(role: .destructive, action: {
                            viewModel.showingDeleteAllConfirmation = true
                            showingStorageInfo = false
                        }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Delete All Downloads")
                            }
                        }
                    } header: {
                        Label("Danger Zone", systemImage: "exclamationmark.triangle")
                    } footer: {
                        Text("This will permanently delete all downloaded books. You can re-download them anytime when online.")
                    }
                }
            }
            .navigationTitle("Storage Management")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingStorageInfo = false
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StatItem: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: DSLayout.tightGap) {
            Image(systemName: icon)
                .font(.system(size: DSLayout.icon))
                .foregroundColor(color)
                .frame(width: DSLayout.largeIcon, height: DSLayout.largeIcon)
            
            VStack(alignment: .center, spacing: DSLayout.tightGap) {
                Text(title)
                    .font(DSText.footnote)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(DSText.prominent)
            }
            .frame(maxWidth: .infinity, alignment: .center)

        }
    }
}

struct StorageRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
            
            Spacer()
            
            Text(value)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
        }
    }
}

struct TipRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
