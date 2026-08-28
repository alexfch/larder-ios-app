import Foundation

struct ProductLookupResult {
    let name: String?
    let brand: String?
    let quantityText: String?
}

/// Looks up a barcode against Open Food Facts (no API key required) per FR-4.1. Only called
/// for barcodes that don't already match an existing `Item` — once an item is saved, it serves
/// as the local cache the PRD describes, since future scans of the same barcode resolve
/// directly to that item instead of triggering another lookup.
enum BarcodeLookupService {

    private struct Response: Decodable {
        let status: Int
        let product: Product?
    }

    private struct Product: Decodable {
        let product_name: String?
        let brands: String?
        let quantity: String?
    }

    /// A scanned or typed barcode is untrusted input before it reaches this point: the scanner
    /// accepts QR alongside real barcode symbologies (`BarcodeScannerView.metadataObjectTypes`),
    /// which can carry arbitrary text, and manual entry has no real enforcement beyond a
    /// numeric-keypad UI hint. Nothing should reach `Item.barcode` or this service's network
    /// request without first looking like an actual barcode. EAN/UPC are pure digits; Code128 and
    /// Code39 SKUs in this app's realistic use (retail packaging) are digits, uppercase letters,
    /// and the occasional hyphen. Code39's full charset also allows space/$/./+/%, but those are
    /// all URL-meaningful characters and vanishingly rare on real consumer packaging, so they're
    /// deliberately excluded here — narrowing the charset this way means a validated value is
    /// already safe to drop straight into a URL path segment with no further escaping needed.
    private static let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")

    /// Canonical validated form of `raw`, or `nil` if it doesn't look like a real barcode.
    /// Both persistence (`NewProductFormView`) and `lookup` below use this — never the raw
    /// scanner/text-field value directly — so one rule governs what's allowed to reach either
    /// boundary.
    static func normalizedBarcode(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (4...48).contains(trimmed.count) else { return nil }
        guard trimmed.unicodeScalars.allSatisfy(allowedCharacters.contains) else { return nil }
        return trimmed
    }

    static func lookup(barcode: String) async -> ProductLookupResult? {
        guard let sanitized = normalizedBarcode(barcode) else { return nil }

        // Built via URLComponents rather than string interpolation into a URL literal, so the
        // sanitized barcode is assembled (and, if it ever contained anything URL-meaningful,
        // percent-encoded) by the URL Loading System instead of by hand.
        var components = URLComponents()
        components.scheme = "https"
        components.host = "world.openfoodfacts.org"
        components.path = "/api/v2/product/\(sanitized).json"
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard decoded.status == 1, let product = decoded.product else { return nil }
            return ProductLookupResult(
                name: product.product_name,
                brand: product.brands,
                quantityText: product.quantity
            )
        } catch {
            return nil
        }
    }
}
