
import SwiftUI

// MARK: - Author Image View
struct AuthorImageView: View {
    let author: Author
    let api: AudiobookshelfClient?
    let size: CGFloat
    
    @StateObject private var loader: AuthorImageLoader
    
    init(author: Author, api: AudiobookshelfClient? = nil, size: CGFloat = 60) {
        self.author = author
        self.api = api
        self.size = size
        self._loader = StateObject(wrappedValue: AuthorImageLoader(
            author: author,
            api: api
        ))
    }
    
    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if loader.isLoading {
                LoadingView()
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            loader.load()
        }
        .onDisappear {
            loader.cancelLoading()
        }
        .animation(.easeInOut(duration: 0.3), value: loader.image != nil)
    }
        
    private var placeholderView: some View {
        Circle()
           .fill(Color.accentColor.opacity(0.2))
           .frame(width: size, height: size)
           .overlay(
               Text(String(author.name.prefix(2).uppercased()))
                   .font(.system(size: size * 0.3, weight: .semibold))
                   .foregroundColor(.accentColor)
           )
    }
}
