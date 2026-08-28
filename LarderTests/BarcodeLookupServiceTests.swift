import XCTest
@testable import Larder

final class BarcodeLookupServiceTests: XCTestCase {

    func testNormalizedBarcodeAcceptsPlainEAN13Digits() {
        XCTAssertEqual(BarcodeLookupService.normalizedBarcode("0123456789012"), "0123456789012")
    }

    func testNormalizedBarcodeUppercasesLettersAndTrimsWhitespace() {
        XCTAssertEqual(BarcodeLookupService.normalizedBarcode("  abc-123  "), "ABC-123")
    }

    func testNormalizedBarcodeRejectsTooShortInput() {
        XCTAssertNil(BarcodeLookupService.normalizedBarcode("12"))
    }

    func testNormalizedBarcodeRejectsTooLongInput() {
        XCTAssertNil(BarcodeLookupService.normalizedBarcode(String(repeating: "1", count: 49)))
    }

    func testNormalizedBarcodeRejectsURLLikeQRPayload() {
        // Regression test: the scanner accepts QR alongside real barcode symbologies, so a "scan"
        // can arrive as arbitrary text. A URL-shaped payload must never reach persistence or the
        // network lookup unvalidated.
        XCTAssertNil(BarcodeLookupService.normalizedBarcode("https://evil.example.com/x"))
    }

    func testNormalizedBarcodeRejectsCharactersOutsideTheNarrowedCode39Charset() {
        // Code39's full charset also allows space/$/./+/%, but those are deliberately excluded
        // (see BarcodeLookupService.allowedCharacters) since they're URL-meaningful and
        // vanishingly rare on real consumer packaging.
        XCTAssertNil(BarcodeLookupService.normalizedBarcode("ABC 123"))
        XCTAssertNil(BarcodeLookupService.normalizedBarcode("ABC$123"))
        XCTAssertNil(BarcodeLookupService.normalizedBarcode("ABC/123"))
    }
}
