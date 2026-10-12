import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The memo editor shared by the overlay and the Option+E preview (#27). The text is the Markdown
/// source; `MarkdownLiveStyle` runs restyle it so it reads like the rendered memo. The caret line(s)
/// show their raw source; every other line hides its markers and draws bullets, checkboxes and rules.
/// With `editable` off it is a reader: nothing reveals, checkboxes and links still work.
struct LiveMarkdownEditor: NSViewRepresentable {
    var text: String
    /// Bump to push `text` into the view (a different desktop, or the file changed outside).
    var version: Int
    var editable: Bool
    var canToggleTasks: Bool
    /// First visible line. The view reports scrolling through `onScroll`; a different value scrolls it.
    var scrollLine: Int
    /// Bump to put the caret in the editor (Option+E's D).
    var focusRequest = 0
    /// The memo folder: relative image paths resolve against it, dropped images are copied into it (#21).
    var baseDirectory: URL?
    var onTextChange: (String) -> Void = { _ in }
    /// Right before a click places the caret: borrow the keyboard (`FocusReturner`).
    var onWantsFocus: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }
    /// Esc or ⌘Enter.
    var onDone: () -> Void = {}
    var onScroll: (Int) -> Void = { _ in }
    /// Checkbox clicked while the editor isn't editable: the owner flips that line in the file.
    var onToggleTask: (Int) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, textView) = Self.makeScrollView()
        context.coordinator.attach(textView, scroll: scroll)
        return scroll
    }

    static func makeScrollView() -> (NSScrollView, LiveMarkdownTextView) {
        let textView = LiveMarkdownTextView.make()
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = textView
        scroll.contentView.postsBoundsChangedNotifications = true
        return (scroll, textView)
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? LiveMarkdownTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        // Fill the visible height so a click below the last line (or in an empty memo) still lands.
        textView.minSize = CGSize(width: 0, height: scroll.contentSize.height)
        textView.isEditable = editable
        if textView.baseURL != baseDirectory {
            textView.baseURL = baseDirectory
            textView.restyle(force: true)
        }
        textView.canToggleTasks = canToggleTasks
        textView.onWantsFocus = { [weak coordinator] in coordinator?.parent?.onWantsFocus() }
        textView.onFocusChange = { [weak coordinator] in coordinator?.parent?.onFocusChange($0) }
        textView.onDone = { [weak coordinator] in coordinator?.parent?.onDone() }
        textView.onTextChange = { [weak coordinator] in coordinator?.parent?.onTextChange($0) }
        textView.onToggleTaskOutside = { [weak coordinator] in coordinator?.parent?.onToggleTask($0) }

        if coordinator.version != version {
            coordinator.version = version
            textView.setSource(text)
            coordinator.scroll(to: scrollLine, animated: false)
        } else if scrollLine != coordinator.reportedLine {
            coordinator.scroll(to: scrollLine, animated: true)
        }
        if coordinator.focusRequest != focusRequest {
            coordinator.focusRequest = focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
            }
        }
        if !editable, textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
    }

    final class Coordinator {
        var parent: LiveMarkdownEditor?
        var version = -1
        var focusRequest = 0
        var reportedLine = 0
        private weak var textView: LiveMarkdownTextView?
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?
        private var restoring = false

        func attach(_ textView: LiveMarkdownTextView, scroll: NSScrollView) {
            self.textView = textView
            scrollView = scroll
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                              object: scroll.contentView, queue: .main) { [weak self] _ in
                self?.boundsChanged()
            }
        }

        deinit { observer.map(NotificationCenter.default.removeObserver) }

        func scroll(to line: Int, animated: Bool) {
            reportedLine = line
            DispatchQueue.main.async { [weak self] in
                guard let self, let textView, let scrollView else { return }
                let y = textView.top(ofLine: line)
                let clip = scrollView.contentView
                let maxY = max(0, textView.frame.height - clip.bounds.height)
                let target = CGPoint(x: 0, y: min(max(0, y), maxY))
                restoring = true
                if animated {
                    NSAnimationContext.runAnimationGroup({ $0.duration = 0.12; clip.animator().setBoundsOrigin(target) },
                                                         completionHandler: { [weak self] in
                        scrollView.reflectScrolledClipView(clip)
                        self?.restoring = false
                    })
                } else {
                    clip.setBoundsOrigin(target)
                    scrollView.reflectScrolledClipView(clip)
                    restoring = false
                }
            }
        }

        private func boundsChanged() {
            guard !restoring, let textView, let scrollView else { return }
            let line = textView.line(atY: scrollView.contentView.bounds.minY)
            guard line != reportedLine else { return }
            reportedLine = line
            parent?.onScroll(line)
        }
    }
}

// MARK: - text view

