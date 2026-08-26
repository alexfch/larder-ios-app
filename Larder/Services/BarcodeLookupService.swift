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

    static func lookup(barcode: String) async -> ProductLookupResult? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json") else {
            return nil
        }

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
