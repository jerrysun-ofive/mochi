import Foundation
import ImageIO
import MochiCore
import PDFKit

public struct LocalContentExtractor: Sendable {
    public let characterLimit: Int

    public init(characterLimit: Int = 2_000) { self.characterLimit = characterLimit }

    public func envelope(for metadata: FileMetadata, allowBoundedText: Bool) -> MinimalFileEnvelope {
        guard allowBoundedText else { return .init(metadata: metadata) }
        let text: String?
        if metadata.fileExtension.lowercased() == "pdf" {
            text = pdfText(at: metadata.url)
        } else if let source = CGImageSourceCreateWithURL(metadata.url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            text = properties.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n")
        } else {
            text = nil
        }
        guard let text, !text.isEmpty else { return .init(metadata: metadata) }
        return .init(metadata: metadata, boundedText: redact(String(text.prefix(characterLimit))), extractionLevel: .boundedText)
    }

    private func pdfText(at url: URL) -> String? {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }
        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        let firstPage = document.page(at: 0)?.string
        return [title, firstPage].compactMap { $0 }.joined(separator: "\n")
    }

    private func redact(_ value: String) -> String {
        let patterns = [
            (#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "[email]"),
            (#"(?<!\d)(?:\+?\d[\d .()-]{7,}\d)(?!\d)"#, "[phone]"),
            (#"(?<!\d)\d{9,}(?!\d)"#, "[number]"),
        ]
        return patterns.reduce(value) { result, pair in
            guard let regex = try? NSRegularExpression(pattern: pair.0, options: [.caseInsensitive]) else { return result }
            return regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: pair.1)
        }
    }
}
