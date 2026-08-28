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

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter
    }()

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.keyboardType = .decimalPad
        textField.textAlignment = .right
        textField.placeholder = placeholder
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        // Never overwrite text the user is actively typing — only push the SwiftUI-side value
        // in when the field isn't first responder (e.g. the initial value, or a change made
        // elsewhere, like the +/- stepper on the unit-quantity variant of this form).
        guard !uiView.isFirstResponder else { return }
        uiView.text = Self.formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TrailingCursorNumberField

        init(_ parent: TrailingCursorNumberField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            // A partial in-progress value (e.g. "3." while typing "3.5") won't parse yet —
            // leave the bound value as-is rather than snapping it to 0 mid-edit.
            guard let text = textField.text,
                  let number = TrailingCursorNumberField.formatter.number(from: text) else { return }
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
