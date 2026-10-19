import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case general, shortcut, desktops, memo, permissions
}

final class SettingsModel: ObservableObject {
    @Published var tab: SettingsTab = .general
    @Published private(set) var spaces: [Space] = []
    @Published private(set) var unusedNames = 0
    @Published private(set) var launchStatus = LaunchAtLogin.status
    @Published var launchError: String?
    @Published var initialSelection = InitialSelection.stored {
        didSet { InitialSelection.store(initialSelection) }
    }
    @Published var menuBar = MenuBarTitle.Settings.load() {
        didSet { menuBar.save() }
    }
    /// Desktop categories (#35); the switcher's C key also changes them.
    @Published var categories = DesktopCategories.load() {
        didSet { if !syncingCategories { categories.save() } }
    }
    private var syncingCategories = false
    @Published var newCategory = ""
    /// Merges only the fields this tab edits into the latest stored settings, because the overlay
    /// saves its own frame/collapsed state meanwhile; saving a stale copy would undo a drag.
    @Published var memo = MemoSettings.load() {
        didSet {
            guard !syncingMemo else { return }
            var current = MemoSettings.load()
            current.overlayEnabled = memo.overlayEnabled
            current.previewEnabled = memo.previewEnabled
            current.opacity = memo.opacity
            current.hideWhenEmpty = memo.hideWhenEmpty
            current.overlayBackground = memo.overlayBackground
            current.directoryPath = memo.directoryPath
            current.template = memo.template
            if current.corner != memo.corner {
                current.corner = memo.corner
                current.resetPositions()  // every desktop's memo moves to the picked corner (#24)
            }
            current.save()
        }
    }
    private var syncingMemo = false
    @Published private(set) var memoFolder = ""
    @Published var showAppIcons = SpaceApps.showIcons() {
        didSet { SpaceApps.setShowIcons(showAppIcons) }
    }
    @Published var hud = SpaceHUDSettings.load() {
        didSet { hud.save() }
    }
    @Published var missionControlLabels = MissionControlLayout.isEnabled() {
        didSet { MissionControlLayout.setEnabled(missionControlLabels) }
    }

    let names: NameStore
    let memos: MemoStore
    let permissions: PermissionMonitor
    let setSwitcherSuspended: (Bool) -> Void

    init(names: NameStore, memos: MemoStore, permissions: PermissionMonitor, setSwitcherSuspended: @escaping (Bool) -> Void) {
        self.names = names
        self.memos = memos
        self.permissions = permissions
        self.setSwitcherSuspended = setSwitcherSuspended
        NotificationCenter.default.addObserver(forName: NameStore.didChange, object: names, queue: .main) { [weak self] _ in
            self?.reload()
        }
        NotificationCenter.default.addObserver(forName: DesktopCategories.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self, !syncingCategories else { return }
            syncingCategories = true
            categories = DesktopCategories.load()
            syncingCategories = false
        }
        // Menu bar toggle and the overlay itself also change memo settings; mirror them here.
        NotificationCenter.default.addObserver(forName: MemoSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            syncingMemo = true
            memo = MemoSettings.load()
            syncingMemo = false
        }
    }

    func reload() {
        memoFolder = memos.directory.path
        spaces = SpaceProvider.spaces()
        unusedNames = names.unusedCount(keeping: Set(spaces.map(\.id)))
        launchStatus = LaunchAtLogin.status
    }

    func setLaunchAtLogin(_ on: Bool) {
        launchError = LaunchAtLogin.set(on)
        launchStatus = LaunchAtLogin.status
    }

    /// Folder picker → ask whether to move existing memos → switch the store (#18).
    func chooseMemoFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "선택"
        panel.message = "메모(.md 파일)를 저장할 폴더를 고르세요"
        panel.directoryURL = memos.directory
        guard panel.runModal() == .OK, let url = panel.url, url.standardizedFileURL != memos.directory.standardizedFileURL else { return }