final class LiveMarkdownTextView: NSTextView {
    var canToggleTasks = true
    var onWantsFocus: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }
    var onDone: () -> Void = {}
    var onTextChange: (String) -> Void = { _ in }
    var onToggleTaskOutside: (Int) -> Void = { _ in }
    /// Memo folder for images (#21).
    var baseURL: URL?
    private var imageObserver: NSObjectProtocol?

    private var revealed: ClosedRange<Int>?

    static func make() -> LiveMarkdownTextView {
        let storage = NSTextStorage()
        let layout = LiveMarkdownLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let view = LiveMarkdownTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), textContainer: container)
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        // Without this the document never grows past its first size, so a long memo put in by code
        // (not typed) had nothing to scroll (#28).
        view.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainerInset = CGSize(width: 0, height: 2)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.typingAttributes = LiveStyleApplier.baseAttributes
        view.registerForDraggedTypes([.fileURL, .png, .tiff])
        // A remote image finished loading: draw it.
        view.imageObserver = NotificationCenter.default.addObserver(forName: LiveImageCache.didLoad, object: nil, queue: .main) { [weak view] _ in
            guard let view, view.string.contains("![") else { return }
            view.restyle(force: true)
        }
        return view
    }

    /// Replaces the whole text (no undo step), keeping the caret where it was if possible.
    func setSource(_ text: String) {
        guard text != string else { restyle(force: true); return }
        let caret = selectedRange()
        textStorage?.setAttributedString(NSAttributedString(string: text, attributes: LiveStyleApplier.baseAttributes))
        let length = (text as NSString).length
        setSelectedRange(NSRange(location: min(caret.location, length), length: 0))
        undoManager?.removeAllActions(withTarget: textStorage as Any)
        restyle(force: true)
    }

    // MARK: styling

    private var isRevealing: Bool { isEditable && window?.firstResponder === self }

    /// AppKit hides the caret while the app is inactive. The overlay is a non-activating panel that
    /// still takes typing when macOS refuses our activation (cooperative activation, macOS 14+), which
    /// left typing with no visible caret; draw it whenever this editor really has the keyboard.
    override var shouldDrawInsertionPoint: Bool {
        super.shouldDrawInsertionPoint
            || (isEditable && window?.isKeyWindow == true && window?.firstResponder === self && selectedRange().length == 0)
    }

    func restyle(force: Bool = false) {
        guard let storage = textStorage, !hasMarkedText() else { return }
        let caretLines = isRevealing
            ? MarkdownLiveStyle.expand(MarkdownLiveStyle.lines(touching: selectedRange(), in: string), in: string) : nil
        guard force || caretLines != revealed else { return }
        revealed = caretLines
        LiveStyleApplier.apply(to: storage, revealing: caretLines, width: textContainer?.size.width ?? 0, base: baseURL)
        typingAttributes = LiveStyleApplier.baseAttributes
        let all = NSRange(location: 0, length: storage.length)
        layoutManager?.invalidateGlyphs(forCharacterRange: all, changeInLength: 0, actualCharacterRange: nil)
        layoutManager?.invalidateLayout(forCharacterRange: all, actualCharacterRange: nil)
        fitHeight()
        needsDisplay = true
        // The caret line was just re-laid out (markers shown or hidden); put the caret where it now is.
        if window?.firstResponder === self { updateInsertionPointStateAndRestartTimer(true) }
    }

    /// Grows (or shrinks) the document to its text so the scroll view knows what there is to scroll
    /// (#28). Typing does this by itself; text and styles set by code do not.
    func fitHeight() {
        guard let layout = layoutManager, let container = textContainer else { return }
        layout.ensureLayout(for: container)
        sizeToFit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged, string.contains("|") {
            DispatchQueue.main.async { [weak self] in self?.restyle(force: true) }   // tables fit the new width
        }
    }

    override func didChangeText() {
        super.didChangeText()
        restyle(force: true)
        onTextChange(string)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting { restyle() }
    }


    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { restyle(force: true); onFocusChange(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            revealed = nil
            DispatchQueue.main.async { [weak self] in self?.restyle(force: true) }
            onFocusChange(false)
        }
        return ok
    }

    // MARK: input

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let url = imageHit(at: point) {
            NSWorkspace.shared.open(url)   // a drawn image opens in its default app (#21)
            return
        }
        if let hit = renderedHit(at: point) {
            switch hit {
            case .task(let line):
                if canToggleTasks { toggleTask(line: line) }
                return
            case .link(let url):
                if let url = URL(string: url) { NSWorkspace.shared.open(url) }
                return
            }
        }
        if isEditable {
            onWantsFocus()
        }
        super.mouseDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onDone()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.command) {   // ⌘Enter
            onDone()
            return
        }
        if handleShortcut(event) { return }
        super.keyDown(with: event)
    }

    // MARK: editing shortcuts (#21)

    /// ⌘ keys come here before `keyDown`; take ours while this editor has the keyboard.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, handleShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Physical keys, so they work with any input source (a Korean layout reports jamo for ⌘B).
    private enum ShortcutKey {
        static let b: UInt16 = 11, i: UInt16 = 34, e: UInt16 = 14, k: UInt16 = 40, l: UInt16 = 37
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard isEditable, !hasMarkedText(),
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return false }
        let text = string, selection = selectedRange()
        switch event.keyCode {
        case ShortcutKey.b: apply(MarkdownEditing.toggleWrap("**", text: text, selection: selection))
        case ShortcutKey.i: apply(MarkdownEditing.toggleWrap("*", text: text, selection: selection))
        case ShortcutKey.e: apply(MarkdownEditing.toggleWrap("`", text: text, selection: selection))
        case ShortcutKey.k: apply(MarkdownEditing.link(text: text, selection: selection))
        case ShortcutKey.l: apply(MarkdownEditing.toggleTask(text: text, selection: selection))
        default: return false
        }
        return true
    }

    override func insertNewline(_ sender: Any?) {
        if isEditable, !hasMarkedText(), let r = MarkdownEditing.newline(text: string, selection: selectedRange()) {
            apply(r)
        } else {
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        if isEditable, !hasMarkedText(), let r = MarkdownEditing.indent(text: string, selection: selectedRange(), outdent: false) {
            apply(r)
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if isEditable, !hasMarkedText(), let r = MarkdownEditing.indent(text: string, selection: selectedRange(), outdent: true) {
            apply(r)
        } else {
            super.insertBacktab(sender)
        }
    }

    /// One undoable edit.
    func apply(_ r: MarkdownEditing.Replacement) {
        guard shouldChangeText(in: r.range, replacementString: r.string) else { return }
        textStorage?.replaceCharacters(in: r.range, with: r.string)
        didChangeText()
        setSelectedRange(r.selection)
    }

    // MARK: line-end moves (#29)

    override func moveToRightEndOfLine(_ sender: Any?) { keepOnLine(towardEnd: true, extending: false) { super.moveToRightEndOfLine(sender) } }
    override func moveToEndOfLine(_ sender: Any?) { keepOnLine(towardEnd: true, extending: false) { super.moveToEndOfLine(sender) } }
    override func moveToLeftEndOfLine(_ sender: Any?) { keepOnLine(towardEnd: false, extending: false) { super.moveToLeftEndOfLine(sender) } }
    override func moveToBeginningOfLine(_ sender: Any?) { keepOnLine(towardEnd: false, extending: false) { super.moveToBeginningOfLine(sender) } }
    override func moveToRightEndOfLineAndModifySelection(_ sender: Any?) {
        keepOnLine(towardEnd: true, extending: true) { super.moveToRightEndOfLineAndModifySelection(sender) }
    }
    override func moveToEndOfLineAndModifySelection(_ sender: Any?) {
        keepOnLine(towardEnd: true, extending: true) { super.moveToEndOfLineAndModifySelection(sender) }
    }
    override func moveToLeftEndOfLineAndModifySelection(_ sender: Any?) {
        keepOnLine(towardEnd: false, extending: true) { super.moveToLeftEndOfLineAndModifySelection(sender) }
    }
    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) {
        keepOnLine(towardEnd: false, extending: true) { super.moveToBeginningOfLineAndModifySelection(sender) }
    }

    /// Runs the stock move (which keeps wrapped-line behavior), then pulls the moving end back onto
    /// the line it started on: hidden markers of the next line belong to this line's last fragment.
    private func keepOnLine(towardEnd: Bool, extending: Bool, _ move: () -> Void) {
        let before = selectedRange()
        move()
        let after = selectedRange()
        let from = towardEnd ? NSMaxRange(before) : before.location
        let moved = towardEnd ? NSMaxRange(after) : after.location
        let target = MarkdownLiveStyle.clamp(moved, from: from, towardEnd: towardEnd, in: string)
        guard target != moved else { return }
        if !extending {
            setSelectedRange(NSRange(location: target, length: 0))
        } else if towardEnd {
            setSelectedRange(NSRange(location: after.location, length: max(0, target - after.location)))
        } else {
            setSelectedRange(NSRange(location: target, length: max(0, NSMaxRange(after) - target)))
        }
    }

    private enum Hit { case task(Int), link(String) }

    // MARK: images (#21)

    /// A drawn image under the pointer.
    private func imageHit(at point: CGPoint) -> URL? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let p = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let index = layout.characterIndex(for: p, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < storage.length, let url = storage.attribute(.liveImageURL, at: index, effectiveRange: nil) as? URL,
              let drawing = storage.attribute(.liveDrawing, at: index, effectiveRange: nil) as? LiveDrawing else { return nil }
        let fragment = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: index), effectiveRange: nil)
        return CGRect(origin: fragment.origin, size: drawing.size).contains(p) ? url : nil
    }

    private var canInsertImages: Bool { isEditable && baseURL != nil }

    private func imageFiles(_ pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .image) == true }
    }

    override func dragOperation(for dragInfo: NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        if canInsertImages, !imageFiles(dragInfo.draggingPasteboard).isEmpty { return .copy }
        return super.dragOperation(for: dragInfo, type: type)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = imageFiles(sender.draggingPasteboard)
        guard canInsertImages, !files.isEmpty else { return super.performDragOperation(sender) }
        insertImageFiles(files, at: characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil)))
        return true
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if canInsertImages {
            let files = imageFiles(pasteboard)
            if !files.isEmpty {
                insertImageFiles(files, at: selectedRange().location)
                return
            }
            // Image data without text (a screenshot, an image copied in a browser): save it as a PNG.
            if pasteboard.string(forType: .string) == nil, let image = NSImage(pasteboard: pasteboard),
               let path = saveIntoMemoFolder(image) {
                insertImages([path], at: selectedRange().location)
                return
            }
        }
        super.paste(sender)
    }

    /// Dropped or pasted image files: copied into the memo folder, one `![](…)` line each.
    func insertImageFiles(_ files: [URL], at index: Int) {
        insertImages(files.compactMap(copyIntoMemoFolder), at: index)
    }

    /// Copies a dropped file into `images/` (a file already in the memo folder is used where it is);
    /// returns its path relative to the memo folder.
    private func copyIntoMemoFolder(_ file: URL) -> String? {
        guard let base = baseURL?.standardizedFileURL else { return nil }
        let source = file.standardizedFileURL
        if source.path.hasPrefix(base.path + "/") { return String(source.path.dropFirst(base.path.count + 1)) }
        let folder = base.appendingPathComponent(MarkdownImages.folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let name = MarkdownImages.fileName(original: source.lastPathComponent, taken: taken)
        do { try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name)) } catch { return nil }
        return MarkdownImages.folder + "/" + name
    }

    private func saveIntoMemoFolder(_ image: NSImage) -> String? {
        guard let base = baseURL, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let folder = base.appendingPathComponent(MarkdownImages.folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let name = MarkdownImages.fileName(original: nil, taken: taken)
        do { try png.write(to: folder.appendingPathComponent(name)) } catch { return nil }
        return MarkdownImages.folder + "/" + name
    }

    /// Each image on its own line at `index`.
    private func insertImages(_ paths: [String], at index: Int) {
        guard !paths.isEmpty else { return }
        let s = string as NSString
        let at = min(index, s.length)
        var text = paths.map(MarkdownImages.markdown).joined(separator: "\n")
        if at > 0, s.character(at: at - 1) != 10 { text = "\n" + text }
        if at < s.length, s.character(at: at) != 10 { text += "\n" }
        let caret = at + (text as NSString).length
        apply(MarkdownEditing.Replacement(range: NSRange(location: at, length: 0), string: text, selection: NSRange(location: caret, length: 0)))
    }

    /// A checkbox or link drawn on a rendered (not caret) line under the pointer.
    private func renderedHit(at point: CGPoint) -> Hit? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let p = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: p, in: container, fractionOfDistanceThroughGlyph: &fraction)
        let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard rect.insetBy(dx: -2, dy: 0).contains(p) else { return nil }
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return nil }
        if let decoration = storage.attribute(.liveDecoration, at: index, effectiveRange: nil) as? String,
           decoration == LiveStyleApplier.Decoration.task || decoration == LiveStyleApplier.Decoration.taskDone {
            return .task(MarkdownLiveStyle.line(at: index, in: string))
        }
        if let url = storage.attribute(.liveLink, at: index, effectiveRange: nil) as? String {
            return .link(url)
        }
        return nil
    }

    private func toggleTask(line: Int) {
        guard isEditable else { onToggleTaskOutside(line); return }
        let toggled = MarkdownBlocks.toggleTask(in: string, line: line)
        guard toggled != string else { return }
        let start = MarkdownLiveStyle.lineStart(line, in: string)
        let oldLine = (string as NSString).lineRange(for: NSRange(location: start, length: 0))
        let newStart = MarkdownLiveStyle.lineStart(line, in: toggled)
        let newLine = (toggled as NSString).lineRange(for: NSRange(location: newStart, length: 0))
        let replacement = (toggled as NSString).substring(with: newLine)
        if shouldChangeText(in: oldLine, replacementString: replacement) {
            textStorage?.replaceCharacters(in: oldLine, with: replacement)
            didChangeText()
        }
    }

    // MARK: scrolling helpers

    func top(ofLine line: Int) -> CGFloat {
        guard let layout = layoutManager, let container = textContainer else { return 0 }
        let start = MarkdownLiveStyle.lineStart(line, in: string)
        guard start < (string as NSString).length else {
            return layout.usedRect(for: container).maxY + textContainerOrigin.y
        }
        let glyph = layout.glyphIndexForCharacter(at: start)
        return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + textContainerOrigin.y
    }

    func line(atY y: CGFloat) -> Int {
        guard let layout = layoutManager, let container = textContainer, (string as NSString).length > 0 else { return 0 }
        let glyph = layout.glyphIndex(for: CGPoint(x: 0, y: y - textContainerOrigin.y + 1), in: container)
        return MarkdownLiveStyle.line(at: layout.characterIndexForGlyph(at: glyph), in: string)
    }
}

