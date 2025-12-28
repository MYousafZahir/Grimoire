import AppKit
import XCTest

@testable import Grimoire

@MainActor
final class PasteboardImageExtractorTests: XCTestCase {
    func testExtractsPNGFromPasteboardPNGType() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("grimoire.test.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let png = Data(
            [
                0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48,
                0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00,
                0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78,
                0x9C, 0x63, 0x60, 0x00, 0x00, 0x02, 0x00, 0x01, 0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA5,
                0x7D, 0x0D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
            ]
        )

        pasteboard.declareTypes([.png], owner: nil)
        XCTAssertTrue(pasteboard.setData(png, forType: .png))

        let extracted = PasteboardImageExtractor.extract(from: pasteboard)
        XCTAssertEqual(extracted?.mimeType, "image/png")
        XCTAssertEqual(extracted?.filename, "pasted-image.png")
        XCTAssertEqual(extracted?.data, png)
    }

    func testExtractsTIFFByConvertingToPNG() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("grimoire.test.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()

        let tiff = try XCTUnwrap(image.tiffRepresentation)
        pasteboard.declareTypes([.tiff], owner: nil)
        XCTAssertTrue(pasteboard.setData(tiff, forType: .tiff))

        let extracted = PasteboardImageExtractor.extract(from: pasteboard)
        XCTAssertEqual(extracted?.mimeType, "image/png")
        XCTAssertEqual(extracted?.filename, "pasted-image.png")

        let data = try XCTUnwrap(extracted?.data)
        XCTAssertTrue(data.starts(with: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])))
    }
}
