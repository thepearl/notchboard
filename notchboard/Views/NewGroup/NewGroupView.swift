//
//  NewGroupView.swift
//  notchboard
//

import SwiftUI
import UniformTypeIdentifiers

struct NewGroupView: View {
    @Bindable var viewModel: NotchboardViewModel

    @State private var confirmingDelete = false
    /// The field currently being dragged by its ⋮⋮ handle (vision §5.5 reorderable list).
    @State private var draggedFieldID: UUID?

    private var isEditing: Bool { viewModel.editingGroupID != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                nameField
                fieldsSection
                Spacer(minLength: 20)
                actions
                if isEditing {
                    deleteSection
                }
            }
            .padding(19)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            NBBackButton(action: viewModel.backToList)
            Text(isEditing ? "edit group" : "new group")
                .font(NBFont.ui(13, weight: .bold))
                .foregroundStyle(NBColor.textPrimary)
        }
    }

    private var nameField: some View {
        LabeledField(labelText: "GROUP NAME") {
            TextField("", text: $viewModel.newGroupName, prompt: Text("e.g. Gift cards").foregroundStyle(NBColor.textMuted))
                .textFieldStyle(.plain)
                .font(NBFont.ui(12))
                .foregroundStyle(NBColor.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(NBColor.field)
                .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
        }
        .padding(.top, 13)
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FIELDS — every element shares this shape")
                .nbMonoLabel(9.5, tracking: 0.8)
                .padding(.top, 13)

            VStack(spacing: 6) {
                ForEach($viewModel.newGroupFields) { $field in
                    FieldEditorRow(field: $field) {
                        viewModel.removeNewGroupField(field.id)
                    }
                    .opacity(draggedFieldID == field.id ? 0.4 : 1)
                    .onDrag {
                        draggedFieldID = field.id
                        return NSItemProvider(object: field.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: FieldReorderDropDelegate(
                        targetID: field.id,
                        draggedID: $draggedFieldID,
                        fields: $viewModel.newGroupFields
                    ))
                }
            }

            Button(action: viewModel.addNewGroupField) {
                Text("＋ add field")
                    .font(NBFont.mono(10))
                    .foregroundStyle(NBColor.amber)
            }
            .buttonStyle(.nbPlain)
            .padding(.top, 2)
        }
    }

    private var deleteSection: some View {
        let elementCount = viewModel.activeGroup.elements.count
        return HStack {
            Spacer()
            Button {
                if confirmingDelete {
                    viewModel.deleteGroup(viewModel.editingGroupID ?? "")
                } else {
                    confirmingDelete = true
                }
            } label: {
                Text(confirmingDelete
                     ? "really delete “\(viewModel.activeGroup.label)” and its \(elementCount) element\(elementCount == 1 ? "" : "s")?"
                     : "delete group…")
                    .font(NBFont.mono(9))
                    .foregroundStyle(NBColor.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.red.opacity(confirmingDelete ? 0.8 : 0.35), lineWidth: 1))
            }
            .buttonStyle(.nbPlain)
        }
        .padding(.top, 14)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button(action: viewModel.saveGroup) {
                Text(isEditing ? "save changes" : "create group")
                    .font(NBFont.ui(11.5, weight: .bold))
                    .foregroundStyle(NBColor.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(NBColor.amber)
                    .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
            }
            .buttonStyle(.nbPlain)

            Button(action: viewModel.backToList) {
                Text("cancel")
                    .font(NBFont.ui(11))
                    .foregroundStyle(NBColor.textSecondaryAlt)
                    .frame(width: 80, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.border, lineWidth: 1))
            }
            .buttonStyle(.nbPlain)
        }
    }
}

/// Reorders the fields list live while a row is dragged over its siblings — the standard
/// onDrag/DropDelegate pattern for reordering inside a plain VStack (List's onMove would
/// bring List chrome the carbon design doesn't want).
private struct FieldReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    @Binding var fields: [NBField]

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetID,
              let from = fields.firstIndex(where: { $0.id == draggedID }),
              let to = fields.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            fields.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

private struct FieldEditorRow: View {
    @Binding var field: NBField
    let onRemove: () -> Void

    /// Edited as raw text rather than through a computed binding over `field.options`:
    /// round-tripping the array on every keystroke ate the comma the moment you typed it.
    @State private var optionsDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Text("⋮⋮")
                    .font(NBFont.mono(10))
                    .foregroundStyle(NBColor.textMuted)

                TextField("", text: $field.label)
                    .textFieldStyle(.plain)
                    .font(NBFont.mono(10.5))
                    .foregroundStyle(NBColor.textFieldValue)

                Picker("", selection: $field.type) {
                    ForEach(NBFieldType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(NBFont.mono(9.5))
                .tint(field.type.color)
                .fixedSize()

                Button(action: onRemove) {
                    Text("×")
                        .font(NBFont.mono(12))
                        .foregroundStyle(NBColor.textMuted)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.nbPlain)
                .help("remove field")
            }

            // A picker field with no options is a dead control, so the schema is where its
            // choices get defined — the element form then renders a real menu.
            if field.type == .picker {
                HStack(spacing: 7) {
                    Text("options")
                        .font(NBFont.mono(9, weight: .medium))
                        .foregroundStyle(NBColor.typePicker)
                    TextField("", text: $optionsDraft, prompt: Text("core, premium, limited").foregroundStyle(NBColor.textMuted))
                        .textFieldStyle(.plain)
                        .font(NBFont.mono(10))
                        .foregroundStyle(NBColor.textFieldValue)
                }
                .padding(.leading, 19)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(NBColor.field)
        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
        .onAppear { optionsDraft = field.options.joined(separator: ", ") }
        .onChange(of: optionsDraft) { _, updated in
            field.options = updated
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }
}