// MARK: - styling

extension NSAttributedString.Key {
    /// Characters drawn as nothing (null glyphs): markers away from the caret line.
    static let liveHidden = NSAttributedString.Key("SpaceSwitcher.liveHidden")
    /// Something the layout manager draws over the characters (bullet, checkbox, rule).
    static let liveDecoration = NSAttributedString.Key("SpaceSwitcher.liveDecoration")
    /// Background drawn across the whole line (quote bar, code block).
    static let liveBlock = NSAttributedString.Key("SpaceSwitcher.liveBlock")
    static let liveLink = NSAttributedString.Key("SpaceSwitcher.liveLink")
    /// A `LiveDrawing` drawn in the (enlarged) line fragment of the character it is on: tables, images.
    static let liveDrawing = NSAttributedString.Key("SpaceSwitcher.liveDrawing")
    /// The file or web address of a drawn image (click opens it).
    static let liveImageURL = NSAttributedString.Key("SpaceSwitcher.liveImageURL")
}

enum LiveStyleApplier {
    enum Decoration {
        static let bullet = "bullet", task = "task", taskDone = "taskDone", rule = "rule"
    }
    enum Block {
        static let quote = "quote", code = "code"
    }

    static let fontSize: CGFloat = 12
    /// Markers on the caret line: clearly readable, just quieter than the text.
    static let markerColor = NSColor.secondaryLabelColor
    static let baseFont = NSFont.systemFont(ofSize: fontSize)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: fontSize - 0.5, weight: .regular)

    static var baseParagraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacing = 3
        p.lineSpacing = 1
        return p
    }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: baseParagraph]
    }

    static func apply(to storage: NSTextStorage, revealing caretLines: ClosedRange<Int>?, width: CGFloat = 0, base: URL? = nil) {
        let text = storage.string
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: all)
        for run in MarkdownLiveStyle.runs(in: text) {
            let raw = caretLines?.contains(run.line) ?? false
            style(run, raw: raw, in: storage)
        }
        for table in MarkdownTables.find(in: text) where !(caretLines?.overlaps(table.lines) ?? false) {
            drawTable(table, in: storage, width: width)
        }
        for image in MarkdownImages.find(in: text) where !(caretLines?.contains(image.line) ?? false) {
            drawImage(image, in: storage, width: width, base: base)
        }
        storage.endEditing()
    }

    /// The image's line becomes as tall as the image and carries the drawing; its text shrinks to
    /// nothing (kept, not hidden, so it stays on this line's fragment). A missing image keeps its
    /// source visible so the broken path can be fixed.
    private static func drawImage(_ image: MarkdownImage, in storage: NSTextStorage, width: CGFloat, base: URL?) {
        guard let url = MarkdownImages.resolve(image.source, base: base) else { return }
        let drawing: LiveDrawing
        switch LiveImageCache.shared.state(for: url) {
        case .loaded(let picture):
            drawing = LiveImageDrawing(picture, size: MarkdownImages.displaySize(natural: picture.size, width: max(width, 1)))
        case .loading:
            drawing = LiveImagePlaceholder("이미지 불러오는 중…")
        case .failed:
            return
        }
        let s = storage.string as NSString
        let start = MarkdownLiveStyle.lineStart(image.line, in: storage.string)
        let line = s.lineRange(for: NSRange(location: start, length: 0))
        var content = line
        if content.length > 0, s.character(at: NSMaxRange(content) - 1) == 10 { content.length -= 1 }
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = drawing.size.height
        p.maximumLineHeight = drawing.size.height
        p.paragraphSpacing = 4
        storage.addAttribute(.paragraphStyle, value: p, range: line)
        storage.addAttributes([.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear,
                               .liveImageURL: url], range: content)
        storage.removeAttribute(.liveHidden, range: content)
        storage.addAttribute(.liveDrawing, value: drawing, range: NSRange(location: content.location, length: 1))
    }

    /// The table's first line grows to the drawn table's height and carries the drawing; the other
    /// lines fold to nothing. Their text is hidden by the `.table` runs.
    private static func drawTable(_ table: MarkdownTable, in storage: NSTextStorage, width: CGFloat) {
        let s = storage.string as NSString
        let drawing = LiveTableDrawing(table, source: storage.string, width: width)
        for line in table.lines {
            let start = MarkdownLiveStyle.lineStart(line, in: storage.string)
            let range = s.lineRange(for: NSRange(location: start, length: 0))
            let p = NSMutableParagraphStyle()
            if line == table.lines.lowerBound {
                p.minimumLineHeight = drawing.size.height
                p.maximumLineHeight = drawing.size.height
                p.paragraphSpacing = 4
                // On the line's last character (its newline): hidden characters at a line start are laid
                // out at the end of the previous line fragment, which would draw the table a line up.
                storage.addAttribute(.liveDrawing, value: drawing, range: NSRange(location: NSMaxRange(range) - 1, length: 1))
            } else {
                p.minimumLineHeight = 0.01
                p.maximumLineHeight = 0.01
            }
            storage.addAttribute(.paragraphStyle, value: p, range: range)
        }
    }

    private static func style(_ run: LiveStyleRun, raw: Bool, in storage: NSTextStorage) {
        let r = run.range
        func font(_ transform: (NSFont) -> NSFont) {
            storage.enumerateAttribute(.font, in: r) { value, sub, _ in
                storage.addAttribute(.font, value: transform((value as? NSFont) ?? baseFont), range: sub)
            }
        }
        switch run.kind {
        case .syntax:
            if raw {
                storage.addAttribute(.foregroundColor, value: LiveStyleApplier.markerColor, range: r)
            } else {
                storage.addAttribute(.liveHidden, value: true, range: r)
            }
        case .heading(let level):
            let size: CGFloat = level == 1 ? 16 : level == 2 ? 14 : 13
            let weight: NSFont.Weight = level == 1 ? .bold : .semibold
            // The whole line, markers included, so a revealed "## " matches the text's size.
            let line = (storage.string as NSString).lineRange(for: r)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: weight), range: line)
        case .bold:
            font { NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask) }
        case .italic:
            font { NSFontManager.shared.convert($0, toHaveTrait: .italicFontMask) }
        case .code:
            storage.addAttributes([.font: codeFont, .backgroundColor: NSColor.labelColor.withAlphaComponent(0.08)], range: r)
        case .strike:
            storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                   .foregroundColor: NSColor.secondaryLabelColor], range: r)
        case .link(let url):
            storage.addAttributes([.foregroundColor: NSColor.linkColor, .liveLink: url], range: r)
            if raw { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
        case .bullet:
            if raw {
                storage.addAttribute(.foregroundColor, value: LiveStyleApplier.markerColor, range: r)
            } else {
                storage.addAttributes([.foregroundColor: NSColor.clear, .liveDecoration: Decoration.bullet], range: r)
            }
        case .task(let checked):
            if raw {
                storage.addAttribute(.foregroundColor, value: LiveStyleApplier.markerColor, range: r)
            } else {
                storage.addAttributes([.foregroundColor: NSColor.clear,
                                       .liveDecoration: checked ? Decoration.taskDone : Decoration.task], range: r)
            }
        case .done:
            storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor,
                                   .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: r)
        case .quote:
            let line = (storage.string as NSString).lineRange(for: r)
            let p = baseParagraph.mutableCopy() as! NSMutableParagraphStyle
            p.firstLineHeadIndent = 10
            p.headIndent = 10
            storage.addAttributes([.paragraphStyle: p, .liveBlock: Block.quote], range: line)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
        case .fence:
            let line = (storage.string as NSString).lineRange(for: r)
            storage.addAttributes([.font: codeFont, .liveBlock: Block.code], range: line)
            if raw {
                storage.addAttribute(.foregroundColor, value: LiveStyleApplier.markerColor, range: r)
            } else {
                storage.addAttribute(.liveHidden, value: true, range: r)   // an empty band above/below the code
            }
        case .fenceInfo:
            storage.addAttribute(.font, value: codeFont, range: r)
            if raw {
                storage.addAttribute(.foregroundColor, value: LiveStyleApplier.markerColor, range: r)
            } else {
                storage.addAttribute(.liveHidden, value: true, range: r)   // as in Markdown: the info string isn't shown
            }
        case .codeBlock:
            let line = (storage.string as NSString).lineRange(for: r)
            storage.addAttributes([.font: codeFont, .liveBlock: Block.code], range: line)
        case .table:
            if !raw { storage.addAttribute(.liveHidden, value: true, range: r) }
        case .image:
            break   // drawn (or left as source) by drawImage
        case .rule:
            if raw {
                storage.addAttribute(.foregroundColor, value: LiveStyleApplier.markerColor, range: r)
            } else {
                storage.addAttributes([.foregroundColor: NSColor.clear, .liveDecoration: Decoration.rule], range: r)
            }
        }
    }
}

