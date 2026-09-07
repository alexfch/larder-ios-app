import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

/// FR-3.1/FR-3.2: captures name, barcode (optional), packaged/non-packaged shape, and an
/// optional photo. Saving only creates the item -- it does not check anything in itself.
/// `onSaved` hands the newly created item back to the presenter, which is expected to
/// immediately follow up with the existing Check In flow (`QuantitySheetView(mode: .checkIn)`)
/// so the user picks quantity and best-before date there, exactly as they would for an existing
/// product.
///
/// The "Type" and "Measure by" pickers below map directly onto `Item.packaging`/
/// `Item.measurementStyle` -- see that struct's doc comment for the three shapes a product can
/// take (packaged / non-packaged-counted / non-packaged-bulk).
struct NewProductFormView: View {
    @Environment(CatalogStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let prefilledBarcode: String?
    private let onSaved: (Item) -> Void

    @State private var name: String
    @State private var barcode: String
    @State private var noun: String = ""
    @State private var packageAmount: Double = 0
    @State private var measurementUnit: String = "g"
    @State private var packaging: PackagingType = .packaged
    @State private var measurementStyle: MeasurementStyle = .bulk
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showCamera = false
    @State private var nameError = false
    @State private var barcodeError: String?
    @State private var lookupState: LookupState = .idle
    @State private var isSaving = false
    @State private var showPhotosPicker = false

    private enum LookupState {
        case idle, loading, found, notFound
    }

    /// Seeds `name`/`barcode` here rather than in `.onAppear`, per the architecture review:
    /// `.onAppear`-based seeding depends on view teardown/recreation, a weaker guarantee than
    /// `init` and a contributing factor to the barcode-prefill bug. The lookup network call
    /// itself stays a `.task` side effect below — that's not a state-seeding concern, just work
    /// tied to the view's lifetime.
    init(prefilledBarcode: String? = nil, prefilledName: String = "", onSaved: @escaping (Item) -> Void = { _ in }) {
        self.prefilledBarcode = prefilledBarcode
        self.onSaved = onSaved
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

                Picker("Type", selection: $packaging) {
                    Text("packaged").tag(PackagingType.packaged)
                    Text("non-packaged").tag(PackagingType.nonPackaged)
                }
                .pickerStyle(.segmented)

                if packaging == .packaged {
                    // Amount/unit are optional -- leave the amount at 0 to skip, for anything
                    // where a single package doesn't have a meaningful bulk size, like a jar of
                    // pickles bought by the jar rather than by weight. See
                    // `Item.packageBulkEquivalentText` for how this becomes the on-hand display's
                    // "(2.5 kg)" suffix.
                    Section("Package details") {
                        TextField("Name (jar, tin, egg…)", text: $noun)
                            .textInputAutocapitalization(.never)
                        HStack {
                            Text("Amount per package")
                            Spacer()
                            TrailingCursorNumberField(value: $packageAmount)
                        }
                        Picker("Units of measurement", selection: $measurementUnit) {
                            Text("g").tag("g")
                            Text("kg").tag("kg")
                            Text("lb").tag("lb")
                            Text("ml").tag("ml")
                            Text("l").tag("l")
                        }
                        .pickerStyle(.segmented)
                    }
                } else {
                    Picker("Measure by", selection: $measurementStyle) {
                        Text("item").tag(MeasurementStyle.count)
                        Text("weight").tag(MeasurementStyle.bulk)
                    }
                    .pickerStyle(.segmented)

                    if measurementStyle == .count {
                        TextField("Item name (egg, apple, lemon…)", text: $noun)
                            .textInputAutocapitalization(.never)
                    } else {
                        Picker("Units of measurement", selection: $measurementUnit) {
                            Text("g").tag("g")
                            Text("kg").tag("kg")
                            Text("lb").tag("lb")
                            Text("ml").tag("ml")
                            Text("l").tag("l")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Photo") {
                    Menu {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                        Button {
                            showPhotosPicker = true
                        } label: {
                            Label("Choose from Library", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        HStack {
                            if let photoData, let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipped()
                            }
                            Text(photoData == nil ? "Add photo" : "Change photo")
                        }
                    }
                    .photosPicker(isPresented: $showPhotosPicker, selection: $photoItem, matching: .images)
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
            // Form provides no built-in "tap anywhere to dismiss the keyboard" behavior — today
            // the keyboard only goes away when focus moves to another control. `simultaneousGesture`
            // fires alongside every row's own tap handling rather than intercepting it, so this
            // doesn't interfere with picking a segment, tapping the photo menu, etc. — it just
            // also resigns whatever's currently first responder (the keyboard-presenting text
            // field, whether SwiftUI-native or the UIKit-bridged Amount field) on every tap.
            .simultaneousGesture(
                TapGesture().onEnded {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            )
            .navigationTitle("New Product")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
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
        .sheet(isPresented: $showCamera) {
            ProductCameraCaptureView { data in
                Task {
                    // Same downsample-before-storing treatment as a library photo.
                    photoData = await ImageDownsampling.downsample(data) ?? data
                }
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
        guard !isSaving else { return }

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
        if let normalizedBarcode, let existing = store.item(matchingBarcode: normalizedBarcode) {
            barcodeError = "This barcode is already used by “\(existing.name)”. Check stock in against that item instead of adding a duplicate."
            return
        }

        isSaving = true
        Task {
            await performSave(normalizedBarcode: normalizedBarcode)
            isSaving = false
        }
    }

    /// Uploads the photo (if any) *before* writing anything to Firestore, rather than firing the
    /// upload off afterward and letting it fail silently in the background: an item whose
    /// `photoStorageRef` points at an object that never successfully uploaded would show the
    /// monogram fallback forever with no explanation and no retry path (there's no "change photo"
    /// flow outside this form yet). Failing the whole save and leaving the form's fields intact —
    /// exactly how the barcode-conflict and name-validation errors above already behave — means
    /// the user sees one clear error and can just hit Save again.
    private func performSave(normalizedBarcode: String?) async {
        let itemId = UUID().uuidString
        var photoStorageRef: String?
        if let photoData {
            do {
                photoStorageRef = try await PhotoStorage.upload(photoData, householdId: store.householdId, itemId: itemId)
            } catch {
                barcodeError = "Couldn't upload the photo — check your connection and try again."
                return
            }
        }

        let item: Item
        switch packaging {
        case .packaged:
            item = Item(
                id: itemId,
                name: name,
                barcode: normalizedBarcode,
                packaging: .packaged,
                packageName: noun.isEmpty ? nil : noun,
                packageAmount: packageAmount > 0 ? packageAmount : nil,
                packageMeasurementUnit: packageAmount > 0 ? measurementUnit : nil,
                photoStorageRef: photoStorageRef
            )
        case .nonPackaged:
            switch measurementStyle {
            case .count:
                item = Item(
                    id: itemId,
                    name: name,
                    barcode: normalizedBarcode,
                    packaging: .nonPackaged,
                    measurementStyle: .count,
                    countUnitName: noun.isEmpty ? nil : noun,
                    photoStorageRef: photoStorageRef
                )
            case .bulk:
                item = Item(
                    id: itemId,
                    name: name,
                    barcode: normalizedBarcode,
                    packaging: .nonPackaged,
                    measurementStyle: .bulk,
                    bulkMeasurementUnit: measurementUnit,
                    photoStorageRef: photoStorageRef
                )
            }
        }
        do {
            try store.addItem(item)
            // Hand off to the presenter rather than checking in or dismissing here -- it's
            // expected to immediately switch to `QuantitySheetView(mode: .checkIn)` for this
            // item, mirroring how `ManualPickListView.onAddNewProduct` already hands a typed
            // name back up rather than acting on it directly.
            onSaved(item)
        } catch {
            barcodeError = error.localizedDescription
        }
    }
}
