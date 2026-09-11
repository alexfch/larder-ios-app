import SwiftUI
import UIKit

enum QuantitySheetMode {
    case checkIn
    case checkOut
}

/// Shared by every check-in/out entry point (hub rows, scan, manual pick, item detail).
/// Shows batch chips only when checking out an item with 2+ lots, per FR-2.2.
struct QuantitySheetView: View {
    @Environment(CatalogStore.self) private var store
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss

    let item: Item
    let mode: QuantitySheetMode
    
    @State private var quantity: Double
    @State private var maxQuantity: Double = 9999.999
    @State private var expDate: Date
    @State private var selectedLot: Lot?
    @State private var errorMessage: String?
    
    init(item: Item, mode: QuantitySheetMode, preselectedLot: Lot? = nil) {
        self.item = item
        self.mode = mode
        _quantity = State(initialValue: 1)
        _expDate = State(initialValue: Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now)
        _selectedLot = State(initialValue: preselectedLot)
    }

    /// Whether `quantity` in *this* sheet currently means a whole package count rather than a
    /// continuous bulk amount. Matches `item.isCountedInWholeUnits` for every item except an
    /// `allowsPartialCheckout` packaged item being checked *out* -- for that one case, and only
    /// that case, `quantity` switches to a bulk amount (e.g. grams) so a partially-used package
    /// can be checked out by weight instead of by the whole package. Check-in for the same item
    /// stays package-count entry either way, per `Item.allowsPartialCheckout`'s doc comment.
    private var quantityIsPackageCount: Bool {
        guard item.packaging == .packaged, item.allowsPartialCheckout, mode == .checkOut else {
            return item.isCountedInWholeUnits
        }
        return false
    }

    private var stepSize: Double {
        guard !quantityIsPackageCount else { return 1 }
        let unit = item.packaging == .packaged ? item.packageMeasurementUnit : item.continuousMeasurementUnit
        return (unit == "ml" || unit == "g") ? 50 : 1
    }

    /// The suffix shown next to the quantity field. Delegates to `item.quantityUnitSuffix` for
    /// every case except checking a package *in* -- there, `quantity` is a package count even
    /// though `quantityUnitSuffix` would (correctly, for the item's *stored* quantity) call an
    /// `allowsPartialCheckout` item's unit bulk terms, so `packageCountSuffix` is used instead.
    private var quantityUnitLabel: String {
        if item.packaging == .packaged, quantityIsPackageCount {
            return item.packageCountSuffix(for: quantity)
        }
        return item.quantityUnitSuffix(for: quantity)
    }

    private var sortedLots: [Lot] {
        CatalogDerivation.sortedLots(itemId: item.id, transactions: store.transactions)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(item.name)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Color.larderInk)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider().overlay(Color.larderDivider)

