import SwiftUI

struct MenuBuilderView: View {
    @EnvironmentObject private var vm: GestureViewModel
    @State private var showAddItem    = false
    @State private var editingItem:   MenuItem? = nil
    @State private var newTitle  = ""
    @State private var newIcon   = "circle.fill"
    @State private var newSubtitle = ""

    private var menu: AppMenu { vm.menu }

    var body: some View {
        NavigationStack {
            List {
                // Current selection preview
                Section {
                    menuPreview
                }

                // Items list
                Section("Menu Items") {
                    ForEach(Array(menu.items.enumerated()), id: \.element.id) { idx, item in
                        MenuItemRow(item: item, isSelected: idx == menu.selectedIndex)
                            .contentShape(Rectangle())
                            .onTapGesture { menu.selectedIndex = idx; pushMenu() }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    removeItem(at: idx)
                                } label: { Label("Delete", systemImage: "trash") }
                                Button {
                                    editingItem = item
                                } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(.orange)
                            }
                    }
                    .onMove { from, to in
                        menu.items.move(fromOffsets: from, toOffset: to)
                        menu.save()
                        pushMenu()
                    }
                }

                // Global actions
                Section {
                    Button {
                        vm.applyAction(.next)
                    } label: {
                        Label("Move to Next Item", systemImage: "arrow.right")
                    }
                    Button {
                        vm.applyAction(.previous)
                    } label: {
                        Label("Move to Previous Item", systemImage: "arrow.left")
                    }
                    Button {
                        vm.applyAction(.select)
                    } label: {
                        Label("Select Current Item", systemImage: "checkmark.circle")
                    }
                    .tint(.green)
                    Button {
                        menu.items = MenuItem.defaultItems
                        menu.selectedIndex = 0
                        menu.save()
                        pushMenu()
                    } label: {
                        Label("Reset to Default Menu", systemImage: "arrow.counterclockwise")
                    }
                    .tint(.orange)
                } header: {
                    Text("Quick Actions")
                }
            }
            .navigationTitle("Menu Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        newTitle = ""; newIcon = "circle.fill"; newSubtitle = ""
                        showAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(menu.items.count >= 8)
                }
            }
            .sheet(isPresented: $showAddItem) { addItemSheet }
            .sheet(item: $editingItem) { item in editItemSheet(item) }
        }
    }

    // MARK: - Menu preview

    private var menuPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Glasses preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(menu.glassesText(format: vm.glassesFormat))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.cyan)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Helpers

    private func removeItem(at idx: Int) {
        menu.items.remove(at: idx)
        if menu.selectedIndex >= menu.items.count {
            menu.selectedIndex = max(0, menu.items.count - 1)
        }
        menu.save(); pushMenu()
    }

    private func pushMenu() {
        vm.pushMenuToGlasses()
    }

    // MARK: - Add item sheet

    private var addItemSheet: some View {
        NavigationStack {
            ItemEditorForm(title: $newTitle, icon: $newIcon, subtitle: $newSubtitle)
                .navigationTitle("New Item")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddItem = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            guard !newTitle.isEmpty else { return }
                            menu.items.append(MenuItem(title: newTitle, icon: newIcon, subtitle: newSubtitle))
                            menu.save(); pushMenu()
                            showAddItem = false
                        }
                        .disabled(newTitle.isEmpty)
                    }
                }
        }
    }

    // MARK: - Edit item sheet

    private func editItemSheet(_ item: MenuItem) -> some View {
        @State var t = item.title
        @State var i = item.icon
        @State var s = item.subtitle
        return NavigationStack {
            ItemEditorForm(title: $t, icon: $i, subtitle: $s)
                .navigationTitle("Edit Item")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingItem = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let idx = menu.items.firstIndex(where: { $0.id == item.id }) {
                                menu.items[idx] = MenuItem(title: t, icon: i, subtitle: s)
                                // preserve id
                                menu.items[idx] = MenuItem(title: t, icon: i, subtitle: s)
                            }
                            menu.save(); pushMenu()
                            editingItem = nil
                        }
                    }
                }
        }
    }
}

// MARK: - Item row

struct MenuItemRow: View {
    let item: MenuItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(isSelected ? .yellow : .secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.yellow.opacity(0.08) : nil)
    }
}

// MARK: - Item editor form

struct ItemEditorForm: View {
    @Binding var title:    String
    @Binding var icon:     String
    @Binding var subtitle: String

    private let iconOptions = [
        "house.fill", "bell.fill", "square.grid.2x2.fill", "gear",
        "play.circle.fill", "map.fill", "camera.fill", "phone.fill",
        "heart.fill", "star.fill", "bookmark.fill", "person.fill",
        "envelope.fill", "calendar", "clock.fill", "wifi",
    ]

    var body: some View {
        Form {
            Section("Title") {
                TextField("Item name", text: $title)
            }
            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(iconOptions, id: \.self) { name in
                        Button {
                            icon = name
                        } label: {
                            Image(systemName: name)
                                .font(.title2)
                                .foregroundStyle(icon == name ? .yellow : .secondary)
                                .frame(width: 44, height: 44)
                                .background(icon == name
                                            ? Color.yellow.opacity(0.15)
                                            : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Subtitle (optional)") {
                TextField("Shown below title on glasses", text: $subtitle)
            }
        }
    }
}

// Make NavAction accessible from ViewModel in the view
extension GestureViewModel {
    func applyAction(_ action: NavAction) {
        switch action {
        case .next:       menu.moveNext()
        case .previous:   menu.movePrev()
        case .scrollUp:   menu.moveFirst()
        case .scrollDown: menu.moveLast()
        case .select:
            if let item = menu.selectedItem {
                glassesServer.broadcastSelect(item.title)
            }
        case .back:
            glassesServer.broadcastStatus("← Back")
        case .none: break
        }
        pushMenuToGlasses()
        menu.save()
    }
}
