import SwiftUI

enum LarderFont {
    static func eyebrow() -> Font {
        .system(size: 12, weight: .semibold, design: .default).uppercaseSmallCaps()
    }

    static func screenTitle() -> Font {
        .system(size: 34, weight: .heavy, design: .default)
    }

    static func rowTitle() -> Font {
        .system(size: 17, weight: .bold)
    }

    static func rowSubtitle() -> Font {
        .system(size: 14, weight: .regular)
    }

    static func quantityValue() -> Font {
        .system(size: 20, weight: .bold)
    }

    static func quantityUnit() -> Font {
        .system(size: 12, weight: .semibold)
    }

    static func buttonLabel() -> Font {
        .system(size: 16, weight: .bold)
    }
}

extension View {
    /// Applies a wide letter-spaced uppercase style used for eyebrow labels and tags.
    func trackedUppercase() -> some View {
        textCase(.uppercase)
            .tracking(1.2)
    }
}
