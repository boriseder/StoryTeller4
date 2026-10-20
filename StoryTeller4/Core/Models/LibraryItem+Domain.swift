import Foundation

// MARK: - LibraryItem → Book Mapping (Domain Layer)
// Ersetzt api.converter.convertLibraryItemToBook() in den ViewModels.
// Reines Struct-zu-Struct Mapping, kein Netzwerk, keine Infrastruktur.
extension LibraryItem {

    /// Konvertiert ein LibraryItem in ein Book-Domain-Objekt.
    /// Gibt nil zurück wenn das Item eine collapsed Series ist
    /// (diese werden gesondert behandelt).
    func toBook() -> Book? {
        // Collapsed series items repräsentieren keine einzelnen Bücher
        guard !isCollapsedSeries else { return nil }

        return Book(
            id: id,
            title: media.metadata.title,
            author: media.metadata.author,
            chapters: resolvedChapters,
            coverPath: media.coverPath,
            collapsedSeries: nil,
            description: media.metadata.description
        )
    }

    /// Konvertiert ein collapsed-Series LibraryItem in ein Book,
    /// das die Series repräsentiert (z.B. für HomeViewModel sections).
    func toSeriesBook() -> Book? {
        guard let series = collapsedSeries else { return nil }

        return Book(
            id: id,
            title: series.name,
            author: series.author,
            chapters: [],
            coverPath: series.coverPath,
            collapsedSeries: series,
            description: nil
        )
    }

    /// Universelle Konvertierung: liefert immer ein Book,
    /// egal ob collapsed series oder normales Item.
    func toAnyBook() -> Book {
        return Book(
            id: id,
            title: title,           // bereits aufgelöst via LibraryItem.title computed var
            author: author,         // bereits aufgelöst via LibraryItem.author computed var
            chapters: resolvedChapters,
            coverPath: coverPath,   // bereits aufgelöst via LibraryItem.coverPath computed var
            collapsedSeries: collapsedSeries,
            description: media.metadata.description
        )
    }

    private var resolvedChapters: [Chapter] {
        if let chapters = media.chapters, !chapters.isEmpty {
            return chapters
        } else if let tracks = media.tracks, !tracks.isEmpty {
            return tracks.enumerated().map { index, track in
                Chapter(
                    id: "\(index)",
                    title: track.title ?? "Kapitel \(index + 1)",
                    start: track.startOffset,
                    end: track.startOffset + track.duration,
                    libraryItemId: id,
                    episodeId: nil
                )
            }
        } else {
            return []
        }
    }
}