            VStack(alignment: .leading, spacing: 24) {
                if mode == .checkOut, sortedLots.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Draw from batch")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.larderSecondaryText)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(sortedLots) { lot in
                                    let isSelected = (selectedLot ?? sortedLots.first)?.exp == lot.exp
                                    Button {
                                        selectedLot = lot
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.formattedQuantity(lot.qty))
                                                .font(.system(size: 13, weight: .bold))
                                            Text(lot.exp.formattedExpirationDate)
                                                .font(.system(size: 11, weight: .semibold))
                                                .opacity(0.75)
                                        }
                                        .foregroundStyle(isSelected ? Color.larderOnAccent : Color.larderInk)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 10)
                                        .background(isSelected ? Color.larderAccent : Color.larderAccentSoft)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                // Skipped entirely for a product checked in with `Item.noExpirationDate == true`
                // -- `confirm()` passes `nil` for `exp` in that case rather than reading `expDate`.
                if mode == .checkIn, !item.noExpirationDate {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Best before")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.larderSecondaryText)
                        DatePicker("", selection: $expDate, displayedComponents: .date)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(height: 100)
                            .clipped()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Quantity")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.larderSecondaryText)
                    HStack(spacing: 0) {
                        Button {
                            quantity = max(stepSize, quantity - stepSize)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 62, height: 56)
                        }
                        .overlay(alignment: .trailing) { Rectangle().fill(Color.larderInk).frame(width: 2) }
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Spacer()
                            // Bound to the raw stored quantity (base unit -- grams/mL, not the
                            // kg/L rollup `formattedQuantity` shows elsewhere) so a typed number
                            // always means exactly what it says. Cursor-to-end-on-focus behavior
                            // comes from `TrailingCursorNumberField` itself.
                            TrailingCursorNumberField(
                                value: $quantity,
                                allowsDecimal: !quantityIsPackageCount,
                                font: .boldSystemFont(ofSize: 34)
                            )
                            .fixedSize(horizontal: true, vertical: false)
                            Text(quantityUnitLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.larderSecondaryText)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            quantity = quantity + stepSize <= maxQuantity ? quantity + stepSize : quantity
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 62, height: 56)
                        }
                        .overlay(alignment: .leading) { Rectangle().fill(Color.larderInk).frame(width: 2) }
                    }
                    .frame(maxHeight: 56)
                    .foregroundStyle(Color.larderInk)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.larderEdge, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Live "≈" readout, derived from whichever direction `quantity` is currently
                    // in: checking out an `allowsPartialCheckout` item enters a bulk amount, so
                    // this shows the package-count equivalent (`packageCountEquivalentText`);
                    // every other case enters a package count, so it shows the bulk equivalent
                    // (`packageBulkEquivalentText`) -- e.g. "2.5 kg" for 5 packs of a 500 g item.
                    // nil, and this shows nothing, wherever there's nothing to convert.
                    if !quantityIsPackageCount, let countText = item.packageCountEquivalentText(for: quantity) {
                        Text("≈ \(countText)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.larderSecondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let bulkTotal = item.packageBulkEquivalentText(for: quantity) {
                        Text("≈ \(bulkTotal)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.larderSecondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.larderWarn)
                }
            }
            .padding(18)

            Spacer(minLength: 0)

            InlineIconButton(
                title: mode == .checkIn ? "Confirm check in" : "Confirm check out",
                systemIcon: "checkmark"
            ) {
                confirm()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Color.larderBackground.ignoresSafeArea())
        // `simultaneousGesture` (not `onTapGesture`) fires alongside every row's own tap
        // handling rather than intercepting it, so this doesn't interfere with the +/- buttons,
        // a batch chip, or the graphical DatePicker — it just also resigns whatever's currently
        // first responder (the UIKit-bridged quantity field) on every tap. Mirrors
        // `NewProductFormView`'s identical need for the same underlying field.
        .simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        )
        .presentationDetents([.medium])
    }

    private func confirm() {
        switch mode {
        case .checkIn:
            do {
                // Check-in always enters a package count for an `allowsPartialCheckout` item
                // (`quantityIsPackageCount` is unaffected by mode for check-in), but that item's
                // *stored* quantity is bulk terms -- convert here, the one point where a
                // package-count entry becomes the bulk amount actually written to the log.
                let storedQty = item.packaging == .packaged && item.allowsPartialCheckout
                    ? quantity * (item.packageAmount ?? 1)
                    : quantity
                try StockService.checkIn(itemId: item.id, qty: storedQty, exp: item.noExpirationDate ? nil : expDate, store: store)
                toastCenter.show("Checked in \(item.formattedQuantity(storedQty))")
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        case .checkOut:
            do {
                // `quantity` is already in the correct stored unit for check-out in every case,
                // including an `allowsPartialCheckout` item (bulk terms, per `quantityIsPackageCount`).
                try StockService.checkOut(itemId: item.id, qty: quantity, preferredLot: selectedLot ?? sortedLots.first, store: store)
                toastCenter.show("Checked out \(item.formattedQuantity(quantity))")
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
