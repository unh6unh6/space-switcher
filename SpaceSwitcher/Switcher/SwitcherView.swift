import AppKit
import SwiftUI

final class SwitcherViewModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id: String
        let number: Int
        let title: String
        let isNamed: Bool
        let isCurrent: Bool
        /// Apps with windows on this desktop (#14); nil when the setting is off.
        var apps: [SpaceApps.App]? = nil
        var overflow = 0
        /// This desktop's memo file (#18).
        var memo: String? = nil
        /// Read-only memo (#27).
        var isLocked = false
    }

    /// What the list draws, top to bottom: category headers (#35; empty ones too with #43) and rows.
    enum Line: Equatable {
        case header(title: String, slot: DesktopCategories.Slot, isEmpty: Bool)
        case row(Int)
    }

    @Published var rows: [Row] = []
    /// Empty = just the rows (no categories).
    @Published var lines: [Line] = []
    var shownLines: [Line] { lines.isEmpty ? rows.indices.map(Line.row) : lines }
    @Published var selection = 0 {
        didSet { restoreMemoScroll() }
    }
    @Published var renamingRow: Int?
    @Published var draft = ""
    /// Memo preview beside the list (#20): on in Settings and at least one desktop has a memo.
    @Published var showsMemoPreview = false
    @Published var editingMemoRow: Int?
    /// Categories are on: C and dragging move rows (#44).
    @Published var canReorder = false
    /// While a row is dragged (#44): the row, and the line the drop marker sits above (`shownLines.count` = after the last).
    @Published var draggedRow: Int?
    @Published var dropMarker: Int?
    /// The memo feature is on (#42): D edits the memo.
    @Published var memoEnabled = true
    /// While D-editing (#27): the editor's text, and the version it was opened with (so typing is never
    /// replaced by a reload); bump `memoFocusRequest` to put the caret in.
    var memoEditText = ""
    @Published var memoEditVersion = 0
    @Published var memoFocusRequest = 0
    /// The memo folder, for images (#21).
    var memoDirectory: URL?
    /// First visible source line of the preview. Shift+↑↓ and mouse scrolling move it; remembered per
    /// desktop, across restarts (#25).
    @Published var memoScrollLine = 0 {
        didSet { memoScroll.set(memoScrollLine, for: selectedRow?.id) }
    }
    private var memoScroll = MemoScrollMemory(persistingAs: "memoScrollPreview")

    /// Drops remembered positions of desktops that no longer exist.
    func pruneMemoScroll(keeping ids: Set<String>) { memoScroll.prune(keeping: ids) }

    var selectedRow: Row? { rows.indices.contains(selection) ? rows[selection] : nil }

    /// Lines per Shift+↑↓ press.
    static let scrollStep = 4

    private var selectedLineCount: Int { MarkdownLiveStyle.lineCount(selectedRow?.memo ?? "") }

    /// Back to where the selected desktop's memo was being read.
    func restoreMemoScroll() {
        memoScrollLine = memoScroll.position(for: selectedRow?.id, blockCount: selectedLineCount)
    }

    func scrollMemo(by steps: Int) {
        memoScrollLine = min(max(0, memoScrollLine + steps * Self.scrollStep), max(0, selectedLineCount - 1))
    }

    var onClick: (Int) -> Void = { _ in }
    var onDoubleClick: (Int) -> Void = { _ in }
    var onCommitRename: (String) -> Void = { _ in }
    var onCancelRename: () -> Void = {}
    var onMemoChange: (String) -> Void = { _ in }
    var onMemoDone: () -> Void = {}
    var onToggleTask: (Int) -> Void = { _ in }
    /// A row dropped before or after a line (#44).
    var onDrop: (_ row: Int, _ slot: DesktopCategories.Slot, _ after: Bool) -> Void = { _, _, _ in }

    /// The line under `y` (list coordinates) and which side of it a drop lands on. A header always takes
    /// the drop below it, at the top of its group.
    static func dropTarget(at y: CGFloat, in lines: [Line], rowHeight: CGFloat, headerHeight: CGFloat,
                           spacing: CGFloat) -> (line: Int, after: Bool)? {
        guard !lines.isEmpty else { return nil }
        var top: CGFloat = 0
        for (i, line) in lines.enumerated() {
            let height: CGFloat
            if case .header = line { height = headerHeight } else { height = rowHeight }
            if y < top + height + spacing || i == lines.count - 1 {
                if case .header = line { return (i, true) }
                return (i, y >= top + height / 2)
            }
            top += height + spacing
        }
        return nil
    }

    func slot(of line: Line) -> DesktopCategories.Slot? {
        switch line {
        case .header(_, let slot, _): return slot
        case .row(let i): return rows.indices.contains(i) ? .space(rows[i].id) : nil
        }
    }
}

