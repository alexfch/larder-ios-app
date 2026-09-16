import CoreText
import SwiftUI

/// Registers the bundled Public Sans static weights with Core Text at launch. The font files
/// ship as loose resources under `Resources/Fonts` rather than through the `UIAppFonts`
/// Info.plist array -- this target's Info.plist is XcodeGen-generated from scalar
/// `INFOPLIST_KEY_*` build settings, which has no clean way to express an array of filenames.
/// Runtime registration via `CTFontManagerRegisterFontsForURL` is Apple's documented alternative
/// and needs no plist entry at all.
enum PublicSansFontLoader {
    private static var didRegister = false

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        for weight in PublicSansWeight.allCases {
            guard let url = Bundle.main.url(forResource: weight.postScriptName, withExtension: "ttf") else {
                assertionFailure("Missing bundled font resource: \(weight.postScriptName).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}

/// Public Sans' nine static weights, named to match their PostScript names exactly. The design
/// calls for "Public Sans at 800 for titles" -- SwiftUI's `Font.Weight` already spans the same
/// nine-step 100...900 scale Public Sans ships as separate static files, so each case below maps
/// onto exactly one `Font.Weight`.
private enum PublicSansWeight: CaseIterable {
    case thin, extraLight, light, regular, medium, semiBold, bold, extraBold, black

    var postScriptName: String {
        switch self {
        case .thin: return "PublicSans-Thin"
        case .extraLight: return "PublicSans-ExtraLight"
        case .light: return "PublicSans-Light"
        case .regular: return "PublicSans-Regular"
        case .medium: return "PublicSans-Medium"
        case .semiBold: return "PublicSans-SemiBold"
        case .bold: return "PublicSans-Bold"
        case .extraBold: return "PublicSans-ExtraBold"
        case .black: return "PublicSans-Black"
        }
    }
}

extension Font {
    /// The design's typeface -- "Public Sans, ... the accessibility-first grotesk" -- at a given
    /// size/weight, replacing a `.system(size:weight:)` call. Fixed-size (not `relativeTo:`
    /// Dynamic Type scaled), matching how every call site already behaved under `.system`.
    static func publicSans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        PublicSansFontLoader.registerIfNeeded()
        return .custom(postScriptName(for: weight), size: size)
    }

    private static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight: return "PublicSans-Thin"
        case .thin: return "PublicSans-ExtraLight"
        case .light: return "PublicSans-Light"
        case .medium: return "PublicSans-Medium"
        case .semibold: return "PublicSans-SemiBold"
        case .bold: return "PublicSans-Bold"
        case .heavy: return "PublicSans-ExtraBold"
        case .black: return "PublicSans-Black"
        default: return "PublicSans-Regular"
        }
    }
}
