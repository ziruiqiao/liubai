#if DEBUG
import AppKit
import LiuBaiCore
import SwiftUI
import Observation
import os

@MainActor
enum NativeChecks {
    static func run(store: AppStore) throws {
        let originalTheme = ThemeManager.shared.selectedID
        defer { ThemeManager.shared.select(originalTheme) }
        let notified = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = Palette.accent } onChange: { notified.withLock { $0 = true } }
        ThemeManager.shared.select(originalTheme == "iris" ? "indigo" : "iris")
        try expect(notified.withLock { $0 }, "Palette reads must invalidate live views when switching themes")
        ThemeManager.shared.select(originalTheme)
        print("PASS: theme changes invalidate observed palette reads")
        try store.checkBreakMusicResumption()
        print("PASS: break music waits for actual focus start, independently for short and long breaks")
        let original = store.data
        defer { store.data = original; store.saveNow() }
        store.data = AppData()
        store.updateIntention("当前专注目标")
        store.toggleTimer()
        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        store.toggleTimer()
        store.resetTimer()
        store.updateIntention("下一轮目标")
        let saved = try store.fileStore.load()
        try expect(saved.focusBlocks?.count == 1 && saved.focusBlocks?.first?.intention == "当前专注目标"
                   && (saved.focusBlocks?.first?.focusSeconds ?? 0) > 0 && saved.focusBlocks?.first?.completed == false,
                   "Timer actions must save the current goal with its partial focus block")
        print("PASS: native timer actions persist the focus goal")
        try checkInput(store: store)
        try checkWindows()
    }

    private static func checkInput(store: AppStore) throws {
        store.data.journal = [:]
        let date = Date()
        let hosting = NSHostingView(rootView: JournalView().environmentObject(store).foregroundStyle(Palette.text))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1000, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        refresh(hosting)
        guard let editor = descendant(of: hosting, matching: { $0.identifier?.rawValue == "手记正文" }) as? CompositionTextView else {
            throw failure("The real journal editor must be present")
        }
        window.makeFirstResponder(editor)
        editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let previousTheme = ThemeManager.shared.selectedID
        ThemeManager.shared.select(previousTheme == "iris" ? "indigo" : "iris")
        store.saveNow(); refresh(hosting, delay: 0.65)
        ThemeManager.shared.select(previousTheme)
        try expect(editor.hasMarkedText() && editor.string == "ni" && store.entry(for: date).body.isEmpty,
                   "Autosave must retain the native composition buffer without saving unconfirmed pinyin")
        editor.setMarkedText("ni hao", selectedRange: NSRange(location: 6, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        store.saveNow(); refresh(hosting, delay: 0.65)
        try expect(editor.hasMarkedText() && editor.string == "ni hao", "Slow composition must survive multiple save intervals")
        editor.insertText("你好，慢慢记录。", replacementRange: NSRange(location: NSNotFound, length: 0))
        store.saveNow(); refresh(hosting)
        let body = try store.fileStore.load().journal[DayKey.string(for: date)]?.body
        try expect(!editor.hasMarkedText() && body == "你好，慢慢记录。", "Confirmed Chinese text must persist immediately")
        let selection = editor.selectedRange()
        store.saveNow(); refresh(hosting)
        try expect(editor.selectedRange() == selection, "Saving unchanged text must not move the insertion point")

        guard let title = descendant(of: hosting, matching: { $0.identifier?.rawValue == "手记标题" }) as? NSTextField else {
            throw failure("The real journal title field must be present")
        }
        window.makeFirstResponder(title)
        guard let fieldEditor = title.currentEditor() as? NSTextView else { throw failure("Title field editor unavailable") }
        fieldEditor.setMarkedText("ri ji", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        store.saveNow(); refresh(hosting, delay: 0.65)
        try expect(fieldEditor.hasMarkedText(), "Title autosave must also retain Chinese composition")
        fieldEditor.insertText("日记", replacementRange: NSRange(location: NSNotFound, length: 0))
        window.makeFirstResponder(nil)
        store.saveNow(); refresh(hosting)
        let savedTitle = try store.fileStore.load().journal[DayKey.string(for: date)]?.title
        try expect(savedTitle == "日记", "Confirmed Chinese title must persist")
        print("PASS: native Chinese composition, slow autosave, commit, and cursor preservation")
    }

    private static func checkWindows() throws {
        var creations = 0
        var main: NSWindow?
        func create() {
            creations += 1
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 260), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            MainWindowPresenter.register(window)
            main = window
            window.orderFront(nil)
        }
        defer { main?.close() }
        MainWindowPresenter.open(create: create)
        let first = main
        for _ in 0..<8 { MainWindowPresenter.open(create: create) }
        try expect(creations == 1 && main === first, "Repeated menu actions must reuse the same main window")
        main?.miniaturize(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        MainWindowPresenter.open(create: create)
        try expect(main?.isMiniaturized == false && creations == 1, "Opening must restore the minimized main window")
        main?.close()
        MainWindowPresenter.open(create: create)
        try expect(creations == 2 && main !== first, "A closed main window must be recreated once")
        try expect(NSApp.windows.filter { $0.identifier == MainWindowPresenter.identifier }.count == 1,
                   "Only one registered main window may remain")
        print("PASS: native window reuse, minimized restore, and recreate after close")
    }

    private static func refresh(_ hosting: NSView, delay: TimeInterval = 0.1) {
        RunLoop.current.run(until: Date().addingTimeInterval(delay))
        hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
    }
    private static func descendant(of view: NSView, matching predicate: (NSView) -> Bool) -> NSView? {
        if predicate(view) { return view }
        for child in view.subviews { if let match = descendant(of: child, matching: predicate) { return match } }
        return nil
    }
    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw failure(message) }
    }
    private static func failure(_ message: String) -> Error {
        NSError(domain: "NativeChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif
