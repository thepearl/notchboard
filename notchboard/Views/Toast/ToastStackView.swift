//
//  ToastStackView.swift
//  notchboard
//

import SwiftUI

struct ToastStackView: View {
    let toasts: [NBToast]

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            ForEach(toasts) { toast in
                ToastRow(toast: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toasts)
    }
}

private struct ToastRow: View {
    let toast: NBToast

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(toast.color.color)
                .frame(width: 6, height: 6)
            Text(toast.message)
                .font(NBFont.mono(9.5))
                .foregroundStyle(NBColor.textFieldValue)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NBColor.chip)
        .overlay(
            RoundedRectangle(cornerRadius: NBMetrics.toastCornerRadius)
                .stroke(NBColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.toastCornerRadius))
        .shadow(color: .black.opacity(0.6), radius: 34, y: 14)
    }
}

#Preview {
    ZStack {
        NBColor.background
        ToastStackView(toasts: [
            NBToast(id: UUID(), message: "username copied to clipboard", color: .amber),
            NBToast(id: UUID(), message: "released “Ava Lindqvist”", color: .green),
            NBToast(id: UUID(), message: "sara marked this in use — take it over from the detail view", color: .amber),
        ])
        .padding(22)
    }
    .frame(width: 320, height: 220)
}
