import SwiftUI
import UIKit

/// A numeric text field that always places the cursor at the end of its value when it gains
/// focus, regardless of where the user tapped. Native SwiftUI `TextField` exposes no API to
/// control cursor/selection position, so this wraps `UITextField` directly and repositions the
/// cursor in `textFieldDidBeginEditing` — which only fires on the focus-gaining tap, not on
/// every tap while already editing, so normal in-place cursor repositioning during active
/// editing is unaffected.
struct TrailingCursorNumberField: UIViewRepresentable {
    @Binding var value: Double
    var placeholder: String = "0"
    /// Whole-count items (e.g. "3 tins") don't take fractional values, so this switches to a
    /// plain number pad (no decimal key) and a formatter that never shows/accepts a fraction —
    /// the same `.unit` vs `.bulk` split `QuantitySheetView`'s +/- stepper already makes via
    /// `stepSize`.
    var allowsDecimal: Bool = true
    /// SwiftUI's `.font()` modifier has no effect on a wrapped `UITextField` (it only reaches
    /// native SwiftUI text views), so callers that need something other than the system default --
    /// e.g. matching `LarderFont.quantityValue()` in `QuantitySheetView` -- pass it here instead.
    var font: UIFont = .systemFont(ofSize: 17)

    /// Single source of truth for the upper bound, shared by every caller that needs to clamp
    /// against it (e.g. `QuantitySheetView`'s +/- stepper) instead of redeclaring the literal.
    static let maxValue: Double = 9999.999

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.maximumIntegerDigits = 4
        return formatter
    }()

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.maximumIntegerDigits = 4
        return formatter
    }()

    private var formatter: NumberFormatter {
        allowsDecimal ? Self.decimalFormatter : Self.integerFormatter
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.keyboardType = allowsDecimal ? .decimalPad : .numberPad
        textField.textAlignment = .right
        textField.placeholder = placeholder
        textField.font = font
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        uiView.font = font
        // `lastCommittedValue` is the value the coordinator itself last pushed (from a
        // keystroke or from here). When `value` still matches it, this call is just SwiftUI's
        // binding round-tripping our own edit back in — leave the text alone so we don't stomp
        // in-progress input like a trailing decimal point. When it differs, `value` changed from
        // outside this field's own typing (e.g. the +/- stepper), so push the new text in and,
        // if the field is still focused, keep the cursor at the end -- this is what makes typing
        // and the +/- buttons stay consistent with each other regardless of which one last ran.
        guard value != context.coordinator.lastCommittedValue else { return }
        context.coordinator.lastCommittedValue = value
        uiView.text = formatter.string(from: NSNumber(value: value)) ?? "0"
        guard uiView.isFirstResponder else { return }
        let end = uiView.endOfDocument
        uiView.selectedTextRange = uiView.textRange(from: end, to: end)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Pure, UIKit-independent edit validation so the accept/reject rule is unit-testable
    /// without a live `UITextField`, and so it can share the formatter's own limits instead of
    /// re-declaring them (a previous version hardcoded ".", "3", and the max value separately
    /// here, which could silently drift from the formatter's configuration).
    static func acceptsEdit(
        to currentText: String,
        in range: NSRange,
        replacementString string: String,
        maxValue: Double,
        maxFractionDigits: Int,
        decimalSeparator: String
    ) -> Bool {
        guard let stringRange = Range(range, in: currentText) else { return false }
        let updatedText = currentText.replacingCharacters(in: stringRange, with: string)

        if updatedText.isEmpty { return true }

        // `Double.init?(String)` only recognizes "." as a decimal point, but `.decimalPad`
        // inserts the locale's own separator (e.g. "," in most European locales) -- normalize
        // to "." before parsing so typing a fraction works outside "." locales too.
        let normalizedText = updatedText.replacingOccurrences(of: decimalSeparator, with: ".")
        guard let doubleValue = Double(normalizedText) else { return false }
        guard doubleValue <= maxValue else { return false }

        let components = updatedText.components(separatedBy: decimalSeparator)
        guard components.count <= 2 else { return false }
        guard components.count < 2 || components[1].count <= maxFractionDigits else { return false }
        return true
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TrailingCursorNumberField
        // Forced to something `value` can never legitimately equal on the first call, so the
        // field's initial text always gets populated on the first `updateUIView`.
        var lastCommittedValue: Double = .nan

        init(_ parent: TrailingCursorNumberField) {
            self.parent = parent
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            TrailingCursorNumberField.acceptsEdit(
                to: textField.text ?? "",
                in: range,
                replacementString: string,
                maxValue: TrailingCursorNumberField.maxValue,
                maxFractionDigits: parent.formatter.maximumFractionDigits,
                decimalSeparator: parent.formatter.decimalSeparator
            )
        }

        @objc func textChanged(_ textField: UITextField) {
            // A partial in-progress value (e.g. "3." while typing "3.5") won't parse yet —
            // leave the bound value as-is rather than snapping it to 0 mid-edit.
            guard let text = textField.text,
                  let number = parent.formatter.number(from: text) else { return }
            lastCommittedValue = number.doubleValue
            parent.value = number.doubleValue
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            // UIKit places the cursor at the tapped character by the time this fires; resetting
            // selection here — deferred one run loop turn so it applies after that default
            // placement, not before it — overrides that with "always at the end," which is the
            // behavior requested regardless of where in the field the user actually tapped.
            DispatchQueue.main.async {
                let end = textField.endOfDocument
                textField.selectedTextRange = textField.textRange(from: end, to: end)
            }
        }
    }
}
