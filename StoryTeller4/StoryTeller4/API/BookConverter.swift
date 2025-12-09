import Foundation

protocol BookConverterProtocol {
    func convertLibraryItemToBook(_ item: LibraryItem) -> Book?
}

class DefaultBookConverter: BookConverterProtocol {
    
    func convertLibraryItemToBook(_ item: LibraryItem) -> Book? {
        let chapters: [Chapter] = {
            if let mediaChapters = item.media.chapters, !mediaChapters.isEmpty {
                return mediaChapters.map { chapter in
                    Chapter(
                        id: chapter.id,
                        title: chapter.title,
                        start: chapter.start,
                        end: chapter.end,
                        libraryItemId: item.id,
                        episodeId: chapter.episodeId
                    )
                }
            } else if let tracks = item.media.tracks, !tracks.isEmpty {
                return tracks.enumerated().map { index, track in
                    Chapter(
                        id: "\(index)",
                        title: track.title ?? "Kapitel \(index + 1)",
                        start: track.startOffset,
                        end: track.startOffset + track.duration,
                        libraryItemId: item.id
                    )
                }
            } else {
                return [Chapter(
                    id: "0",
                    title: item.media.metadata.title,
                    start: 0,
                    end: item.media.duration ?? 3600,
                    libraryItemId: item.id
                )]
            }
        }()
        
        return Book(
            id: item.id,
            title: item.media.metadata.title,
            author: item.media.metadata.author,
            chapters: chapters,
            coverPath: item.media.coverPath,
            collapsedSeries: item.collapsedSeries
        )
    }
}