// MARK: - layout manager

/// Hides `.liveHidden` characters (null glyphs, no width) and draws bullets, checkboxes, rules,
/// quote bars and code backgrounds.
final class LiveMarkdownLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = textStorage else { return 0 }
        var newProps: [NSLayoutManager.GlyphProperty]?
        for i in 0..<glyphRange.length {
            let index = charIndexes[i]
            guard index < storage.length, storage.attribute(.liveHidden, at: index, effectiveRange: nil) != nil else { continue }
            if newProps == nil { newProps = Array(UnsafeBufferPointer(start: props, count: glyphRange.length)) }
            newProps?[i] = .null
        }
        guard let newProps else { return 0 }
        setGlyphs(glyphs, properties: newProps, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.liveBlock, in: chars) { value, range, _ in
            guard let block = value as? String else { return }
            // Start at the first shown character: hidden markers at a line start sit at the end of the
            // previous line fragment, which would pull the bar or background one line up.
            var start = range.location
            while start < NSMaxRange(range) - 1, storage.attribute(.liveHidden, at: start, effectiveRange: nil) != nil { start += 1 }
            let glyphs = glyphRange(forCharacterRange: NSRange(location: start, length: NSMaxRange(range) - start),
                                    actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, _, _ in
                var rect = fragment.offsetBy(dx: origin.x, dy: origin.y)
                rect.size.width = container.size.width
                if block == LiveStyleApplier.Block.quote {
                    NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
                    NSBezierPath(roundedRect: CGRect(x: rect.minX + 1, y: rect.minY + 1, width: 3, height: rect.height - 2),
                                 xRadius: 1.5, yRadius: 1.5).fill()
                } else {
                    NSColor.labelColor.withAlphaComponent(0.07).setFill()
                    rect.fill()
                }
            }
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.liveDrawing, in: chars) { value, range, _ in
            guard let drawing = value as? LiveDrawing else { return }
            let fragment = lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: range.location), effectiveRange: nil)
            drawing.draw(in: CGRect(origin: CGPoint(x: fragment.minX + origin.x, y: fragment.minY + origin.y), size: drawing.size))
        }
        storage.enumerateAttribute(.liveDecoration, in: chars) { value, range, _ in
            guard let decoration = value as? String else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
            switch decoration {
            case LiveStyleApplier.Decoration.bullet:
                let bullet = NSAttributedString(string: "•", attributes: [.font: LiveStyleApplier.baseFont,
                                                                          .foregroundColor: NSColor.secondaryLabelColor])
                bullet.draw(at: CGPoint(x: rect.minX, y: rect.minY))
            case LiveStyleApplier.Decoration.task, LiveStyleApplier.Decoration.taskDone:
                let checked = decoration == LiveStyleApplier.Decoration.taskDone
                // checkmark.square.fill: the mark is the first layer, the box the second.
                let colors: [NSColor] = checked ? [.white, .controlAccentColor] : [.secondaryLabelColor]
                let config = NSImage.SymbolConfiguration(pointSize: LiveStyleApplier.fontSize, weight: .regular)
                    .applying(NSImage.SymbolConfiguration(paletteColors: colors))
                if let image = NSImage(systemSymbolName: checked ? "checkmark.square.fill" : "square", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    let side = min(rect.height, LiveStyleApplier.fontSize + 2)
                    let box = CGRect(x: rect.minX, y: rect.midY - side / 2, width: side, height: side)
                    image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            case LiveStyleApplier.Decoration.rule:
                let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil).offsetBy(dx: origin.x, dy: origin.y)
                NSColor.separatorColor.setFill()
                CGRect(x: fragment.minX, y: rect.midY.rounded(), width: container.size.width, height: 1).fill()
            default:
                break
            }
        }
    }
}

