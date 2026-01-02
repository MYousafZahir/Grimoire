import AppKit
import Foundation
import UniformTypeIdentifiers

struct ExtractedImage: Equatable {
    let data: Data
    let filename: String
    let mimeType: String?
}

enum PasteboardImageExtractor {
    struct DataItem: Equatable {
        let types: [String]
        let dataByType: [String: Data]
    }

    private static let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif"]

    static func extract(from pasteboard: NSPasteboard) -> ExtractedImage? {
        if let file = extractFromFileURL(pasteboard) { return file }
        if let items = pasteboard.pasteboardItems, !items.isEmpty {
            let dataItems: [DataItem] = items.map { item in
                var map: [String: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type), !data.isEmpty {
                        map[type.rawValue] = data
                    }
                }
                return DataItem(types: item.types.map(\.rawValue), dataByType: map)
            }
            if let extracted = extract(from: dataItems) { return extracted }
        }
        if let imageObj = extractFromNSImageRead(pasteboard) { return imageObj }
        return nil
    }

    static func extract(from items: [DataItem]) -> ExtractedImage? {
        extractFromKnownDataTypes(items)
    }

    private static func extractFromFileURL(_ pasteboard: NSPasteboard) -> ExtractedImage? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
           let url = urls.first(where: { isImageFileURL($0) }),
           let data = try? Data(contentsOf: url)
        {
            let ext = url.pathExtension.lowercased()
            return ExtractedImage(data: data, filename: url.lastPathComponent, mimeType: mimeType(forExtension: ext))
        }
        return nil
    }

    private static func extractFromKnownDataTypes(_ items: [DataItem]) -> ExtractedImage? {
        let candidates: [(NSPasteboard.PasteboardType, String, String?)] = [
            (.png, "pasted-image.png", "image/png"),
            (.init("public.png"), "pasted-image.png", "image/png"),
            (.init("com.apple.pngpasteboardtype"), "pasted-image.png", "image/png"),
            (.init("public.jpeg"), "pasted-image.jpg", "image/jpeg"),
            (.init("public.jpg"), "pasted-image.jpg", "image/jpeg"),
            (.init("public.gif"), "pasted-image.gif", "image/gif"),
            (.init("com.compuserve.gif"), "pasted-image.gif", "image/gif"),
            (.init("public.webp"), "pasted-image.webp", "image/webp"),
            (.init("public.heic"), "pasted-image.heic", "image/heic"),
            (.init("public.heif"), "pasted-image.heif", "image/heif"),
        ]

        for (type, filename, mime) in candidates {
            for item in items {
                if let data = item.dataByType[type.rawValue], !data.isEmpty {
                    return ExtractedImage(data: data, filename: filename, mimeType: mime)
                }
            }
        }

        let tiffKey = NSPasteboard.PasteboardType.tiff.rawValue
        for item in items {
            if let tiff = item.dataByType[tiffKey], !tiff.isEmpty,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]),
               !png.isEmpty
            {
                return ExtractedImage(data: png, filename: "pasted-image.png", mimeType: "image/png")
            }
        }

        // Some apps place less-common encodings (e.g. BMP) or only declare a generic image type.
        // Prefer raw bytes only for formats the backend accepts; otherwise, try converting to PNG.
        for item in items {
            for typeId in item.types {
                guard let ut = UTType(typeId) else { continue }
                guard let data = item.dataByType[typeId], !data.isEmpty else { continue }

                if ut.conforms(to: .image),
                   let ext = preferredExtension(for: ut)?.lowercased(),
                   allowedExtensions.contains(ext)
                {
                    let preferredExt = preferredExtension(for: ut)
                    let mimeType = ut.preferredMIMEType
                    let filename = preferredExt.map { "pasted-image.\($0)" } ?? "pasted-image"
                    return ExtractedImage(data: data, filename: filename, mimeType: mimeType)
                }

                if ut.conforms(to: .image) || ut.conforms(to: .pdf) {
                    if let image = NSImage(data: data),
                       let png = pngData(for: image),
                       !png.isEmpty
                    {
                        return ExtractedImage(data: png, filename: "pasted-image.png", mimeType: "image/png")
                    }
                }
            }
        }

        return nil
    }

    private static func extractFromNSImageRead(_ pasteboard: NSPasteboard) -> ExtractedImage? {
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let png = pngData(for: image),
           !png.isEmpty
        {
            return ExtractedImage(data: png, filename: "pasted-image.png", mimeType: "image/png")
        }
        if let image = NSImage(pasteboard: pasteboard),
           let png = pngData(for: image),
           !png.isEmpty
        {
            return ExtractedImage(data: png, filename: "pasted-image.png", mimeType: "image/png")
        }
        return nil
    }

    static func isImageFileURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif"].contains(ext)
    }

    static func mimeType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        default: return nil
        }
    }

    static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation else { return nil }
        guard let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func preferredExtension(for type: UTType) -> String? {
        // Prefer common image extensions; UTType can return nil for some types.
        if type.conforms(to: .png) { return "png" }
        if type.conforms(to: .jpeg) { return "jpg" }
        if type.conforms(to: .gif) { return "gif" }
        if type.conforms(to: .webP) { return "webp" }
        if type.identifier == "public.heic" { return "heic" }
        if type.identifier == "public.heif" { return "heif" }
        return type.preferredFilenameExtension
    }
}
