//
//  AddElementView.swift
//  notchboard
//

import SwiftUI

struct AddElementView: View {
    @Bindable var viewModel: NotchboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                form
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
            Text(viewModel.editingElementID == nil ? "new \(viewModel.activeGroup.singular)" : "edit \(viewModel.activeGroup.singular)")
                .font(NBFont.ui(13, weight: .bold))
                .foregroundStyle(NBColor.textPrimary)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField(labelText: "DISPLAY NAME") {
                NBTextField(text: $viewModel.addName, placeholder: "e.g. Expired Card")
            }

            ForEach(viewModel.activeGroup.fields) { field in
                LabeledField(labelText: "\(field.label.uppercased()) · \(field.type.rawValue)") {
                    NBTextField(
                        text: Binding(
                            get: { viewModel.addValues[field.key] ?? "" },
                            set: { viewModel.addValues[field.key] = $0 }
                        ),
                        placeholder: field.type == .secret ? "secret — masked in lists" : (field.type == .bool ? "true / false" : "")
                    )
                }
            }

            LabeledField(labelText: "ENVIRONMENT") {
                HStack(spacing: 6) {
                    ForEach([NBEnvironment.dev, .stg, .prd]) { env in
                        EnvChip(label: env.rawValue, isActive: viewModel.addEnvironment == env) {
                            viewModel.addEnvironment = env
                        }
                    }
                }
            }

            LabeledField(labelText: "NOTE (optional)") {
                NBTextEditor(text: $viewModel.addNote, placeholder: "context a teammate would want, e.g. “no card on file”")
            }
        }
        .padding(.top, 17)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button(action: viewModel.saveElement) {
                Text(viewModel.editingElementID == nil ? "create \(viewModel.activeGroup.singular)" : "save changes")
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

/// Small label + content wrapper matching the prototype's `LABEL` / control stacking.
struct LabeledField<Content: View>: View {
    let labelText: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(labelText)
                .nbMonoLabel(8, tracking: 0.8)
            content()
        }
    }
}

struct NBTextField: View {
    @Binding var text: String
    var placeholder: String = ""

    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(NBColor.textMuted))
            .textFieldStyle(.plain)
            .font(NBFont.mono(10.5))
            .foregroundStyle(NBColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(NBColor.field)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(focused ? NBColor.amber : NBColor.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .focused($focused)
    }
}

struct NBTextEditor: View {
    @Binding var text: String
    var placeholder: String = ""

    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(NBFont.mono(10))
                    .foregroundStyle(NBColor.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            }
            TextEditor(text: $text)
                .font(NBFont.mono(10))
                .foregroundStyle(NBColor.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .focused($focused)
        }
        .frame(height: 52)
        .background(NBColor.field)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(focused ? NBColor.amber : NBColor.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
