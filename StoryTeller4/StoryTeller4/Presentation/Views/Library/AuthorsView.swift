import SwiftUI

struct AuthorsView: View {
    let viewModel: AuthorsViewModel
    
    // FIX: Use @Environment(Type.self)
    @Environment(ThemeManager.self) var theme
    @Environment(AppStateManager.self) var appState
    
    @State private var selectedAuthor: Author?

    var body: some View {
        ZStack {

            if theme.backgroundStyle == .dynamic {
                DynamicBackground()
                    .transition(.opacity)
                    .zIndex(0)
            }

            ScrollView {
                LazyVStack(spacing: DSLayout.tightGap) {
                    ForEach(viewModel.authors) { author in
                        Button {
                            selectedAuthor = author
                        } label: {
                            AuthorRow(author: author, api: viewModel.api)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, DSLayout.screenPadding)
            .transition(.opacity)
        }
        .navigationTitle("Authors")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SettingsButton()
            }
        }
        .task {
            await viewModel.loadAuthors()
        }
        .sheet(item: $selectedAuthor) { author in
            AuthorDetailView(
                author: author,
                onBookSelected: { }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.black.opacity(0.65))
        }
    }
}

// MARK: - Author Row Component
struct AuthorRow: View {
    let author: Author
    let api: AudiobookshelfClient?
 
    // FIX: Use @Environment(Type.self)
    @Environment(ThemeManager.self) var theme
    @Environment(AppStateManager.self) var appState

    var body: some View {
        HStack(spacing: DSLayout.contentGap) {
            
            // Author Image
            AuthorImageView(
                author: author,
                api: api,
                size: DSLayout.smallAvatar
            )
            
            // Author Info
            VStack(alignment: .leading, spacing: DSLayout.elementGap) {
                Text(author.name)
                    .font(DSText.detail)
                    .foregroundColor(theme.textColor)
                    .lineLimit(1)

                Text("\(author.numBooks ?? 0) \((author.numBooks ?? 0) == 1 ? "Book" : "Books")")
                    .font(DSText.metadata)
                    .foregroundColor(theme.textColor.opacity(0.85))
                    .lineLimit(1)

                if let description = author.description, !description.isEmpty {
                    Text(description)
                        .font(DSText.metadata)
                        .foregroundColor(theme.textColor.opacity(0.85))
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, DSLayout.elementPadding)
        .padding(.horizontal, DSLayout.screenPadding)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.element))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}
