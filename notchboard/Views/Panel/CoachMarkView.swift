//
//  CoachMarkView.swift
//  notchboard
//

import SwiftUI

struct CoachMarkView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("docked ✓")
                .font(NBFont.mono(9))
                .foregroundStyle(NBColor.green)

            Text("Notchboard found your Simulator and attached itself. Click the notch to open the team catalogue.")
                .font(NBFont.ui(11))
                .foregroundStyle(NBColor.textFieldValue)
                .lineSpacing(4)

            Button(action: onDone) {
                Text("got it")
                    .font(NBFont.mono(9))
                    .foregroundStyle(NBColor.amber)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(NBColor.amber.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(13)
        .frame(width: 198)
        .background(NBColor.chip)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(NBColor.amber.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.7), radius: 50, y: 20)
    }
}

#Preview {
    ZStack {
        NBColor.background
        CoachMarkView(onDone: {})
    }
    .frame(width: 300, height: 200)
}
