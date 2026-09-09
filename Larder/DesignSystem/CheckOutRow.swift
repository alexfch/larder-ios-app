import SwiftUI

/// Check Out hub's row: adds a left urgency bar, a proportional multi-batch strip, and inline
/// status tags on top of the shared monogram/name/qty layout `HubRow` uses elsewhere -- matching
/// the design's richer "shortlist" row, distinct from the simpler list rows Check In and Manual
/// Pick use.
struct CheckOutRow: View {
    let item: Item
    let transactions: [Transaction]

    private var lots: [Lot] {
        CatalogDerivation.sortedLots(itemId: item.id, transactions: transactions)
    }

    private var total: Double {
        lots.reduce(0) { $0 + $1.qty }
    }

    private var earliest: Date? {
        lots.compactMap(\.exp).min()
    }

    private var isUrgent: Bool {
        guard let earliest else { return false }
        return earliest.daysFromToday <= 14
    }

    /// True when at least one batch is a partially-used open package -- see
    /// `Item.packageOpenStatus`'s doc comment for how "open" is inferred from the numbers.
    private var isOpened: Bool {
        item.packaging == .packaged && item.allowsPartialCheckout
            && lots.contains { (item.packageOpenStatus(for: $0.qty)?.openedAmount ?? 0) > 0 }
    }

    private var quantityParts: (value: String, unit: String) {
        let full = item.formattedQuantity(total)
        let parts = full.components(separatedBy: " ")
        return (parts.first ?? full, parts.dropFirst().joined(separator: " "))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(isUrgent ? Color.larderWarn : Color.clear)
                .frame(width: 3)

            ItemThumbnail(
                photoData: nil,
                photoStorageRef: item.photoStorageRef,
                monogram: item.monogram,
                size: 52,
                monogramBackground: Color.larderMonoTones[item.monogramToneIndex]
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.top, 13)
            .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.larderInk)
                        Text(earliest.map { "\($0.formatted(.iso8601.year().month().day())) · \($0.relativeDayLabel)" } ?? "no best-before date")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(isUrgent ? Color.larderWarn : Color.larderSecondaryText)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(quantityParts.value)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(Color.larderInk)
                        Text(quantityParts.unit)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.larderSecondaryText)
                    }
                }

                if lots.count > 1 {
                    HStack(spacing: 3) {
                        ForEach(Array(lots.enumerated()), id: \.element.id) { index, lot in
                            let lotUrgent = (lot.exp?.daysFromToday ?? .max) <= 14
                            RoundedRectangle(cornerRadius: 2)
                                .fill(lotUrgent ? Color.larderWarn : (index == 0 ? Color.larderAccent : Color.larderEdge))
                                .frame(width: max(lot.qty / max(total, 1), 0.06) * 100, height: 5)
                        }
                    }
                }

                if isUrgent || lots.count > 1 || isOpened {
                    HStack(spacing: 6) {
                        if isUrgent {
                            tag("USE FIRST", fg: Color.larderWarn, bg: Color.larderExpiryBadgeBackground)
                        }
                        if lots.count > 1 {
                            tag("\(lots.count) batches", fg: Color.larderSecondaryText, bg: Color.larderChip)
                        }
                        if isOpened {
                            tag("Opened", fg: Color.larderAccent, bg: Color.larderAccentSoft)
                        }
                    }
                }
            }
            .padding(.top, 13)
            .padding(.trailing, 18)
            .padding(.bottom, 11)
            .padding(.leading, 12)
        }
    }

    private func tag(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .trackedUppercase()
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
