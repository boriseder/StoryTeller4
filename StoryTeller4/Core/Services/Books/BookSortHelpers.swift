
import Foundation

enum BookSortHelpers {
    
    /// Sort books by embedded number in title
    /// Handles patterns: "Book 1", "Part 2", "Vol. 3", "Band 1", etc.
    /// Falls back to alphabetical sorting if no number found
    /// - Parameter books: Books to sort
    /// - Returns: Sorted books array
    static func sortByBookNumber(_ books: [Book]) -> [Book] {
        books.sorted { book1, book2 in
            let title1 = book1.title.lowercased()
            let title2 = book2.title.lowercased()
            
            // Try to extract book numbers for natural sorting
            if let num1 = extractBookNumber(from: title1),
               let num2 = extractBookNumber(from: title2) {
                return num1 < num2
            }
            
            // Fallback to alphabetical sorting
            return title1.localizedCompare(title2) == .orderedAscending
        }
    }
    
    /// Extract book number from title string
    /// Tries multiple patterns in order of specificity
    /// - Parameter title: Book title (should be lowercased)
    /// - Returns: Extracted number or nil
    private static func extractBookNumber(from title: String) -> Int? {
        // Patterns for common book numbering (ordered by specificity)
        let patterns = [
            #"(?:book|part|vol|volume|teil|band)\s*(\d+)"#,  // "Book 1", "Vol. 2"
            #"^(\d+)[\.\-\s]"#,                               // "1.", "2-", "3 "
            #"\b(\d+)\b"#                                     // Any standalone number
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(title.startIndex..<title.endIndex, in: title)
                if let match = regex.firstMatch(in: title, options: [], range: range),
                   match.numberOfRanges > 1 {
                    let numberRange = match.range(at: 1)
                    if let swiftRange = Range(numberRange, in: title) {
                        if let number = Int(String(title[swiftRange])) {
                            return number
                        }
                    }
                }
            }
        }
        return nil
    }
}
