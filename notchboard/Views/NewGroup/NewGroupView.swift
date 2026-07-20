//
//  NewGroupView.swift
//  notchboard
//

import SwiftUI

struct NewGroupView: View {
    @Bindable var viewModel: NotchboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                nameField
                fieldsSection
                Spacer(minLength: 20)
                actions
            }
            .padding(19)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button(action: viewModel.backToList) {
                Text("←")
                    .font(NBFont.ui(13))
                    .foregroundStyle(NBColor.textSecondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            Text("new group")
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
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(NBColor.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(.top, 13)
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FIELDS — every element shares this shape")
                .nbMonoLabel(8, tracking: 0.8)
                .padding(.top, 13)

            VStack(spacing: 6) {
                ForEach($viewModel.newGroupFields) { $field in
                    FieldEditorRow(field: $field) {
                        viewModel.removeNewGroupField(field.id)
                    }
                }
            }

            Button(action: viewModel.addNewGroupField) {
                Text("＋ add field")
                    .font(NBFont.mono(10))
                    .foregroundStyle(NBColor.amber)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button(action: viewModel.createGroup) {
                Text("create group")
                    .font(NBFont.ui(11.5, weight: .bold))
                    .foregroundStyle(NBColor.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(NBColor.amber)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)

            Button(action: viewModel.backToList) {
                Text("cancel")
                    .font(NBFont.ui(11))
                    .foregroundStyle(NBColor.textSecondaryAlt)
                    .frame(width: 80, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(NBColor.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct FieldEditorRow: View {
    @Binding var field: NBField
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Text("⋮⋮")
                .font(NBFont.mono(9))
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
            .font(NBFont.mono(8.5))
            .tint(field.type.color)
            .fixedSize()

            Button(action: onRemove) {
                Text("×")
                    .font(NBFont.mono(10))
                    .foregroundStyle(NBColor.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(NBColor.field)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(NBColor.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
