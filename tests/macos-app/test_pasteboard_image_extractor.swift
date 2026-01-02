import Darwin
import AppKit
import Foundation

@main
struct PasteboardExtractorTest {
static func main() {
    let png = Data(
        [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48,
            0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00,
            0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78,
            0x9C, 0x63, 0x60, 0x00, 0x00, 0x02, 0x00, 0x01, 0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA5,
            0x7D, 0x0D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
        ]
    )

    let item = PasteboardImageExtractor.DataItem(
        types: ["public.png"],
        dataByType: ["public.png": png]
    )

    guard let extracted = PasteboardImageExtractor.extract(from: [item]) else {
        fputs("FAIL: extractor returned nil\n", stderr)
        exit(1)
    }
    guard extracted.mimeType == "image/png" else {
        fputs("FAIL: wrong mimeType: \(extracted.mimeType ?? "nil")\n", stderr)
        exit(1)
    }
    guard extracted.data == png else {
        fputs("FAIL: data mismatch\n", stderr)
        exit(1)
    }

    // TIFF -> PNG conversion path.
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: 2, height: 2).fill()
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation else {
        fputs("FAIL: could not create tiff\n", stderr)
        exit(1)
    }
    let tiffItem = PasteboardImageExtractor.DataItem(
        types: ["public.tiff"],
        dataByType: ["public.tiff": tiff]
    )
    guard let converted = PasteboardImageExtractor.extract(from: [tiffItem]) else {
        fputs("FAIL: extractor returned nil for tiff\n", stderr)
        exit(1)
    }
    guard converted.mimeType == "image/png" else {
        fputs("FAIL: wrong converted mimeType: \(converted.mimeType ?? "nil")\n", stderr)
        exit(1)
    }
    guard converted.data.starts(with: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) else {
        fputs("FAIL: converted data is not png\n", stderr)
        exit(1)
    }

    print("OK: extracted png (raw=\(extracted.data.count) bytes) and tiff->png (converted=\(converted.data.count) bytes)")
    exit(0)
}
}
