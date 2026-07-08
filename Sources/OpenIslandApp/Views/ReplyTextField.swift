import SwiftUI

struct ReplyTextField: View {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    @State private var isFocused = false

    var body: some View {
        _ReplyTextFieldRepresentable(placeholder: placeholder, text: $text, onSubmit: onSubmit, isFocused: $isFocused)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(V6Palette.paper.opacity(0.32))
                    .frame(height: 1)
                    .opacity(isFocused ? 1 : 0)
                    .animation(.easeInOut(duration: 0.18), value: isFocused)
            }
    }
}

private struct _ReplyTextFieldRepresentable: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void
    @Binding var isFocused: Bool

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 13),
            ]
        )
        field.delegate = context.coordinator
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.isFocused = $isFocused
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, isFocused: $isFocused)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var isFocused: Binding<Bool>

        init(text: Binding<String>, onSubmit: @escaping () -> Void, isFocused: Binding<Bool>) {
            self.text = text
            self.onSubmit = onSubmit
            self.isFocused = isFocused
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isFocused.wrappedValue = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            isFocused.wrappedValue = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Let AppKit handle Enter during IME composition (e.g. confirming
                // a Chinese/Japanese candidate). Only submit when no marked text.
                guard !textView.hasMarkedText() else { return false }
                onSubmit()
                return true
            }
            return false
        }
    }
}