// MARK: - drawn blocks (#21)

/// Something drawn in place of hidden source lines: a table, an image.
protocol LiveDrawing: AnyObject {
    var size: CGSize { get }
    func draw(in rect: CGRect)
}

/// A pipe table laid out for a width: columns fit (cells wrap) when the natural width doesn't.
final class LiveTableDrawing: NSObject, LiveDrawing {
    private static let padX: CGFloat = 6, padY: CGFloat = 3, minColumn: CGFloat = 36

    private let cells: [[NSAttributedString]]   // row 0 = header
    private let columns: [CGFloat]
    private let rows: [CGFloat]
    let size: CGSize

    init(_ table: MarkdownTable, source: String, width: CGFloat) {
        func cell(_ c: MarkdownTable.Cell, header: Bool, alignment: MarkdownTable.Alignment) -> NSAttributedString {
            let shown = MarkdownLiveStyle.displayInline(c.text)
            let p = NSMutableParagraphStyle()
            p.alignment = alignment == .center ? .center : alignment == .right ? .right : .left
            let base = header ? NSFont.systemFont(ofSize: LiveStyleApplier.fontSize, weight: .semibold) : LiveStyleApplier.baseFont
            let a = NSMutableAttributedString(string: shown.text, attributes: [.font: base, .foregroundColor: NSColor.labelColor, .paragraphStyle: p])
            for run in shown.runs {
                switch run.kind {
                case .bold: a.addAttribute(.font, value: NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask), range: run.range)
                case .italic: a.addAttribute(.font, value: NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask), range: run.range)
                case .code: a.addAttributes([.font: LiveStyleApplier.codeFont, .backgroundColor: NSColor.labelColor.withAlphaComponent(0.08)], range: run.range)
                case .strike: a.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: run.range)
                case .link: a.addAttribute(.foregroundColor, value: NSColor.linkColor, range: run.range)
                default: break
                }
            }
            return a
        }
        let padX = Self.padX, padY = Self.padY, minColumn = Self.minColumn
        let all = [table.header] + table.rows
        let texts = all.enumerated().map { r, row in
            row.enumerated().map { c, value in cell(value, header: r == 0, alignment: table.alignments[c]) }
        }

        let count = table.header.count
        let natural: [CGFloat] = (0..<count).map { c in
            max(minColumn, texts.map { ceil($0[c].size().width) + 2 * padX }.max() ?? minColumn)
        }
        let available = max(width - 1, CGFloat(count) * minColumn)
        let total = natural.reduce(0, +)
        // Too wide: shrink columns in proportion (never below the minimum); cells wrap.
        var widths: [CGFloat] = width > 0 && total > available ? natural.map { max(minColumn, floor($0 * available / total)) } : natural
        // The minimum can push the sum back over; take the rest from the widest columns.
        while width > 0, widths.reduce(0, +) > available,
              let widest = widths.indices.max(by: { widths[$0] < widths[$1] }), widths[widest] > minColumn {
            widths[widest] -= min(widths.reduce(0, +) - available, widths[widest] - minColumn)
        }
        let heights: [CGFloat] = texts.map { row in
            row.enumerated().map { c, text -> CGFloat in
                let bounds = text.boundingRect(with: CGSize(width: widths[c] - 2 * padX, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading])
                return ceil(max(bounds.height, LiveStyleApplier.fontSize + 3)) + 2 * padY
            }.max() ?? 0
        }
        cells = texts
        columns = widths
        rows = heights
        size = CGSize(width: widths.reduce(0, +) + 1, height: heights.reduce(0, +) + 1)
        super.init()
    }

    func draw(in rect: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let x0 = rect.minX + 0.5, y0 = rect.minY + 0.5
        if let header = rows.first {
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            CGRect(x: x0, y: y0, width: size.width - 1, height: header).fill()
        }
        var y = y0
        for (r, height) in rows.enumerated() {
            var x = x0
            for (c, width) in columns.enumerated() {
                let box = CGRect(x: x + Self.padX, y: y + Self.padY, width: width - 2 * Self.padX, height: height - 2 * Self.padY)
                cells[r][c].draw(with: box, options: [.usesLineFragmentOrigin, .usesFontLeading])
                x += width
            }
            y += height
        }
        let grid = NSBezierPath()
        grid.lineWidth = 1
        grid.appendRect(CGRect(x: x0, y: y0, width: size.width - 1, height: size.height - 1))
        var lineY = y0
        for height in rows.dropLast() { lineY += height; grid.move(to: CGPoint(x: x0, y: lineY)); grid.line(to: CGPoint(x: x0 + size.width - 1, y: lineY)) }
        var lineX = x0
        for width in columns.dropLast() { lineX += width; grid.move(to: CGPoint(x: lineX, y: y0)); grid.line(to: CGPoint(x: lineX, y: y0 + size.height - 1)) }
        NSColor.separatorColor.setStroke()
        grid.stroke()
    }
}

