import SwiftUI

struct SeriesView: View {
    // FIX: Use @Bindable for @Observable model passed in
    @Bindable var viewModel: SeriesViewModel
    
    // FIX: Use @Environment(Type.self)
    @Environment(AppStateManager.self) var appState
    @Environment(ThemeManager.self) var theme
    
    @AppStorage("auto_play_on_book_tap") private var autoPlay = false
    
    @State private var showEmptyState = false

    var body: some View {
        ZStack {
            if theme.backgroundStyle == .dynamic {
                DynamicBackground()
                    .transition(.opacity)
                    .zIndex(0)
            }

            contentView
                .transition(.opacity)
        }
        .navigationTitle("Series")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
        .searchable(text: $viewModel.filterState.searchText, prompt: "Serien durchsuchen...")
        .refreshable {
            await viewModel.loadSeries()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: DSLayout.contentGap) {
                    if !viewModel.series.isEmpty {
                        sortMenu
                    }
                    SettingsButton()
                }
            }
        }
        .task {
            await viewModel.loadSeriesIfNeeded()
        }
    }
    
    private var contentView: some View {
        ZStack {

            ScrollView {
                LazyVStack(spacing: DSLayout.contentGap) {
                    ForEach(viewModel.filteredAndSortedSeries) { series in
                        SeriesSectionView(
                            series: series,
                            api: viewModel.api,
                            onBookSelected: { book in
                                Task {
                                    await viewModel.playBook(
                                        book,
                                        appState: appState,
                                        restoreState: true
                                    )
                                }
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
    
    private var sortMenu: some View {
        Menu {
            ForEach(SeriesSortOption.allCases, id: \.self) { option in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.filterState.selectedSortOption = option
                    }
                }) {
                    Label(option.rawValue, systemImage: option.systemImage)
                    if viewModel.filterState.selectedSortOption == option {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 16))
                .foregroundColor(.primary)
        }
    }
}
