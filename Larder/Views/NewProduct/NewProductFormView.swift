import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// FR-3.1/FR-3.2: captures name, barcode (optional), unit/bulk kind, quantity, expiry, and an
/// optional photo. Saving performs the item's initial check-in.
struct NewProductFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.dismiss) private var dismiss

    var prefilledBarcode: String? = nil
    var prefilledName: String = ""

    @State private var name: String = ""
    @State private var barcode: String = ""
    @State private var kind: ItemKind = .unit
    @State private var noun: String = ""
    @State private var bulkUnit: String = "g"
    @State private var quantity: Double = 1
    @State private var expDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var nameError = false
    @State private var barcodeError: String?
    @State private var lookupState: LookupState = .idle

    private enum LookupState {
        case idle, loading, found, notFound
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .onChange(of: name) { _, _ in nameError = false }
                    if nameError {
                        Text("Enter a name before saving.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.larderAccent)
                    }

                    TextField("Barcode (optional)", text: $barcode)
                        .keyboardType(.numberPad)
                        .onChange(of: barcode) { _, _ in barcodeError = nil }
                    if let barcodeError {
                        Text(barcodeError)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.larderAccent)
                    }
                    switch lookupState {
                    case .loading:
                        Label("Looking up product…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.larderSecondaryText)
                    case .notFound:
                        Text("Nothing found on file for this barcode — enter the details below.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.larderSecondaryText)
                    default:
                        EmptyView()
                    }
                }

                Section("Kind") {
                    Picker("Kind", selection: $kind) {
                        Text("Whole units").tag(ItemKind.unit)
                        Text("Weight / Volume").tag(ItemKind.bulk)
                    }
                    .pickerStyle(.segmented)

                    if kind == .unit {
                        TextField("Unit name (jar, tin, egg…)", text: $noun)
                        Stepper(value: $quantity, in: 0...9999, step: 1) {
                            Text("Quantity: \(Int(quantity))")
                        }
                    } else {
                        Picker("Unit", selection: $bulkUnit) {
                            Text("g").tag("g")
                            Text("ml").tag("ml")
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Text("Amount checked in")
                            Spacer()
                            TextField("0", value: $quantity, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }
                }

                Section("Best Before") {
                    DatePicker("Expiration date", selection: $expDate, displayedComponents: .date)
                }

                Section("Photo") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        HStack {
                            if let photoData, let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipped()
                            }
                            Text(photoData == nil ? "Add a photo" : "Change photo")
                        }
                    }
                    .onChange(of: photoItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                photoData = data
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Product")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .onAppear {
            name = prefilledName
            if let prefilledBarcode {
                barcode = prefilledBarcode
                runLookup(for: prefilledBarcode)
            }
        }
    }

    private func runLookup(for code: String) {
        lookupState = .loading
        Task {
            let result = await BarcodeLookupService.lookup(barcode: code)
            if let result, let productName = result.name, !productName.isEmpty {
                if name.isEmpty { name = productName }
                lookupState = .found
            } else {
                lookupState = .notFound
            }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            nameError = true
            return
        }

        let trimmedBarcode = barcode.trimmingCharacters(in: .whitespaces)

        // Barcode is the de facto identity scans resolve against (Check In, Check Out, and
        // Count scan-sweep all match on it) — nothing in the schema enforces uniqueness, so a
        // second item saved with the same code would silently steal scans from the first and
        // desync its on-hand total with no error surfaced. Block it here instead, per the
        // architecture review's recommendation to do this as an explicit app-level check rather
        // than a SwiftData @Attribute(.unique) (whose autosave-merge behavior isn't validated
        // for this app yet).
        if !trimmedBarcode.isEmpty, let existing = existingItem(forBarcode: trimmedBarcode) {
            barcodeError = "This barcode is already used by “\(existing.name)”. Check stock in against that item instead of adding a duplicate."
            return
        }

        let item = Item(
            name: name,
            barcode: trimmedBarcode.isEmpty ? nil : trimmedBarcode,
            kind: kind,
            unit: kind == .bulk ? bulkUnit : nil,
            noun: kind == .unit ? (noun.isEmpty ? "unit" : noun) : nil,
            photoData: photoData
        )
        context.insert(item)
        StockService.checkIn(item: item, qty: quantity, exp: expDate, context: context)
        toastCenter.show("\(item.name) added to Stock")
        dismiss()
    }

    private func existingItem(forBarcode code: String) -> Item? {
        var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.barcode == code })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
