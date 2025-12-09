import SwiftUI

struct SeriesView: View {
    @StateObject private var viewModel: SeriesViewModel = DependencyContainer.shared.seriesViewModel
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var seriesViewModel: SeriesViewModel

    @State private var showEmptyState = false

    var body: some View {
        ZStack {
            if theme.backgroundStyle == .dynamic {
                Color.accent.ignoresSafeArea()
            }

            ZStack {
                contentView
                    .transition(.opacity)
            }
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
            if theme.backgroundStyle == .dynamic {
                DynamicBackground()
            }

            ScrollView {
                LazyVStack(spacing: DSLayout.contentGap) {
                    ForEach(viewModel.filteredAndSortedSeries) { series in
                        SeriesSectionView(
                            series: series,
                            api: viewModel.api,
                            onBookSelected: {}
                        )
                        .environmentObject(appState)
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
