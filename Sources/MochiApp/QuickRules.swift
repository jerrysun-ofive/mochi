import Foundation
import MochiCore

/// Common destination folders. The AI may suggest any of them even before the user
/// has created it; entries with extensions or filename keywords also appear as Quick Rules.
struct SuggestedFolder: Identifiable, Hashable {
    let id: String
    let folder: String
    let aiDescription: String
    let systemImage: String
    var extensions: [String] = []
    var filenameKeywords: [String] = []

    static let catalog: [SuggestedFolder] = [
        .init(id: "pdfs", folder: "PDFs", aiDescription: "PDF documents that fit no more specific folder", systemImage: "doc.richtext", extensions: ["pdf"]),
        .init(id: "images", folder: "Images", aiDescription: "Graphics, illustrations, memes and downloaded images", systemImage: "photo.on.rectangle.angled", extensions: ["jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "bmp"]),
        .init(id: "photos", folder: "Photos", aiDescription: "Camera and phone photos, usually named IMG_, DSC or PXL_", systemImage: "camera", filenameKeywords: ["IMG_", "DSC_", "PXL_"]),
        .init(id: "screenshots", folder: "Screenshots", aiDescription: "Screen captures and screenshots", systemImage: "camera.viewfinder", filenameKeywords: ["Screenshot", "Screen Shot"]),
        .init(id: "documents", folder: "Documents", aiDescription: "General letters, notes and word-processor documents", systemImage: "doc.text", extensions: ["doc", "docx", "pages", "txt", "rtf", "odt"]),
        .init(id: "work", folder: "Work", aiDescription: "Work documents, reports, meeting notes and anything job related", systemImage: "briefcase"),
        .init(id: "spreadsheets", folder: "Spreadsheets", aiDescription: "Spreadsheets, CSV exports and data tables", systemImage: "tablecells", extensions: ["xls", "xlsx", "csv", "numbers", "ods"]),
        .init(id: "presentations", folder: "Presentations", aiDescription: "Slide decks and presentations", systemImage: "rectangle.on.rectangle", extensions: ["ppt", "pptx", "key", "odp"]),
        .init(id: "invoices", folder: "Invoices", aiDescription: "Invoices sent or received", systemImage: "doc.plaintext", filenameKeywords: ["invoice"]),
        .init(id: "receipts", folder: "Receipts", aiDescription: "Purchase receipts and order confirmations", systemImage: "cart", filenameKeywords: ["receipt", "order confirmation"]),
        .init(id: "utility-bills", folder: "Utility Bills", aiDescription: "Electricity, gas, water, internet and phone bills", systemImage: "bolt", filenameKeywords: ["utility", "electricity", "energy bill", "water bill", "gas bill", "phone bill", "internet bill"]),
        .init(id: "bank-statements", folder: "Bank Statements", aiDescription: "Bank, credit card and brokerage statements", systemImage: "building.columns", filenameKeywords: ["statement"]),
        .init(id: "taxes", folder: "Taxes", aiDescription: "Tax returns, tax forms and payment summaries", systemImage: "percent", filenameKeywords: ["tax return", "W-2", "1099"]),
        .init(id: "contracts", folder: "Contracts", aiDescription: "Contracts, agreements, leases and legal documents", systemImage: "signature", filenameKeywords: ["contract", "agreement", "lease"]),
        .init(id: "resumes", folder: "Resumes", aiDescription: "Resumes, CVs and cover letters", systemImage: "person.text.rectangle", filenameKeywords: ["resume", "résumé", "cover letter"]),
        .init(id: "travel", folder: "Travel", aiDescription: "Boarding passes, tickets, itineraries and bookings", systemImage: "airplane", filenameKeywords: ["boarding pass", "itinerary", "e-ticket"]),
        .init(id: "health", folder: "Health", aiDescription: "Medical records, prescriptions and insurance claims", systemImage: "heart.text.square"),
        .init(id: "school", folder: "School", aiDescription: "Assignments, lecture notes, transcripts and course material", systemImage: "graduationcap"),
        .init(id: "videos", folder: "Videos", aiDescription: "Video files and screen recordings", systemImage: "film", extensions: ["mp4", "mov", "m4v", "avi", "mkv", "webm"]),
        .init(id: "audio", folder: "Audio", aiDescription: "Music, podcasts, voice memos and sound files", systemImage: "waveform", extensions: ["mp3", "wav", "m4a", "aac", "flac", "aiff"]),
        .init(id: "design", folder: "Design", aiDescription: "Design files, mockups and vector artwork", systemImage: "paintpalette", extensions: ["psd", "ai", "sketch", "fig", "xd", "svg"]),
        .init(id: "code", folder: "Code", aiDescription: "Source code, scripts and config files", systemImage: "chevron.left.forwardslash.chevron.right", extensions: ["swift", "py", "js", "ts", "json", "html", "css", "sh", "rb", "go", "rs", "java"]),
        .init(id: "fonts", folder: "Fonts", aiDescription: "Font files", systemImage: "textformat", extensions: ["ttf", "otf", "woff", "woff2"]),
        .init(id: "ebooks", folder: "Ebooks", aiDescription: "Ebooks and digital books", systemImage: "book", extensions: ["epub", "mobi", "azw3"]),
        .init(id: "archives", folder: "Archives", aiDescription: "Zip files and other compressed archives", systemImage: "archivebox", extensions: ["zip", "rar", "7z", "tar", "gz"]),
        .init(id: "installers", folder: "Installers", aiDescription: "macOS installers and disk images", systemImage: "shippingbox", extensions: ["dmg", "pkg"]),
    ]
}

struct QuickRuleTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let systemImage: String
    let extensions: [String]
    let filenameKeywords: [String]
    let subfolder: String

    static let builtIns: [QuickRuleTemplate] = SuggestedFolder.catalog.compactMap(QuickRuleTemplate.init)

    init?(_ folder: SuggestedFolder) {
        guard !folder.extensions.isEmpty || !folder.filenameKeywords.isEmpty else { return nil }
        id = folder.id
        name = "Sort \(folder.folder)"
        systemImage = folder.systemImage
        extensions = folder.extensions
        filenameKeywords = folder.filenameKeywords
        subfolder = folder.folder
        if !folder.extensions.isEmpty {
            detail = "Move \(folder.extensions.prefix(4).map { ".\($0)" }.joined(separator: ", "))\(folder.extensions.count > 4 ? " and more" : "") files into a \(folder.folder) folder."
        } else {
            detail = "Move files whose names contain \(folder.filenameKeywords.prefix(3).map { "“\($0)”" }.joined(separator: " or ")) into a \(folder.folder) folder."
        }
    }

    func makeRule(sourceGrantID: UUID?, destinationGrantID: UUID, priority: Int) -> OrganizationRule {
        var predicates: [RulePredicate] = filenameKeywords.map { .filename(operation: .contains, value: $0) }
        if !extensions.isEmpty { predicates.append(.fileExtension(values: extensions)) }
        return OrganizationRule(
            name: name,
            isEnabled: true,
            priority: priority,
            sourceGrantIDs: sourceGrantID.map { [$0] } ?? [],
            match: .init(operation: .any, predicates: predicates),
            action: .init(disposition: .move(.init(grantID: destinationGrantID, relativeSubpath: subfolder))),
            origin: .user
        )
    }
}

extension AppModel {
    @discardableResult
    func addQuickRuleInsideWatchedFolder(_ template: QuickRuleTemplate, sourceGrantID: UUID) async -> Bool {
        guard sourceGrants.contains(where: { $0.id == sourceGrantID }) else {
            notice = "Choose an authorized watched folder first."
            return false
        }
        do {
            try await allowAsDestination(sourceGrantID)
        } catch {
            notice = "Could not use that folder as a destination: \(error.localizedDescription)"
            return false
        }
        return await addQuickRule(template, sourceGrantID: sourceGrantID, destinationGrantID: sourceGrantID)
    }

    @discardableResult
    func addQuickRule(_ template: QuickRuleTemplate, sourceGrantID: UUID?, destinationGrantID: UUID) async -> Bool {
        guard sourceGrantID == nil || sourceGrants.contains(where: { $0.id == sourceGrantID }),
              destinationGrants.contains(where: { $0.id == destinationGrantID }) else {
            notice = "Choose an authorized watched folder and destination first."
            return false
        }
        guard !rules.contains(where: { $0.name == template.name }) else {
            notice = "The quick rule “\(template.name)” already exists."
            return false
        }
        let createdFolder: Bool
        do {
            createdFolder = try await ensureDestinationSubfolder(grantID: destinationGrantID, relativePath: template.subfolder)
        } catch {
            notice = "Could not prepare the \(template.subfolder) folder: \(error.localizedDescription)"
            return false
        }
        addRule(template.makeRule(sourceGrantID: sourceGrantID, destinationGrantID: destinationGrantID, priority: rules.count))
        notice = createdFolder
            ? "Created the \(template.subfolder) folder and added rule “\(template.name)”."
            : "Found the existing \(template.subfolder) folder and added rule “\(template.name)”."
        return true
    }
}
