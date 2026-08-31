import XCTest
@testable import Larder

/// Covers `Item.formattedQuantity` (FR-2.3) and `Item.monogram` — pure display logic with
/// explicit acceptance criteria in the PRD but no existing test coverage.
final class ItemFormattingTests: XCTestCase {

    private func unitItem(noun: String) -> Item {
        Item(name: "Test", kind: .unit, noun: noun)
    }

    private func bulkItem(unit: String) -> Item {
        Item(name: "Test", kind: .bulk, unit: unit)
    }

    // MARK: Whole-unit items (FR-2.3)

    func testWholeUnitQuantityIsSingularAtExactlyOne() {
        XCTAssertEqual(unitItem(noun: "tin").formattedQuantity(1), "1 tin")
    }

    func testWholeUnitQuantityIsPluralAboveOne() {
        XCTAssertEqual(unitItem(noun: "tin").formattedQuantity(4), "4 tins")
    }

    func testWholeUnitQuantityIsPluralAtZero() {
        // FR-2.3: "at any other quantity the noun is plural" — zero included.
        XCTAssertEqual(unitItem(noun: "tin").formattedQuantity(0), "0 tins")
    }

    func testWholeUnitQuantityRoundsFractionalCountsToWholeNumbers() {
        // Whole-unit items are conceptually integer-valued; a stray fractional total should
        // still render as a whole count, not "2.7 tins".
        XCTAssertEqual(unitItem(noun: "tin").formattedQuantity(2.7), "3 tins")
    }

    func testWholeUnitPluralizationHandlesSibilantEndings() {
        XCTAssertEqual(unitItem(noun: "box").formattedQuantity(3), "3 boxes")
        XCTAssertEqual(unitItem(noun: "dish").formattedQuantity(2), "2 dishes")
    }

    func testWholeUnitPluralizationHandlesConsonantPlusY() {
        XCTAssertEqual(unitItem(noun: "berry").formattedQuantity(6), "6 berries")
    }

    func testWholeUnitPluralizationKeepsVowelPlusYSimple() {
        XCTAssertEqual(unitItem(noun: "tray").formattedQuantity(2), "2 trays")
    }

    // MARK: Bulk items (FR-2.3)

    func testBulkGramsBelow1000ShowRawUnit() {
        XCTAssertEqual(bulkItem(unit: "g").formattedQuantity(750), "750 g")
    }

    func testBulkMillilitresBelow1000ShowRawUnit() {
        XCTAssertEqual(bulkItem(unit: "ml").formattedQuantity(200), "200 ml")
    }

    func testBulkGramsRollUpToKilogramsAtOrAbove1000() {
        // PRD prose (FR-2.3): "roll up to kg or L (two decimal places) at or above 1000".
        // NOTE: the FR-2.3 worked example says 1,400 g reads "1.4 kg" (one decimal), which the
        // current implementation (`%.2f`) does not produce — the PRD is internally inconsistent
        // here. This test asserts the prose ("two decimal places").
        XCTAssertEqual(bulkItem(unit: "g").formattedQuantity(1400), "1.40 kg")
    }

    func testBulkMillilitresRollUpToLitresAtOrAbove1000() {
        XCTAssertEqual(bulkItem(unit: "ml").formattedQuantity(2000), "2.00 L")
    }

    func testBulkExactlyAtRollUpThreshold() {
        XCTAssertEqual(bulkItem(unit: "g").formattedQuantity(1000), "1.00 kg")
    }

    func testBulkFractionalGramsBelow1000ShowOneDecimal() {
        XCTAssertEqual(bulkItem(unit: "g").formattedQuantity(12.5), "12.5 g")
    }

    func testBulkWithNilUnitFallsBackToGrams() {
        XCTAssertEqual(Item(name: "Test", kind: .bulk, unit: nil).formattedQuantity(300), "300 g")
    }

    // MARK: monogram

    func testMonogramUsesFirstLetterOfFirstTwoWords() {
        XCTAssertEqual(Item(name: "Tinned Tomatoes", kind: .unit, noun: "tin").monogram, "TT")
    }

    func testMonogramForSingleWordNameIsOneLetter() {
        XCTAssertEqual(Item(name: "Rice", kind: .unit, noun: "bag").monogram, "R")
    }

    func testMonogramIgnoresWordsBeyondTheFirstTwo() {
        XCTAssertEqual(Item(name: "Extra Virgin Olive Oil", kind: .bulk, unit: "ml").monogram, "EV")
    }
}
