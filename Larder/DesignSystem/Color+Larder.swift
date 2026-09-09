import SwiftUI
import UIKit

/// Token values below are pulled directly from the Claude Design canvas ("Larder Civic") shared
/// for this app's redesign -- both its light (`:root`) and dark (`[data-theme="dark"]`) token
/// sets. Kept as one file, same as before the redesign, so every screen still has one place to
/// pull colors from; see the design's own CSS for the source these mirror.
private extension Color {
    /// "#rrggbb" or "#rrggbbaa" (also accepts the leading "#" omitted).
    init(hex: String) {
        var digits = hex
        if digits.hasPrefix("#") { digits.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: digits).scanHexInt64(&value)
        let hasAlpha = digits.count > 6
        let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
        self.init(red: red, green: green, blue: blue, opacity: alpha)
    }

    /// A color that switches between `light` and `dark` by the active `UIUserInterfaceStyle`,
    /// the same mechanism `[data-theme]` selects between on the web design -- every token below
    /// is defined this way so the app gets dark mode for free by following the system appearance,
    /// with no per-screen branching.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

extension Color {
    // MARK: Canvas / surface

    /// `--canvas` -- the screen background.
    static let larderBackground = Color(light: Color(hex: "#fbfbf9"), dark: Color(hex: "#101820"))
    /// `--surface` -- a raised card/row background, one step above canvas.
    static let larderSurface = Color(light: Color(hex: "#ffffff"), dark: Color(hex: "#18222c"))
    /// `--soft` -- a subtle fill (e.g. an unselected segmented-control option's background).
    static let larderSoft = Color(light: Color(hex: "#eef2f6"), dark: Color(hex: "#1f2b36"))

    // MARK: Text

    /// `--ink` -- primary text/icons.
    static let larderInk = Color(light: Color(hex: "#101820"), dark: Color(hex: "#f2f5f7"))
    /// `--ink-2` -- a secondary text tier stronger than `larderSecondaryText`, e.g. a detail value
    /// that should still read clearly (not yet used by any screen pre-redesign).
    static let larderInk2 = Color(light: Color(hex: "#33404b"), dark: Color(hex: "#cbd4dc"))
    /// `--muted` -- secondary text: subtitles, metadata lines, unit labels.
    static let larderSecondaryText = Color(light: Color(hex: "#4a5560"), dark: Color(hex: "#97a3ae"))
    /// `--faint` -- the quietest text tier, e.g. placeholder-like or disabled-adjacent text.
    static let larderFaint = Color(light: Color(hex: "#79838e"), dark: Color(hex: "#727e8a"))

    // MARK: Lines

    /// `--line` -- hairline dividers between rows.
    static let larderDivider = Color(light: Color(hex: "#e8e8e2"), dark: Color(hex: "#24303b"))
    /// `--edge` -- a slightly stronger border, e.g. an outlined button or unselected chip.
    static let larderEdge = Color(light: Color(hex: "#d3d3cc"), dark: Color(hex: "#35424e"))

    // MARK: Accent

    /// `--accent` -- primary buttons, the active tab, "use first" emphasis. Navy blue in this
    /// redesign, replacing the previous red.
    static let larderAccent = Color(light: Color(hex: "#123a6b"), dark: Color(hex: "#8ab4e8"))
    /// `--accent-soft` -- a light accent-tinted fill, e.g. a selected chip's background.
    static let larderAccentSoft = Color(light: Color(hex: "#eaeff5"), dark: Color(hex: "#1a2836"))
    /// `--accent-deep` -- a darker accent shade for pressed/emphasized states.
    static let larderAccentDeep = Color(light: Color(hex: "#0b2748"), dark: Color(hex: "#aecdf2"))
    /// `--onaccent` -- text/icon color placed on top of a solid `larderAccent` fill (e.g. a
    /// primary button's label). Replaces the previous hardcoded `.white`.
    static let larderOnAccent = Color(light: Color(hex: "#ffffff"), dark: Color(hex: "#0b1926"))

    // MARK: Warn (expiry)

    /// `--warn` -- expiry-soon emphasis: badge text, "use first" tags. A distinct color from
    /// `larderAccent` in this redesign (previously both reused the one red accent).
    static let larderWarn = Color(light: Color(hex: "#8c1d18"), dark: Color(hex: "#f2b8b5"))
    /// `--warn-soft` -- the expiry badge's background fill.
    static let larderExpiryBadgeBackground = Color(light: Color(hex: "#fbe9e7"), dark: Color(hex: "#33211f"))

    // MARK: Overlays

    /// `--scrim` -- the dimming layer behind a presented sheet.
    static let larderScrim = Color(light: Color(hex: "#101820").opacity(0.5), dark: Color(hex: "#04080c").opacity(0.62))
    /// `--scan-bg` -- the barcode scanner's camera-viewport background.
    static let larderScanBackground = Color(light: Color(hex: "#0d1620"), dark: Color(hex: "#080d12"))

    // MARK: Toast

    /// `--toast-bg` -- deliberately inverted from `larderInk`/`larderBackground` in dark mode (a
    /// light chip on a dark screen, not a dark-on-dark one) so a toast keeps the same contrast in
    /// either appearance rather than following the screen's own theme.
    static let larderToastBackground = Color(light: Color(hex: "#101820"), dark: Color(hex: "#f2f5f7"))
    static let larderToastForeground = Color(light: Color(hex: "#ffffff"), dark: Color(hex: "#101820"))
    static let larderToastIcon = Color(light: Color(hex: "#8ab4e8"), dark: Color(hex: "#123a6b"))

    // MARK: Wheel pickers

    /// `--picker-band` -- the selected-row highlight band in a `.wheel`-style picker.
    static let larderPickerBand = Color(light: Color(hex: "#787880").opacity(0.12), dark: Color(hex: "#787880").opacity(0.24))
    /// `--picker-near` -- an adjacent (one row away) wheel value's text color.
    static let larderPickerNear = Color(light: Color(hex: "#3c3c43").opacity(0.55), dark: Color(hex: "#ebebf5").opacity(0.5))
    /// `--picker-far` -- a further wheel value's text color.
    static let larderPickerFar = Color(light: Color(hex: "#3c3c43").opacity(0.3), dark: Color(hex: "#ebebf5").opacity(0.28))

    // MARK: Monogram tiles

    /// `--mono-1` .. `--mono-4` -- rotating monogram tile background tones. Most call sites want
    /// `larderMonoTones[item.monogramToneIndex]` rather than one of these directly.
    static let larderMono1 = Color(light: Color(hex: "#eaeff5"), dark: Color(hex: "#1e2b3a"))
    static let larderMono2 = Color(light: Color(hex: "#e6ecf2"), dark: Color(hex: "#1d2836"))
    static let larderMono3 = Color(light: Color(hex: "#eef1f4"), dark: Color(hex: "#212c38"))
    static let larderMono4 = Color(light: Color(hex: "#f0f2f4"), dark: Color(hex: "#232d38"))
    /// `--mono-fg` -- the monogram letters' color, consistent across every tone above.
    static let larderMonoForeground = Color(light: Color(hex: "#123a6b"), dark: Color(hex: "#a8c7ea"))
    /// Indexed by `Item.monogramToneIndex` (`0..<4`) to pick a monogram tile's background tone.
    static let larderMonoTones: [Color] = [.larderMono1, .larderMono2, .larderMono3, .larderMono4]

    /// `--chip` -- a neutral pill/tag background (e.g. a "N batches" tag).
    static let larderChip = Color(light: Color(hex: "#f0f0ea"), dark: Color(hex: "#222e3a"))
}
