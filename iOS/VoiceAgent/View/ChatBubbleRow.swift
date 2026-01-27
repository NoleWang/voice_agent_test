//
//  ChatBubbleRow.swift
//  VoiceAgent
//
//  Created by WangSimin on 1/8/26.
//

import SwiftUI

enum ChatRole {
    case system
    case me
    case agent
    case other
}

struct ChatBubbleRow: View {
    let message: LiveKitChatMessage

    var body: some View {
        switch message.role {
        case .system:
            systemRow

        case .agent:
            bubbleRow(
                alignRight: true,
                senderLabel: "me",
                bubble: AnyView(agentBubble)
            )

        case .me:
            bubbleRow(
                alignRight: false,
                senderLabel: "Customer Service",
                bubble: AnyView(userBubble)
            )

        case .other:
            bubbleRow(
                alignRight: false,
                senderLabel: message.from,
                bubble: AnyView(userBubble)
            )
        }
    }

    // MARK: - Bubbles

    private var userBubble: some View {
        Text(message.text)
            .font(.body)
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var agentBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text("Agent")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white.opacity(0.95))

            Text(message.text)
                .font(.body)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.blue)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var systemRow: some View {
        HStack {
            Spacer()
            Text(message.text)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
    }

    // MARK: - Layout wrapper

    private func bubbleRow(
        alignRight: Bool,
        senderLabel: String,
        bubble: AnyView
    ) -> some View {
        HStack(alignment: .bottom) {
            if alignRight { Spacer(minLength: 40) }

            VStack(alignment: alignRight ? .trailing : .leading, spacing: 4) {
                Text(senderLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(alignRight ? .trailing : .leading, 4)

                bubble
            }
            .frame(maxWidth: 280, alignment: alignRight ? .trailing : .leading)

            if !alignRight { Spacer(minLength: 40) }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
    }
}
