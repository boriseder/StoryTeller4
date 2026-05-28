import SwiftUI

extension String {
    func htmlToAttributedString() -> AttributedString {
        guard let data = self.data(using: .utf8) else {
            return AttributedString(self)
        }
        
        do {
            let nsString = try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
            
            // WICHTIG: Nur den reinen Text extrahieren
            let plainText = nsString.string
            
            // Neues AttributedString OHNE jegliche HTML-Formatierung erstellen
            return AttributedString(plainText)
            
        } catch {
            return AttributedString(self)
        }
    }
}