/// A loaded image, scaled to fit.
final class LiveImageDrawing: NSObject, LiveDrawing {
    private let image: NSImage
    let size: CGSize

    init(_ image: NSImage, size: CGSize) {
        self.image = image
        self.size = size
    }

    func draw(in rect: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// A one-line note in place of an image that is still loading.
final class LiveImagePlaceholder: NSObject, LiveDrawing {
    private let text: NSAttributedString
    let size: CGSize

    init(_ message: String) {
        text = NSAttributedString(string: message, attributes: [.font: LiveStyleApplier.baseFont, .foregroundColor: NSColor.secondaryLabelColor])
        size = CGSize(width: ceil(text.size().width) + 8, height: LiveStyleApplier.fontSize + 8)
    }

    func draw(in rect: CGRect) {
        text.draw(at: CGPoint(x: rect.minX + 4, y: rect.minY + 3))
    }
}

/// Images by URL. Local files load right away (and reload when the file changes); web images load
/// in the background and post `didLoad`.
final class LiveImageCache {
    static let shared = LiveImageCache()
    static let didLoad = Notification.Name("LiveImageCache.didLoad")

    enum State { case loaded(NSImage), loading, failed }

    private var remote: [URL: State] = [:]
    private var local: [URL: (modified: Date, image: NSImage)] = [:]

    func state(for url: URL) -> State {
        if url.isFileURL {
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
                return .failed   // not there (yet): not cached, a drop may add it
            }
            if let cached = local[url], cached.modified == modified { return .loaded(cached.image) }
            guard let image = NSImage(contentsOf: url) else { return .failed }
            local[url] = (modified, image)
            return .loaded(image)
        }
        if let state = remote[url] { return state }
        remote[url] = .loading
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            DispatchQueue.main.async {
                self.remote[url] = image.map(State.loaded) ?? .failed
                NotificationCenter.default.post(name: Self.didLoad, object: nil)
            }
        }.resume()
        return .loading
    }
}