        let alert = NSAlert()
        alert.messageText = "기존 메모를 새 폴더로 옮길까요?"
        alert.informativeText = "옮기지 않으면 새 폴더에 있는 메모를 사용합니다. 기존 파일은 그대로 남습니다."
        alert.addButton(withTitle: "옮기기")
        alert.addButton(withTitle: "그대로 두기")
        alert.addButton(withTitle: "취소")
        let answer = alert.runModal()
        guard answer != .alertThirdButtonReturn else { return }
        memos.changeDirectory(to: url, moveExisting: answer == .alertFirstButtonReturn)
        memo.directoryPath = url.path
        reload()
    }

    func openMemoFolder() {
        try? FileManager.default.createDirectory(at: memos.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(memos.directory)
    }

    func addCategory() {
        if categories.add(newCategory) { newCategory = "" } else { NSSound.beep() }
    }

    func removeUnusedNames() {
        names.removeUnused(keeping: Set(spaces.map(\.id)))
        var settings = MemoSettings.load()
        settings.pruneLayouts(keeping: Set(spaces.map(\.id)))   // memo window layouts of removed desktops (#24)
        settings.save()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView(selection: $model.tab) {
            GeneralTab(model: model)
                .tabItem { Label("일반", systemImage: "gearshape") }.tag(SettingsTab.general)
            ShortcutTab(model: model)
                .tabItem { Label("단축키", systemImage: "keyboard") }.tag(SettingsTab.shortcut)
            DesktopsTab(model: model)
                .tabItem { Label("데스크탑", systemImage: "rectangle.3.group") }.tag(SettingsTab.desktops)
            MemoTab(model: model)
                .tabItem { Label("메모", systemImage: "note.text") }.tag(SettingsTab.memo)
            PermissionsView(monitor: model.permissions, onClose: nil)
                .tabItem { Label("권한", systemImage: "lock.shield") }.tag(SettingsTab.permissions)
        }
        .padding(20)
        .frame(width: 540, height: 560)
        .onAppear(perform: model.reload)
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("로그인 시 자동 실행", isOn: Binding(
                    get: { model.launchStatus != .disabled },
                    set: { model.setLaunchAtLogin($0) }))
                if model.launchStatus == .needsApproval {
                    HStack {
                        Text("시스템 설정 → 일반 → 로그인 항목에서 SpaceSwitcher를 허용해 주세요.")
                            .font(.callout).foregroundStyle(.orange)
                        Button("열기") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = model.launchError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }
            Section("메뉴바 표시") {
                Picker("표시 방식", selection: $model.menuBar.style) {
                    Text("이름만  (업무)").tag(MenuBarTitle.Style.name)
                    Text("번호 + 이름  (2 업무)").tag(MenuBarTitle.Style.numberAndName)
                    Text("점  (○ ● ○)").tag(MenuBarTitle.Style.dots)
                    Text("점 + 이름  (○ ● ○ 업무)").tag(MenuBarTitle.Style.dotsAndName)
                    Text("번호만  (2)").tag(MenuBarTitle.Style.number)
                }
                Picker("이름 최대 길이", selection: $model.menuBar.maxLength) {
                    ForEach(MenuBarTitle.lengthOptions, id: \.self) { Text("\($0)자").tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled([.dots, .number].contains(model.menuBar.style))
            }
            Section("데스크탑 이동 시 이름 표시") {
                Toggle("화면에 데스크탑 이름 잠깐 표시", isOn: $model.hud.isEnabled)
                Picker("표시 시간", selection: $model.hud.duration) {
                    Text("짧게").tag(SpaceHUDSettings.Duration.short)
                    Text("보통").tag(SpaceHUDSettings.Duration.normal)
                    Text("길게").tag(SpaceHUDSettings.Duration.long)
                }
                .pickerStyle(.segmented)
                .disabled(!model.hud.isEnabled)
                Picker("위치", selection: $model.hud.position) {
                    Text("가운데").tag(SpaceHUDSettings.Position.center)
                    Text("위쪽").tag(SpaceHUDSettings.Position.top)
                }
                .pickerStyle(.segmented)
                .disabled(!model.hud.isEnabled)
            }
            Section("Mission Control") {
                Toggle("데스크탑 줄 썸네일에 데스크탑 이름 표시", isOn: $model.missionControlLabels)
                Text("화면 위쪽 데스크탑 줄을 펼치면 각 썸네일 아래쪽에 이름이 붙습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("스위처 목록에 데스크탑별 앱 아이콘 표시", isOn: $model.showAppIcons)
                Picker("스위처를 열 때 처음 선택", selection: $model.initialSelection) {
                    Text("현재 데스크탑").tag(InitialSelection.current)
                    Text("직전 데스크탑").tag(InitialSelection.previous)
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MemoTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("저장 폴더") {
                Text(model.memoFolder)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack {
                    Button("폴더 변경…", action: model.chooseMemoFolder)
                    Button("Finder에서 열기", action: model.openMemoFolder)
                }
                Text("데스크탑마다 `이름.md` 파일 하나. 다른 편집기에서 고쳐도 바로 반영됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("메모 띄우기") {
                Toggle("현재 데스크탑 메모를 항상 위에 띄우기", isOn: $model.memo.overlayEnabled)
                LabeledContent("투명도") {
                    Slider(value: $model.memo.opacity, in: MemoSettings.minOpacity...1)
                        .frame(maxWidth: 220)
                    Text("\(Int(model.memo.opacity * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                .disabled(!model.memo.overlayEnabled)
                Picker("위치", selection: Binding(
                    get: { model.memo.corner },
                    set: { model.memo.corner = $0 })) {
                    Text("왼쪽 위").tag(MemoSettings.Corner.topLeft)
                    Text("오른쪽 위").tag(MemoSettings.Corner.topRight)
                    Text("왼쪽 아래").tag(MemoSettings.Corner.bottomLeft)
                    Text("오른쪽 아래").tag(MemoSettings.Corner.bottomRight)
                }
                .disabled(!model.memo.overlayEnabled)
                Toggle("메모가 없는 데스크탑에서는 숨기기", isOn: $model.memo.hideWhenEmpty)
                    .disabled(!model.memo.overlayEnabled)
                Picker("메모 창 배경색", selection: $model.memo.overlayBackground) {
                    ForEach(MemoSettings.Background.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!model.memo.overlayEnabled)
                Text("드래그로 옮기고 가장자리를 끌어 크기를 바꿀 수 있어요. 위치는 기억됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Option+E") {
                Toggle("목록 옆에 선택한 데스크탑의 메모 미리보기", isOn: $model.memo.previewEnabled)
            }
            Section("새 메모 템플릿") {
                TextEditor(text: $model.memo.template)
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
                Text("메모가 없는 데스크탑에서 처음 입력할 때 이 내용으로 시작해요. 고치지 않고 나가면 저장되지 않아요.\n`{{name}}` 데스크탑 이름 · `{{date}}` 오늘 날짜 · 비우면 빈 메모로 시작")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("스위처 단축키").font(.headline)
            ShortcutRecorderView(setSuspended: model.setSwitcherSuspended)
            Text("버튼을 누른 뒤 새 조합을 누르면 바로 적용됩니다. 수식키(⌃ ⌥ ⌘) 1개 이상 + 일반 키 1개.\n"
                 + "수식키를 누른 채 키를 반복해서 누르면 순환 모드, 짧게 누르면 팝업 모드입니다.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

private struct DesktopsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CategoriesEditor(model: model)
            List(model.spaces) { space in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(space.index)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        NameField(space: space, names: model.names)
                        if space.isCurrent {
                            Text("현재").font(.caption).foregroundStyle(.secondary)
                        }
                        if !model.categories.categories.isEmpty {
                            Picker("", selection: Binding(
                                get: { model.categories.category(for: space.id)?.id ?? "" },
                                set: { model.categories.assign($0.isEmpty ? nil : $0, to: space.id) })) {
                                Text(DesktopCategories.uncategorizedTitle).tag("")
                                ForEach(model.categories.categories) { Text($0.name).tag($0.id) }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                    }
                    MemoField(space: space, names: model.names, memos: model.memos)
                        .padding(.leading, 32)
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text("Enter로 저장 · 설명 줄바꿈은 ⌥Enter · 비우면 삭제")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("사용하지 않는 이름 정리 (\(model.unusedNames)개)", action: model.removeUnusedNames)
                    .disabled(model.unusedNames == 0)
            }
        }
    }
}

/// Category list (#35): add, rename (Enter), reorder, delete. Order = group order in Option+E.
private struct CategoriesEditor: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("카테고리").font(.headline)
            ForEach(model.categories.categories) { category in
                HStack(spacing: 6) {
                    CategoryNameField(category: category, model: model)
                    Button { model.categories.move(category.id, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(model.categories.categories.first?.id == category.id)
                    Button { model.categories.move(category.id, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(model.categories.categories.last?.id == category.id)
                    Button { model.categories.remove(category.id) } label: { Image(systemName: "trash") }
                        .help("삭제 (이 카테고리의 데스크탑은 미분류로)")
                }
                .buttonStyle(.borderless)
            }
            HStack(spacing: 6) {
                TextField("새 카테고리 (예: todo)", text: $model.newCategory)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(model.addCategory)
                Button("추가", action: model.addCategory)
                    .disabled(model.newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Option+E 목록이 이 순서대로 묶여 보여요. 목록에서 C를 누르면 선택한 데스크탑의 카테고리가 바뀌어요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CategoryNameField: View {
    let category: DesktopCategories.Category
    @ObservedObject var model: SettingsModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { draft = category.name }
            .onChange(of: category.name) { _, name in draft = name }
            .onSubmit(save)
            .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
    }

    private func save() {
        model.categories.rename(category.id, to: draft)
        draft = model.categories.categories.first { $0.id == category.id }?.name ?? draft
    }
}

/// Edits a draft and saves on Enter or when focus leaves.
private struct NameField: View {
    let space: Space
    let names: NameStore
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("데스크탑 \(space.index)", text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { draft = names.name(for: space.id) ?? "" }
            .onSubmit(save)
            .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
    }

    private func save() {
        if draft != (names.name(for: space.id) ?? "") { names.setName(draft, for: space.id) }
        draft = names.name(for: space.id) ?? ""
    }
}

/// The desktop's memo (#18), saved as a Markdown file. Enter saves, ⌥Enter adds a line, leaving saves too.
private struct MemoField: View {
    let space: Space
    let names: NameStore
    let memos: MemoStore
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("메모 (여러 줄, 마크다운 파일로 저장)", text: $draft, axis: .vertical)
            .lineLimit(1...4)
            .font(.callout)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { draft = memos.memo(for: space.id) ?? "" }
            .onSubmit(save)
            .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
    }

    private func save() {
        if draft != (memos.memo(for: space.id) ?? "") {
            memos.setMemo(draft, for: space.id, desktopName: names.displayName(for: space))
        }
        draft = memos.memo(for: space.id) ?? ""
    }
}

/// Plain NSWindow: the SwiftUI `Settings` scene is awkward to open from an agent app's menu.
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?

    init(model: SettingsModel) {
        self.model = model
    }

    func show(tab: SettingsTab? = nil) {
        if let tab { model.tab = tab }
        model.reload()
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "SpaceSwitcher 설정"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
