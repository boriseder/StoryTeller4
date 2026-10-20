import SwiftUI

struct AuthorsView: View {
    let viewModel: AuthorsViewModel

    @Environment(ThemeManager.self) var theme
    @Environment(AppStateManager.self) var appState
    @Environment(DependencyContainer.self) var dependencies

    var body: some View {
        @Bindable var vm = viewModel
        
        ZStack {
            DynamicBackground()
            List {
            ForEach(viewModel.filteredAuthors) { author in
                NavigationLink(value: author) {
                    AuthorRow(author: author, api: viewModel.api)
                }
            }
        }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Authors")
        .searchable(
            text: $vm.searchText,
            placement: .automatic,
            prompt: "Search authors..."
        )
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SettingsButton()
            }
        }
        .task {
            await viewModel.loadAuthors()
        }
        .navigationDestination(for: Author.self) { author in
            if let authorVM = dependencies.makeAuthorDetailViewModel(
                author: author,
                onBookSelected: { }
            ) {
                AuthorDetailView(viewModel: authorVM)
            }
        }
    }
}

// MARK: - Author Row Component
struct AuthorRow: View {
    let author: Author
    let api: AudiobookshelfClient?

    var body: some View {
        HStack(spacing: DSLayout.contentGap) {
            AuthorImageView(
                author: author,
                api: api,
                size: DSLayout.smallAvatar
            )

            VStack(alignment: .leading, spacing: DSLayout.elementGap) {
                Text(author.name)
                    .font(DSText.detail)
                    .lineLimit(1)

                Text("\(author.numBooks ?? 0) \((author.numBooks ?? 0) == 1 ? "Book" : "Books")")
                    .font(DSText.metadata)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let description = author.description, !description.isEmpty {
                    Text(description)
                        .font(DSText.metadata)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
