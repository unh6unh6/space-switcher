import AppKit
import SwiftUI

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
        let caretLines = isRevealing ? MarkdownLiveStyle.lines(touching: selectedRange(), in: string) : nil
        guard force || caretLines != revealed else { return }
        revealed = caretLines
        LiveStyleApplier.apply(to: storage, revealing: caretLines)
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
        super.keyDown(with: event)
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

    static func apply(to storage: NSTextStorage, revealing caretLines: ClosedRange<Int>?) {
        let text = storage.string
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: all)
        for run in MarkdownLiveStyle.runs(in: text) {
            let raw = caretLines?.contains(run.line) ?? false
            style(run, raw: raw, in: storage)
        }
        storage.endEditing()
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
