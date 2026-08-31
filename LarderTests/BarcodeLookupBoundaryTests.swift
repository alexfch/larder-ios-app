import XCTest
@testable import Larder

/// Boundary coverage for `BarcodeLookupService.normalizedBarcode`, the single gate every
/// scanned or typed barcode passes before it can be persisted as an item's identity (FR-4.2) or
/// sent to the Open Food Facts lookup (FR-4.1). `BarcodeLookupServiceTests` covers the common
/// cases; this file pins the exact length limits and the empty-input case.
final class BarcodeLookupBoundaryTests: XCTestCase {

    func testLengthLimitsAreFourToFortyEightCharactersInclusive() {
        XCTAssertNil(BarcodeLookupService.normalizedBarcode(String(repeating: "1", count: 3)), "3 is too short")
        XCTAssertEqual(BarcodeLookupService.normalizedBarcode(String(repeating: "1", count: 4))?.count, 4, "4 is the minimum")
        XCTAssertEqual(BarcodeLookupService.normalizedBarcode(String(repeating: "1", count: 48))?.count, 48, "48 is the maximum")
        XCTAssertNil(BarcodeLookupService.normalizedBarcode(String(repeating: "1", count: 49)), "49 is too long")
    }

    func testEmptyAndWhitespaceOnlyInputIsRejected() {
        XCTAssertNil(BarcodeLookupService.normalizedBarcode(""))
        XCTAssertNil(BarcodeLookupService.normalizedBarcode("     "))
    }

    func testHyphenIsAcceptedButOtherPunctuationIsNot() {
        XCTAssertEqual(BarcodeLookupService.normalizedBarcode("ABC-12345"), "ABC-12345")
        XCTAssertNil(BarcodeLookupService.normalizedBarcode("ABC_12345"), "underscore is outside the allowed set")
        XCTAssertNil(BarcodeLookupService.normalizedBarcode("ABC.12345"))
    }

    func testNormalizationTrimsWhitespaceAndUppercasesConsistently() {
        XCTAssertEqual(BarcodeLookupService.normalizedBarcode("  \tabcde12  \n"), "ABCDE12")
    }

    func testLookupReturnsNilWithoutAttemptingANetworkCallForAnInvalidBarcode() async {
        // A QR payload / junk string never passes normalization, so `lookup` must short-circuit
        // to nil rather than build a request URL from it.
        let result = await BarcodeLookupService.lookup(barcode: "https://example.com/not-a-barcode")
        XCTAssertNil(result)
    }
}
