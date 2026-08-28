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

    private let prefilledBarcode: String?

    @State private var name: String
    @State private var barcode: String
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

    /// Seeds `name`/`barcode` here rather than in `.onAppear`, per the architecture review:
    /// `.onAppear`-based seeding depends on view teardown/recreation, a weaker guarantee than
    /// `init` and a contributing factor to the barcode-prefill bug. The lookup network call
    /// itself stays a `.task` side effect below — that's not a state-seeding concern, just work
    /// tied to the view's lifetime.
    init(prefilledBarcode: String? = nil, prefilledName: String = "") {
        self.prefilledBarcode = prefilledBarcode
        _name = State(initialValue: prefilledName)
        _barcode = State(initialValue: prefilledBarcode ?? "")
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
                            guard let data = try? await newItem?.loadTransferable(type: Data.self) else { return }
                            // Downsample before it's ever stored: photos only ever render at
                            // thumbnail size, so there's no reason to keep the camera/photo
                            // library's full resolution in Item.photoData at all.
                            photoData = await ImageDownsampling.downsample(data) ?? data
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
        .task {
            guard let prefilledBarcode else { return }
            // The scanner accepts QR alongside real barcode symbologies, so a "scan" can arrive
            // as arbitrary text rather than a barcode. Skip the network call entirely for
            // anything that doesn't look like a real barcode, and say so up front instead of
            // leaving the field silently stuck on "no match found."
            if BarcodeLookupService.normalizedBarcode(prefilledBarcode) != nil {
                runLookup(for: prefilledBarcode)
            } else {
                barcodeError = "That doesn't look like a valid barcode — only letters, numbers, and hyphens are allowed."
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

        var normalizedBarcode: String?
        let trimmedBarcode = barcode.trimmingCharacters(in: .whitespaces)
        if !trimmedBarcode.isEmpty {
            // Reject anything that doesn't look like a real barcode before it's ever persisted —
            // a scanned QR code or hand-typed junk shouldn't silently become an item's identity.
            guard let sanitized = BarcodeLookupService.normalizedBarcode(trimmedBarcode) else {
                barcodeError = "That doesn't look like a valid barcode — only letters, numbers, and hyphens are allowed."
                return
            }
            normalizedBarcode = sanitized
        }

        // Barcode is the de facto identity scans resolve against (Check In, Check Out, and
        // Count scan-sweep all match on it) — nothing in the schema enforces uniqueness, so a
        // second item saved with the same code would silently steal scans from the first and
        // desync its on-hand total with no error surfaced. Block it here instead, per the
        // architecture review's recommendation to do this as an explicit app-level check rather
        // than a SwiftData @Attribute(.unique) (whose autosave-merge behavior isn't validated
        // for this app yet).
        if let normalizedBarcode, let existing = Item.match(barcode: normalizedBarcode, in: context) {
            barcodeError = "This barcode is already used by “\(existing.name)”. Check stock in against that item instead of adding a duplicate."
            return
        }

        let item = Item(
            name: name,
            barcode: normalizedBarcode,
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
}
