import SwiftUI

enum LarderFont {
    static func eyebrow() -> Font {
        .publicSans(size: 12, weight: .semibold).uppercaseSmallCaps()
    }

    static func screenTitle() -> Font {
        .publicSans(size: 34, weight: .heavy)
    }

    static func rowTitle() -> Font {
        .publicSans(size: 17, weight: .bold)
    }

    static func rowSubtitle() -> Font {
        .publicSans(size: 14, weight: .regular)
    }

    static func quantityValue() -> Font {
        .publicSans(size: 20, weight: .bold)
    }

    static func quantityUnit() -> Font {
        .publicSans(size: 12, weight: .semibold)
    }

    static func buttonLabel() -> Font {
        .publicSans(size: 16, weight: .bold)
    }
}

extension View {
    /// Applies a wide letter-spaced uppercase style used for eyebrow labels and tags.
    func trackedUppercase() -> some View {
        textCase(.uppercase)
            .tracking(1.2)
    }
}
