import XCTest
@testable import Larder

/// FR-2.3 — quantity formatting by item kind. The rule ("4 tins", "750 g", "1.4 kg", singular
/// noun at exactly 1) has explicit Given/When/Then acceptance criteria in the PRD but no unit
/// coverage before this file: `Item.formattedQuantity` was only ever exercised transitively
/// through view code.
final class ItemFormattingTests: XCTestCase {

    private func unitItem(noun: String) -> Item {
        Item(name: "Test", kind: .unit, noun: noun)
    }

    private func bulkItem(unit: String) -> Item {
        Item(name: "Test", kind: .bulk, unit: unit)
    }

    // MARK: Whole units — pluralization (FR-2.3 AC 3)

    func testWholeUnitIsSingularAtExactlyOne() {
        XCTAssertEqual(unitItem(noun: "tin").formattedQuantity(1), "1 tin")
    }

    func testWholeUnitIsPluralAtEveryOtherQuantityIncludingZero() {
        let tins = unitItem(noun: "tin")
        XCTAssertEqual(tins.formattedQuantity(0), "0 tins")
        XCTAssertEqual(tins.formattedQuantity(2), "2 tins")
        XCTAssertEqual(tins.formattedQuantity(12), "12 tins")
    }

    func testWholeUnitQuantityIsRoundedToAWholeNumber() {
        let tins = unitItem(noun: "tin")
        XCTAssertEqual(tins.formattedQuantity(1.4), "1 tin", "1.4 rounds to 1 — singular")
        XCTAssertEqual(tins.formattedQuantity(1.6), "2 tins", "1.6 rounds to 2 — plural")
    }

    func testPluralizationHandlesCommonEnglishSuffixes() {
        XCTAssertEqual(unitItem(noun: "jar").formattedQuantity(3), "3 jars")
        XCTAssertEqual(unitItem(noun: "box").formattedQuantity(3), "3 boxes", "x → es")
        XCTAssertEqual(unitItem(noun: "dish").formattedQuantity(3), "3 dishes", "sh → es")
        XCTAssertEqual(unitItem(noun: "match").formattedQuantity(3), "3 matches", "ch → es")
        XCTAssertEqual(unitItem(noun: "berry").formattedQuantity(3), "3 berries", "consonant + y → ies")
        XCTAssertEqual(unitItem(noun: "day").formattedQuantity(3), "3 days", "vowel + y → s, not ies")
    }

    func testWholeUnitFallsBackToGenericNounWhenNoneIsSet() {
        let noNoun = Item(name: "Test", kind: .unit, noun: nil)
        XCTAssertEqual(noNoun.formattedQuantity(1), "1 unit")
        XCTAssertEqual(noNoun.formattedQuantity(2), "2 units")
    }

    // MARK: Weight / volume — base unit vs. roll-up (FR-2.3 AC 1 & 2)

    func testBulkBelowOneThousandShowsTheBaseUnit() {
        XCTAssertEqual(bulkItem(unit: "g").formattedQuantity(750), "750 g")
        XCTAssertEqual(bulkItem(unit: "ml").formattedQuantity(999), "999 ml")
    }

    func testBulkNonIntegerBelowOneThousandShowsOneDecimal() {
        XCTAssertEqual(bulkItem(unit: "g").formattedQuantity(500.5), "500.5 g")
    }

    func testBulkAtOrAboveOneThousandRollsUpToKgOrL() {
        XCTAssertEqual(bulkItem(unit: "g").formattedQuantity(1000), "1.00 kg")
        XCTAssertEqual(bulkItem(unit: "ml").formattedQuantity(2500), "2.50 L")
    }

    /// FR-2.3 AC 2 states 1,400 g "reads '1.4 kg'". The implementation formats the rolled-up
    /// value with `%.2f`, so it actually renders "1.40 kg". This test pins the current behavior;
    /// the trailing zero is a (cosmetic) deviation from the acceptance criterion's exact wording.
    func testBulkRollUpUsesTwoDecimalPlaces() {
        XCTAssertEqual(bulkItem(unit: "g").formattedQuantity(1400), "1.40 kg")
    }

    func testBulkFallsBackToGramsWhenNoUnitIsSet() {
        let noUnit = Item(name: "Test", kind: .bulk, unit: nil)
        XCTAssertEqual(noUnit.formattedQuantity(200), "200 g")
    }

    // MARK: Monogram

    func testMonogramUsesTheFirstLetterOfUpToTwoWords() {
        XCTAssertEqual(Item(name: "Nutella", kind: .unit).monogram, "N")
        XCTAssertEqual(Item(name: "kidney beans", kind: .unit).monogram, "KB")
        XCTAssertEqual(Item(name: "extra virgin olive oil", kind: .bulk).monogram, "EV", "only the first two words")
    }
}
