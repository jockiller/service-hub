import SwiftUI

@MainActor
struct GroupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    var groupToEdit: ServiceGroup?
    let onSave: (ServiceGroup) -> Void

    @State private var name: String = ""
    @State private var icon: String = "folder"
    @State private var errorMessage: String? = nil

    private let presetIcons = [
        "folder",
        "server.rack",
        "cylinder",
        "shippingbox.fill",
        "terminal",
        "network",
        "cpu",
        "bolt.fill",
        "globe",
        "gearshape",
        "cloud",
        "waveform.path.ecg",
        "shield.fill",
        "cube",
        "sparkles",
        "externaldrive",
        "tray"
    ]

    var isEditing: Bool {
        groupToEdit != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏标题
            HStack {
                Text(isEditing ? L("编辑分组", "Edit Group") : L("新建分组", "New Group"))
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(Color.primary.opacity(0.03))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 分组名称
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("分组名称", "Group Name"))
                            .font(.system(size: 12, weight: .semibold))
                        TextField(L("例如：后端开发、数据库、AI服务", "e.g. Backend, Databases, AI Services"), text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // 分组图标选择
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("分组图标", "Group Icon"))
                            .font(.system(size: 12, weight: .semibold))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40, maximum: 44), spacing: 8)], spacing: 8) {
                            ForEach(presetIcons, id: \.self) { sym in
                                let isSelected = icon == sym
                                Button(action: { icon = sym }) {
                                    Image(systemName: sym)
                                        .font(.system(size: 16))
                                        .frame(width: 38, height: 38)
                                        .background(
                                            isSelected
                                                ? Color.accentColor.opacity(0.2)
                                                : Color.primary.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(
                                                    isSelected ? Color.accentColor : Color.clear,
                                                    lineWidth: 1.5
                                                )
                                        )
                                        .foregroundColor(isSelected ? .accentColor : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(20)
            }

            Divider()

            // 底栏操作按钮
            HStack {
                Spacer()
                Button(L("取消", "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? L("保存", "Save") : L("创建", "Create")) {
                    saveGroup()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(Color.primary.opacity(0.02))
        }
        .frame(width: 420, height: 360)
        .onAppear {
            if let g = groupToEdit {
                name = g.name
                icon = g.icon
            }
        }
    }

    private func saveGroup() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = L("分组名称不能为空", "Group name cannot be empty")
            return
        }

        var group = groupToEdit ?? ServiceGroup(name: trimmedName, icon: icon)
        group.name = trimmedName
        group.icon = icon

        onSave(group)
        dismiss()
    }
}
