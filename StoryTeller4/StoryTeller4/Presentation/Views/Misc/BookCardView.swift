import SwiftUI


// MARK: - Book Card View
struct BookCardView: View {
    let viewModel: BookCardViewModel
    let api: AudiobookshelfClient?
    let onTap: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    
    @State private var isPressed = false
    @EnvironmentObject var theme: ThemeManager

    var cardWidth: CGFloat
    
    init(
        viewModel: BookCardViewModel,
        api: AudiobookshelfClient?,
        onTap: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.api = api
        self.onTap = onTap
        self.onDownload = onDownload
        self.onDelete = onDelete
        
        cardWidth = DSLayout.cardCoverNoPadding

    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: DSLayout.elementGap) {
                bookCoverSection
                bookInfoSection
                    .padding(.top, DSLayout.tightPadding)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            contextMenuItems
        }
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
    }
    
    // MARK: - Book Cover Section
    
    private var bookCoverSection: some View {
        
        ZStack {
            BookCoverView.square(
                book: viewModel.book,
                size: DSLayout.cardCoverNoPadding,
                api: api,
                downloadManager: nil,
                showProgress: false
            )
            .clipShape(RoundedRectangle(cornerRadius: DSCorners.element))
            
            if viewModel.duration > 0 && viewModel.currentProgress > 0 {
                
                VStack {
                    Spacer()
                    bookProgressIndicator
                }
            }
                
            VStack {
                HStack(alignment: .top) {
                    if viewModel.book.isCollapsedSeries && !viewModel.isDownloading {
                        seriesBadge
                            .transition(.scale.combined(with: .opacity))
                    }

                    Spacer()

                    downloadStatusView
                        .transition(.scale.combined(with: .opacity))
                }
                .padding(DSLayout.elementPadding)

                Spacer()

                if viewModel.isCurrentBook && !viewModel.isDownloading {
                    currentBookStatusOverlay
                        .padding(.bottom, DSLayout.elementPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(width: DSLayout.cardCoverNoPadding, height: DSLayout.cardCoverNoPadding)
    }

    // MARK: - Info Section

    private var bookInfoSection: some View {
        VStack(alignment: .leading, spacing: DSLayout.tightGap) {
            Text(viewModel.book.displayTitle)
                .font(DSText.detail)
                .foregroundColor(theme.textColor)
                .lineLimit(1)

                VStack(alignment: .leading, spacing: 0) {
                    Text(viewModel.book.author ?? "Unknown Author")
                        .font(DSText.metadata)
                        .foregroundColor(theme.textColor.opacity(0.85))
                        .lineLimit(1)
                    
                    Spacer()
                }
        }
        .frame(maxWidth: cardWidth - 2 * DSLayout.elementPadding, alignment: .leading)
        .padding(.horizontal, DSLayout.elementPadding)
    }

    // MARK: - Download Status Layer
    
    private var downloadStatusView: some View {
        
        ZStack {
            Circle()
                .fill(.white.opacity(0.95))
                .frame(width: DSLayout.actionButtonSize, height: DSLayout.actionButtonSize)
                .shadow(color: .black.opacity(DSLayout.shadowOpacity), radius: 6, x: 0, y: 2)

            if viewModel.isDownloading {
                Circle()
                    .trim(from: 0, to: viewModel.downloadProgress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.accentColor, .accentColor.opacity(0.8)]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: DSLayout.actionButtonSize, height: DSLayout.actionButtonSize)
                    .animation(.linear(duration: 0.2), value: viewModel.downloadProgress)
            }

            Image(systemName: {
                if viewModel.isDownloading {
                    "arrow.down.circle"
                } else if viewModel.isDownloaded {
                    "checkmark.circle.fill"
                } else {
                    "icloud.and.arrow.down"
                }
            }())
            .symbolRenderingMode(.hierarchical)
            .resizable()
            .scaledToFit()
            .frame(width: DSLayout.actionButtonSize * 0.45, height: DSLayout.actionButtonSize * 0.45)
            .foregroundStyle(viewModel.isDownloaded ? .green : Color.black)
            .transition(.opacity.combined(with: .scale))
            .animation(.easeInOut(duration: 0.25), value: viewModel.isDownloading)
            .animation(.easeInOut(duration: 0.25), value: viewModel.isDownloaded)
        }
        .onTapGesture {
            if viewModel.isDownloaded {
                onDelete()
            } else if !viewModel.isDownloading {
                onDownload()
            }
        }
    }
    
    // MARK: - Series Badge
    
    private var seriesBadge: some View {

        HStack(spacing: DSLayout.tightGap) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: DSLayout.icon, weight: .semibold))
                .foregroundColor(.white)
            Text("\(viewModel.book.seriesBookCount)")
                .font(.system(size: DSLayout.icon, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, DSLayout.contentPadding)
        .padding(.vertical, DSLayout.elementPadding)
        .background(
            Capsule()
                .fill(LinearGradient(colors: [.blue.opacity(0.85), .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)
        .scaleEffect(1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.book.seriesBookCount)
    }
    
    // MARK: - Play/Pause Overlay
    
    private var currentBookStatusOverlay: some View {
        
        HStack(spacing: DSLayout.contentGap) {
            Image(systemName: viewModel.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                .font(DSText.button)
                .foregroundColor(.white)
                .if(viewModel.isPlaying) { view in
                    view.symbolEffect(.pulse, options: .repeating, value: viewModel.isPlaying)
                }
            
            Text(viewModel.isPlaying ? "Play" : "Paused")
                .font(DSText.detail)
                .foregroundColor(.white)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, DSLayout.contentPadding)
        .padding(.vertical, DSLayout.elementPadding)
        .background(
            Capsule()
                .fill(
                    viewModel.isPlaying ?
                    AnyShapeStyle(LinearGradient(colors: [.accentColor.opacity(0.8), .accentColor.opacity(0.6)],
                                                startPoint: .leading, endPoint: .trailing)) :
                    AnyShapeStyle(Color.primary.opacity(0.7))
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)
        .scaleEffect(viewModel.isPlaying ? 1.05 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: viewModel.isPlaying)
    }
    
    // MARK: - Progress Bar
    
    private var bookProgressIndicator: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.65))
                    .frame(height: 4)
                
                Rectangle()
                    .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.8)],
                                         startPoint: .leading,
                                         endPoint: .trailing))
                    .frame(width: geometry.size.width * viewModel.currentProgress, height: 4)
                    .animation(.linear(duration: 0.2), value: viewModel.currentProgress)
            }
        }
        .frame(height: 4)
        .padding(.bottom, 2)
        .padding(.horizontal, 2)
    }
    
    // MARK: - Context Menu
    
    private var contextMenuItems: some View {
        Group {
            Button(action: onTap) {
                if viewModel.book.isCollapsedSeries {
                    Label("Show series", systemImage: "books.vertical.fill")
                } else {
                    Label("Play", systemImage: "play.fill")
                }
            }
            Divider()
            if !viewModel.isDownloaded && api != nil {
                Button(action: onDownload) {
                    if viewModel.book.isCollapsedSeries {
                        Label("Download series", systemImage: "arrow.down.circle")
                    } else {
                        Label("Download book", systemImage: "arrow.down.circle")
                    }
                }
            } else if viewModel.isDownloaded {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete download", systemImage: "trash")
                }
            }
        }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
