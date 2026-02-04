//
//  LiveKitRoomView.swift
//  VoiceAgent
//
//  Created by WangSimin on 12/25/25.
//

import SwiftUI
import LiveKit

struct LiveKitRoomView: View {

    // If manager is owned by parent, use ObservedObject initializer below.
    @ObservedObject private var manager: LiveKitManager

    let roomUrl: String
    let token: String
    let shortCode: String?
    let bankPhoneNumber: String?
    let bootstrapPayload: LiveKitBootstrapPayload?

    @Environment(\.dismiss) private var dismiss
    @State private var messageText: String = ""
    @State private var showCallAlert = false
    @State private var callAlertMessage = ""

    // Use something stable; ideally pass from login/profile
    private let displayName = "iOS User"
    @State private var sendAsOverride: Bool = true
    private let liveKitPhoneNumber = AppConfig.liveKitPhoneNumber

    // MARK: - Initializers

    /// Use this when parent owns/creates manager.
    init(
        manager: LiveKitManager,
        roomUrl: String,
        token: String,
        shortCode: String? = nil,
        bankPhoneNumber: String? = nil,
        bootstrapPayload: LiveKitBootstrapPayload? = nil
    ) {
        self.manager = manager
        self.roomUrl = roomUrl
        self.token = token
        self.shortCode = shortCode
        self.bankPhoneNumber = bankPhoneNumber
        self.bootstrapPayload = bootstrapPayload
        self.manager.pendingBootstrapPayload = bootstrapPayload
    }

    var body: some View {
        VStack(spacing: 12) {

            header

            Divider()

            participantsRow

            chatTranscript

            inputBar

            if let bankPhone = bankPhoneNumber, !bankPhone.isEmpty {
                callBridgeSection(bankPhone: bankPhone)
            }

            hangupButton
        }
        .onAppear {
            Task { await manager.connect(roomUrl: roomUrl, token: token) }
        }
        .onDisappear {
            // Optional: avoid leaving the room running if user navigates away
            // If you don't want this behavior, remove it.
            manager.disconnect()
        }
        .alert("Call Status", isPresented: $showCallAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(callAlertMessage)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            Text("智能语音客服")
                .font(.title2).fontWeight(.semibold)

            if manager.isConnected {
                Text("已连接到客服房间")
                    .foregroundStyle(.green)
            } else if let err = manager.errorMessage {
                Text(err)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("Connecting…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
    }

    private var participantsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Participants:")
                    .foregroundStyle(.secondary)

                ForEach(manager.participants, id: \.self) { p in
                    Text(p)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
        }
    }

    private var chatTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(manager.messages) { m in
                        ChatBubbleRow(message: m)
                            .id(m.id)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .modifier(ScrollToBottomOnMessagesChange(proxy: proxy, messages: manager.messages))
        }
    }

    private var inputBar: some View {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 10) {
            Button {
                sendAsOverride.toggle()
            } label: {
                Image(systemName: sendAsOverride ? "megaphone.fill" : "person.fill")
            }
            .accessibilityLabel(sendAsOverride ? "Send as agent override" : "Send as user")

            TextField("Type a message…", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            Button {
                manager.sendChat(text: trimmed, displayName: displayName, asOverride: sendAsOverride)
                messageText = ""
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(!manager.isConnected || trimmed.isEmpty)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func callBridgeSection(bankPhone: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Call setup")
                .font(.headline)
                .padding(.horizontal)

//            VStack(alignment: .leading, spacing: 10) {
//                Text("1. Call your bank from the Phone app (or tap below).")
//                Text("2. After the bank answers, tap “Add Call”.")
//                Text("3. Dial the LiveKit number and wait for it to answer.")
//                if let code = shortCode, !code.isEmpty {
//                    Text("4. Enter code \(code), then press #.")
//                }
//                Text("5. Merge the calls so the agent hears both sides.")
//            }
//            .font(.subheadline)
//            .foregroundStyle(.secondary)
//            .padding(.horizontal)

            VStack(spacing: 10) {
                callButton(title: "Call Bank", number: bankPhone, color: .blue)
                callButton(title: "Call LiveKit Number", number: liveKitPhoneNumber, color: .purple)
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }

    private var hangupButton: some View {
        Button(role: .destructive) {
            manager.disconnect()
            dismiss()
        } label: {
            HStack {
                Image(systemName: "phone.down.fill")
                Text("挂断")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.red)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Call Helpers

    private func callButton(title: String, number: String, color: Color) -> some View {
        Button {
            initiatePhoneCall(title: title, number: number)
        } label: {
            HStack {
                Image(systemName: "phone.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.semibold)
                    Text(PhoneCallService.formatPhoneNumber(number))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal)
            .background(color)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!manager.isConnected)
    }

    private func initiatePhoneCall(title: String, number: String) {
        guard PhoneCallService.isValidPhoneNumber(number) else {
            callAlertMessage = "Invalid phone number for \(title)."
            showCallAlert = true
            return
        }

        let didStart = PhoneCallService.makePhoneCallWithPrompt(number)
        if !didStart {
            callAlertMessage = "Unable to start the \(title.lowercased()) call."
            showCallAlert = true
        }
    }

    // MARK: - Bubble

//    @ViewBuilder
//    private func chatBubble(_ m: LiveKitChatMessage) -> some View {
//        VStack(alignment: .leading, spacing: 4) {
//            Text(m.from)
//                .font(.caption)
//                .foregroundStyle(.secondary)
//
//            Text(m.text)
//                .padding(10)
//                .background(Color(.systemGray6))
//                .clipShape(RoundedRectangle(cornerRadius: 12))
//        }
//    }
}

// MARK: - Scroll helper (handles iOS 16/17 onChange signature differences)

private struct ScrollToBottomOnMessagesChange: ViewModifier {
    let proxy: ScrollViewProxy
    let messages: [LiveKitChatMessage]

    func body(content: Content) -> some View {
        content
            .onChange(of: messages.count) { _ in
                scroll()
            }
    }

    private func scroll() {
        guard let last = messages.last else { return }
        // Dispatch to next runloop so layout is ready
        DispatchQueue.main.async {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