struct SwitcherView: View {
    /// Tall enough for 16 rows without scrolling on a 13" screen (SPEC §3.2).
    static let rowHeight: CGFloat = 30
    static let previewWidth: CGFloat = 380
    /// The preview never gets shorter than this, even next to a 2-desktop list.
    static let previewMinHeight: CGFloat = 240
    /// A category header above a group of rows (#35).
    static let headerHeight: CGFloat = 20
    static let spacing: CGFloat = 2
    private static let listSpace = "switcherList"

    @ObservedObject var model: SwitcherViewModel
    @FocusState private var fieldFocused: Bool
    @FocusState private var editorFocused: Bool

    private var showsPreview: Bool { model.showsMemoPreview || model.editingMemoRow != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            list
                .frame(width: model.rows.contains { $0.apps != nil } ? 440 : 340)
            if showsPreview {
                Divider()
                memoPreview
                    .frame(width: Self.previewWidth, height: previewHeight, alignment: .topLeading)
            }
        }
        .padding(10)
    }

    /// As tall as the list (min 240) and never taller: a long memo scrolls instead of stretching
    /// the panel, and moving the selection never resizes it.
    private var previewHeight: CGFloat {
        let headers = CGFloat(model.shownLines.filter { if case .header = $0 { return true } else { return false } }.count)
            * (Self.headerHeight + 2)
        let listHeight = CGFloat(model.rows.count) * (Self.rowHeight + 2) + headers + 28
        return max(listHeight, Self.previewMinHeight)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            let lines = model.shownLines
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Group {
                    switch line {
                    case let .header(title, _, isEmpty):
                        header(title, isEmpty: isEmpty)
                    case .row(let index):
                        if model.rows.indices.contains(index) { rowView(model.rows[index], index: index) }
                    }
                }
                .overlay(alignment: .top) { if model.dropMarker == i { dropMarker.offset(y: -2) } }
                .overlay(alignment: .bottom) { if model.dropMarker == lines.count, i == lines.count - 1 { dropMarker.offset(y: 2) } }
            }
            if showsPreview { Spacer(minLength: 0) }
            Text(model.editingMemoRow != nil
                 ? "자동 저장 · Esc 완료"
                 : "↑↓ 이동 · Enter 전환 · 1–9 바로 · R 이름" + (model.memoEnabled ? " · D 메모" : "")
                    + (model.canReorder ? " · C 옮기기" : "")
                    + (showsPreview ? " · ⇧↑↓ 스크롤" : "") + " · Esc")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .padding(.horizontal, 10)
        }
        .coordinateSpace(name: Self.listSpace)
    }

    /// A category header; an empty category (#43) is shown dimmed so rows can still be moved under it.
    private func header(_ title: String, isEmpty: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if isEmpty {
                Text("비어 있음")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: Self.headerHeight, maxHeight: Self.headerHeight, alignment: .bottomLeading)
        .opacity(isEmpty ? 0.7 : 1)
    }

    /// Where a dragged row will land (#44).
    private var dropMarker: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 6)
    }

    /// Drag a row to another place (#44); moving it under another header recategorizes it.
    private func dragRow(_ index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.listSpace))
            .onChanged { value in
                guard model.canReorder, model.renamingRow == nil, model.editingMemoRow == nil else { return }
                model.draggedRow = index
                let target = SwitcherViewModel.dropTarget(at: value.location.y, in: model.shownLines, rowHeight: Self.rowHeight,
                                                          headerHeight: Self.headerHeight, spacing: Self.spacing)
                model.dropMarker = target.map { $0.after ? $0.line + 1 : $0.line }
            }
            .onEnded { value in
                defer { model.draggedRow = nil; model.dropMarker = nil }
                guard model.draggedRow == index,
                      let target = SwitcherViewModel.dropTarget(at: value.location.y, in: model.shownLines, rowHeight: Self.rowHeight,
                                                                headerHeight: Self.headerHeight, spacing: Self.spacing),
                      let slot = model.slot(of: model.shownLines[target.line]) else { return }
                model.onDrop(index, slot, target.after)
            }
    }

    /// The selected desktop's memo, scrollable; D makes it editable in place (#20, #27).
    private var memoPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(model.selectedRow?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                if model.selectedRow?.isLocked == true {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).help("읽기 전용")
                }
            }
            if let row = model.selectedRow, row.memo != nil || model.editingMemoRow != nil {
                let editing = model.editingMemoRow != nil
                LiveMarkdownEditor(text: editing ? model.memoEditText : (row.memo ?? ""),
                                   version: editing ? model.memoEditVersion : (row.memo ?? "").hashValue,
                                   editable: editing,
                                   canToggleTasks: !row.isLocked,
                                   scrollLine: model.memoScrollLine,
                                   focusRequest: model.memoFocusRequest,
                                   baseDirectory: model.memoDirectory,
                                   onTextChange: model.onMemoChange,
                                   onDone: model.onMemoDone,
                                   onScroll: { model.memoScrollLine = $0 },
                                   onToggleTask: model.onToggleTask)
                    .id(row.id)   // a fresh editor per desktop, opened at its remembered line
            } else {
                Text(model.selectedRow?.isLocked == true ? "메모 없음" : "메모 없음 · D로 작성")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)  // short content (e.g. "메모 없음") hugs the left edge
    }

    /// Up to 5 app icons, "+N" for the rest, or "(비어 있음)" for a desktop without windows.
    @ViewBuilder
    private func appIcons(_ apps: [SpaceApps.App], overflow: Int, selected: Bool) -> some View {
        if apps.isEmpty {
            Text("(비어 있음)")
                .font(.caption)
                .foregroundStyle(selected ? .white.opacity(0.7) : .secondary)
        } else {
            HStack(spacing: 3) {
                ForEach(apps, id: \.pid) { app in
                    if let icon = NSRunningApplication(processIdentifier: app.pid)?.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                            .help(app.name)
                    }
                }
                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(.caption)
                        .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: SwitcherViewModel.Row, index: Int) -> some View {
        let selected = index == model.selection
        HStack(spacing: 10) {
            Text("\(row.number)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
                .frame(width: 22, alignment: .trailing)

            if model.renamingRow == index {
                TextField(row.isNamed ? "" : row.title, text: $model.draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { model.onCommitRename(model.draft) }
                    .onExitCommand { model.onCancelRename() }
                    .onAppear { fieldFocused = true }
            } else {
                Text(row.title)
                    .foregroundStyle(selected ? .white : (row.isNamed ? .primary : .secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)
            if let apps = row.apps, model.renamingRow != index {
                appIcons(apps, overflow: row.overflow, selected: selected)
            }
            if row.isCurrent {
                Text("현재")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(selected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.2)))
                    .foregroundStyle(selected ? .white : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .opacity(model.draggedRow == index ? 0.5 : 1)
        .onTapGesture(count: 2) { model.onDoubleClick(index) }
        .onTapGesture { model.onClick(index) }
        .simultaneousGesture(dragRow(index))
    }
}
