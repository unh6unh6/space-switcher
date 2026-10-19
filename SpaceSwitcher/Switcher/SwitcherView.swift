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
        /// Category header shown above this row: it starts a group (#35).
        var groupTitle: String? = nil
    }

    @Published var rows: [Row] = []
    @Published var selection = 0 {
        didSet { restoreMemoScroll() }
    }
    @Published var renamingRow: Int?
    @Published var draft = ""
    /// Memo preview beside the list (#20): on in Settings and at least one desktop has a memo.
    @Published var showsMemoPreview = false
    @Published var editingMemoRow: Int?
    /// Any category exists: the C key does something (#35).
    @Published var hasCategories = false
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
}

struct SwitcherView: View {
    /// Tall enough for 16 rows without scrolling on a 13" screen (SPEC §3.2).
    static let rowHeight: CGFloat = 30
    static let previewWidth: CGFloat = 380
    /// The preview never gets shorter than this, even next to a 2-desktop list.
    static let previewMinHeight: CGFloat = 240
    /// A category header above a group of rows (#35).
    static let headerHeight: CGFloat = 20

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
        let headers = CGFloat(model.rows.filter { $0.groupTitle != nil }.count) * (Self.headerHeight + 2)
        let listHeight = CGFloat(model.rows.count) * (Self.rowHeight + 2) + headers + 28
        return max(listHeight, Self.previewMinHeight)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { i, row in
                if let title = row.groupTitle {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: Self.headerHeight, alignment: .bottomLeading)
                }
                rowView(row, index: i)
            }
            if showsPreview { Spacer(minLength: 0) }
            Text(model.editingMemoRow != nil
                 ? "자동 저장 · Esc 완료"
                 : "↑↓ 이동 · Enter 전환 · 1–9 바로 · R 이름 · D 메모" + (model.hasCategories ? " · C 분류" : "")
                    + (showsPreview ? " · ⇧↑↓ 스크롤" : "") + " · Esc")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .padding(.horizontal, 10)
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
        .onTapGesture(count: 2) { model.onDoubleClick(index) }
        .onTapGesture { model.onClick(index) }
    }
}
