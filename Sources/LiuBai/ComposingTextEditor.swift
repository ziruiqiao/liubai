import AppKit
import SwiftUI

/// Keep the native marked-text buffer independent of published app updates.
/// Only confirmed text reaches the binding and the autosave queue.
struct ComposingTextEditor: NSViewRepresentable {
    @Binding var text: String
    let documentID: String
    var fontSize: CGFloat = 13
    var lineSpacing: CGFloat = 8
    var inset = NSSize(width: 5, height: 8)
    var accessibilityLabel = "手记正文"
    var placeholder = ""

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let editor = CompositionTextView(frame: .zero)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = inset
        editor.font = NSFont.systemFont(ofSize: fontSize)
        editor.textColor = NSColor(Palette.text)
        editor.insertionPointColor = NSColor(Palette.accent)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = lineSpacing
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor(Palette.text), .paragraphStyle: paragraph]
        editor.string = text
        editor.placeholder = placeholder
        editor.setAccessibilityLabel(accessibilityLabel)
        editor.identifier = NSUserInterfaceItemIdentifier(accessibilityLabel)
        editor.delegate = context.coordinator
        editor.onCompositionEnded = { [weak coordinator = context.coordinator] editor in coordinator?.publish(editor) }
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? CompositionTextView else { return }
        let coordinator = context.coordinator
        if coordinator.parent.documentID != documentID {
            // Finish the old document through its old, date-specific binding.
            coordinator.isUpdatingView = true
            editor.unmarkText()
            coordinator.publishLater(editor.string)
            coordinator.parent = self
            editor.string = text
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            editor.undoManager?.removeAllActions()
            coordinator.isUpdatingView = false
            return
        }
        coordinator.parent = self
        guard !editor.hasMarkedText(), editor.string != text else { return }
        let selection = editor.selectedRange()
        editor.string = text
        let location = min(selection.location, (text as NSString).length)
        editor.setSelectedRange(NSRange(location: location, length: 0))
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let editor = scroll.documentView as? CompositionTextView else { return }
        coordinator.isUpdatingView = true
        editor.unmarkText()
        coordinator.publishLater(editor.string)
        editor.delegate = nil
        editor.onCompositionEnded = nil
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposingTextEditor
        var isUpdatingView = false
        init(_ parent: ComposingTextEditor) { self.parent = parent }
        func publish(_ editor: NSTextView) {
            guard !isUpdatingView, !editor.hasMarkedText(), parent.text != editor.string else { return }
            parent.text = editor.string
        }
        func publishLater(_ value: String) {
            let binding = parent.$text
            guard binding.wrappedValue != value else { return }
            DispatchQueue.main.async { binding.wrappedValue = value }
        }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { publish(editor) }
        }
        func textDidEndEditing(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { publish(editor) }
        }
    }
}

final class CompositionTextView: NSTextView {
    var placeholder = ""
    var onCompositionEnded: ((NSTextView) -> Void)?
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, !placeholder.isEmpty {
            (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height),
                                          withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(Palette.secondary).withAlphaComponent(0.65)])
        }
    }
    override func unmarkText() {
        super.unmarkText()
        onCompositionEnded?(self)
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        if !hasMarkedText() { onCompositionEnded?(self) }
    }
}

struct ComposingTextField: NSViewRepresentable {
    @Binding var text: String
    let documentID: String
    var placeholder = ""

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 24, weight: .medium)
        field.textColor = NSColor(Palette.text)
        field.placeholderString = placeholder
        field.stringValue = text
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("手记标题")
        field.identifier = NSUserInterfaceItemIdentifier("手记标题")
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        if coordinator.parent.documentID != documentID {
            coordinator.isUpdatingView = true
            (field.currentEditor() as? NSTextView)?.unmarkText()
            coordinator.publishLater(field.stringValue)
            coordinator.parent = self
            field.stringValue = text
            field.undoManager?.removeAllActions()
            coordinator.isUpdatingView = false
            return
        }
        coordinator.parent = self
        guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        if field.stringValue != text { field.stringValue = text }
    }
    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.isUpdatingView = true
        (field.currentEditor() as? NSTextView)?.unmarkText()
        coordinator.publishLater(field.stringValue)
        field.delegate = nil
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ComposingTextField
        var isUpdatingView = false
        init(_ parent: ComposingTextField) { self.parent = parent }
        func publish(_ notification: Notification) {
            guard !isUpdatingView, let field = notification.object as? NSTextField,
                  (field.currentEditor() as? NSTextView)?.hasMarkedText() != true,
                  parent.text != field.stringValue else { return }
            parent.text = field.stringValue
        }
        func publishLater(_ value: String) {
            let binding = parent.$text
            guard binding.wrappedValue != value else { return }
            DispatchQueue.main.async { binding.wrappedValue = value }
        }
        func controlTextDidChange(_ notification: Notification) { publish(notification) }
        func controlTextDidEndEditing(_ notification: Notification) { publish(notification) }
    }
}
