/// Settings isn't a tab of its own -- per the redesign it's reached through the gear icon on
/// `LarderTopBar`, present on all three of these screens, so the bottom bar only ever needs to
/// switch between the three primary workflows.
enum AppTab: String, CaseIterable {
    case checkOut = "Check Out"
    case checkIn = "Check In"
    case stock = "Stock"

    /// SF Symbol shown above the label in `CustomTabBar`, matching the arrow vocabulary the rest
    /// of the app already uses for these actions (see `ItemDetailView`'s "Check out"/"Check in"
    /// buttons).
    var icon: String {
        switch self {
        case .checkOut: return "arrow.up"
        case .checkIn: return "arrow.down"
        case .stock: return "shippingbox"
        }
    }
}
