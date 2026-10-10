import Foundation
import MochiCore

struct QuickRuleTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let systemImage: String
    let extensions: [String]
    let subfolder: String

    static let builtIns: [QuickRuleTemplate] = [
        .init(id: "pdfs", name: "Sort PDFs", detail: "Move PDF documents into a PDFs folder.", systemImage: "doc.richtext", extensions: ["pdf"], subfolder: "PDFs"),
        .init(id: "images", name: "Sort Images", detail: "Move common image files into an Images folder.", systemImage: "photo.on.rectangle.angled", extensions: ["jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "bmp"], subfolder: "Images"),
        .init(id: "screenshots", name: "Sort Screenshots", detail: "Move files whose names contain “Screenshot” into a Screenshots folder.", systemImage: "camera.viewfinder", extensions: [], subfolder: "Screenshots"),
        .init(id: "archives", name: "Sort Archives", detail: "Move downloaded archives into an Archives folder.", systemImage: "archivebox", extensions: ["zip", "rar", "7z", "tar", "gz"], subfolder: "Archives"),
        .init(id: "installers", name: "Sort Installers", detail: "Move macOS installers and disk images into an Installers folder.", systemImage: "shippingbox", extensions: ["dmg", "pkg"], subfolder: "Installers"),
        .init(id: "documents", name: "Sort Documents", detail: "Move common office documents into a Documents folder.", systemImage: "doc.text", extensions: ["doc", "docx", "pages", "txt", "rtf", "odt"], subfolder: "Documents"),
    ]

    func makeRule(sourceGrantID: UUID?, destinationGrantID: UUID, priority: Int) -> OrganizationRule {
        let predicate: RulePredicate = id == "screenshots"
            ? .filename(operation: .contains, value: "Screenshot")
            : .fileExtension(values: extensions)
        return OrganizationRule(
            name: name,
            isEnabled: true,
            priority: priority,
            sourceGrantIDs: sourceGrantID.map { [$0] } ?? [],
            match: .init(operation: .all, predicates: [predicate]),
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
