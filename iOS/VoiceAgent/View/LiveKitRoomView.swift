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
    let bankPhoneNumber: String?
    let roomName: String

    @Environment(\.dismiss) private var dismiss
    @State private var messageText: String = ""
    @State private var isCallingBank = false
    @State private var bankCallStatus: String? = nil
    @State private var showCallAlert = false
    @State private var callAlertMessage = ""

    // Use something stable; ideally pass from login/profile
    private let displayName = "iOS User"

    // MARK: - Initializers

    /// Use this when parent owns/creates manager.
    init(manager: LiveKitManager, roomUrl: String, token: String, bankPhoneNumber: String? = nil, roomName: String = "") {
        self.manager = manager
        self.roomUrl = roomUrl
        self.token = token
        self.bankPhoneNumber = bankPhoneNumber
        self.roomName = roomName
    }

    var body: some View {
        VStack(spacing: 12) {

            header

            Divider()

            participantsRow

            chatTranscript

            inputBar

            // Show call bank button if bank phone number is available
            if let bankPhone = bankPhoneNumber, !bankPhone.isEmpty {
                callBankButton
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
            TextField("Type a message…", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            Button {
                manager.sendChat(text: trimmed, displayName: displayName)
                messageText = ""
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(!manager.isConnected || trimmed.isEmpty)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private var callBankButton: some View {
        Button {
            Task {
                await callBank()
            }
        } label: {
            HStack {
                if isCallingBank {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "phone.fill")
                }
                Text(isCallingBank ? "Calling..." : (bankCallStatus != nil ? "Call Connected" : "Call Bank"))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(bankCallStatus != nil ? Color.green : Color.blue)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
        .disabled(isCallingBank || bankCallStatus != nil || !manager.isConnected)
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

    // MARK: - SIP Call

    private func callBank() async {
        guard let phoneNumber = bankPhoneNumber, !phoneNumber.isEmpty, !roomName.isEmpty else {
            await MainActor.run {
                callAlertMessage = "Bank phone number or room name is missing"
                showCallAlert = true
            }
            return
        }

        await MainActor.run {
            isCallingBank = true
            bankCallStatus = nil
        }

        do {
            let response = try await LiveKitTokenAPI.createSIPOutboundCall(
                room: roomName,
                phoneNumber: phoneNumber
            )

            await MainActor.run {
                isCallingBank = false
                if response.success {
                    bankCallStatus = response.participant_identity ?? "connected"
                    callAlertMessage = response.message ?? "Call initiated successfully"
                } else {
                    callAlertMessage = response.message ?? "Failed to initiate call"
                    showCallAlert = true
                }
            }
        } catch {
            await MainActor.run {
                isCallingBank = false
                callAlertMessage = "Failed to call bank: \(error.localizedDescription)"
                showCallAlert = true
            }
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
