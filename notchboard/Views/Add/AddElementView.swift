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
            NBBackButton(action: viewModel.backToList)
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
                    FieldInput(
                        field: field,
                        value: Binding(
                            get: { viewModel.addValues[field.key] ?? "" },
                            set: { viewModel.addValues[field.key] = $0 }
                        )
                    )
                }
            }

            LabeledField(labelText: "ENVIRONMENTS") {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        ForEach(NBEnvironment.assignable) { env in
                            EnvChip(
                                label: env.rawValue,
                                isActive: viewModel.addEnvironments.contains(env),
                                activeColor: env.color
                            ) {
                                toggle(env)
                            }
                        }
                    }
                    Text("pick every environment these values are valid in")
                        .font(NBFont.mono(9))
                        .foregroundStyle(NBColor.textMuted)
                }
            }

            LabeledField(labelText: "NOTE (optional)") {
                NBTextEditor(text: $viewModel.addNote, placeholder: "why this element exists, e.g. “no card on file”")
            }
        }
        .padding(.top, 17)
    }

    /// Toggling an environment is one click, except the one combination worth a second
    /// thought: production alongside anything else (see EnvironmentWarningDialog).
    private func toggle(_ env: NBEnvironment) {
        if viewModel.productionMixWarningNeeded(togglingOn: env) {
            let answer = EnvironmentWarningDialog.confirmProductionMix(elementName: viewModel.addName)
            if answer.suppressFuture { viewModel.suppressProductionMixWarning = true }
            guard answer.confirmed else { return }
        }
        viewModel.toggleAddEnvironment(env)
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

/// The control a field's type deserves. A `bool` gets two states to choose between, a
/// `picker` gets its group's options, a `number` refuses letters as you type, and
/// everything else is a text field with a placeholder that says what's expected. Values
/// are still validated on save (NBFieldValidation) — controls shape input, they don't
/// guarantee it, since imports and hand-edited files bypass them entirely.
private struct FieldInput: View {
    let field: NBField
    @Binding var value: String

    var body: some View {
        switch field.type {
        case .bool:
            BoolSelector(value: $value)
        case .picker where !field.options.isEmpty:
            OptionSelector(options: field.options, value: $value)
        default:
            NBTextField(text: $value, placeholder: field.type.placeholder)
                .onChange(of: value) { _, updated in
                    // Filtering here rather than rejecting on save keeps the field honest
                    // while typing: a stray letter in a price simply never appears.
                    let filtered = NBFieldValidation.filtered(updated, for: field.type)
                    if filtered != updated { value = filtered }
                }
        }
    }
}

/// true / false as two chips. Tapping the active one clears the value, because a bool that
/// was never set is a real state ("unknown") and the old free-text field could express it.
private struct BoolSelector: View {
    @Binding var value: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(NBFieldValidation.boolValues, id: \.self) { option in
                EnvChip(
                    label: option,
                    isActive: value.lowercased() == option,
                    activeColor: option == "true" ? NBColor.green : NBColor.textSecondaryAlt
                ) {
                    value = value.lowercased() == option ? "" : option
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A real picker for `picker` fields, driven by the options defined on the group's schema.
private struct OptionSelector: View {
    let options: [String]
    @Binding var value: String

    private static let noneTag = ""

    var body: some View {
        Picker("", selection: $value) {
            Text("—").tag(Self.noneTag)
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(NBFont.mono(10.5))
        .tint(NBColor.amber)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small label + content wrapper matching the prototype's `LABEL` / control stacking.
struct LabeledField<Content: View>: View {
    let labelText: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(labelText)
                .nbMonoLabel(9.5, tracking: 0.8)
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
            .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(focused ? NBColor.amber : NBColor.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
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
        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(focused ? NBColor.amber : NBColor.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
    }
}
