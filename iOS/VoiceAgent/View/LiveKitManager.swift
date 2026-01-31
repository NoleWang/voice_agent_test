//
//  LiveKitManager.swift
//  VoiceAgent
//
//  LiveKit “Sandbox-like chat” + Microphone publish
//  - DataPackets: reliable topic="chat"
//  - Timestamp: Unix seconds (matches Python time.time())
//  - URL hardening: strips invisible unicode spaces + normalizes ws/wss
//  - Mic: iOS15+ compatible permission request; stores LocalTrackPublication for clean unpublish
/// - Ensures ALL @Published mutations happen on MainActor (fixes dropped UI updates)
/// - Robust chat receive: decode JSON payload, and if decode fails, parse JSON manually (so Echo always shows)
/// - Encodes/decodes timestamps as Unix seconds to match Python time.time()
//  Created by WangSimin on 12/24/25.

import Foundation
import Combine
import AVFoundation
import LiveKit

@MainActor
final class LiveKitManager: ObservableObject {

    // MARK: - Published UI state
    @Published var isConnected: Bool = false
    @Published var errorMessage: String?
    @Published var participants: [String] = []
    @Published var messages: [LiveKitChatMessage] = []
    @Published var isMicOn: Bool = false

    // MARK: - LiveKit
    private(set) var room: Room = Room()
    private let chatTopic = "chat"
    private let bootstrapTopic = "bootstrap"

    var pendingBootstrapPayload: LiveKitBootstrapPayload?

    // MARK: - Audio
    private let audioSession = AVAudioSession.sharedInstance()
    private var micPublication: LocalTrackPublication?

    init() {
        room.add(delegate: self)
    }

    // MARK: - Connection

    func connect(roomUrl: String, token: String) async {
        errorMessage = nil

        let cleaned = Self.normalizeLiveKitURL(roomUrl)
        guard let url = URL(string: cleaned), url.host != nil else {
            errorMessage = "Failed to parse URL (\(cleaned))"
            isConnected = false
            return
        }

        let hasMicPermission = await requestMicPermission()
        guard hasMicPermission else {
            errorMessage = "Microphone permission denied. Enable access in Settings to start a call."
            isConnected = false
            return
        }

        do {
            // Force autoSubscribe ON so data/remote tracks are received.
            let opts = ConnectOptions(autoSubscribe: true)

            // LiveKit API accepts String URL; we already validated as URL above.
            try await room.connect(url: cleaned, token: token, connectOptions: opts)

            isConnected = true
            refreshParticipants()

            // Optional: start mic automatically
            await enableMicrophone(skipPermissionCheck: true)

            await sendPendingBootstrapPayload()

            // Avoid duplicate “Connected” spam if reconnect triggers delegate too
            if messages.last?.text != "Connected" {
                messages.append(.init(from: "system", text: "Connected"))
            }
        } catch {
            isConnected = false
            errorMessage = "Failed to connect: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        Task { @MainActor in
            await disableMicrophone()
            await room.disconnect()
            isConnected = false
            micPublication = nil
            isMicOn = false
            refreshParticipants()
        }
    }

    // MARK: - Chat (send)

    func sendChat(text: String, displayName: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let msg = LiveKitChatMessage(from: displayName, text: trimmed)

        Task { @MainActor in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970

                let data = try encoder.encode(msg)
                let opts = DataPublishOptions(topic: chatTopic, reliable: true)

                try await room.localParticipant.publish(data: data, options: opts)

                // Optimistic local echo (typed messages)
//                messages.append(msg)
                print("📤 iOS sent chat:", trimmed)
            } catch {
                errorMessage = "Send failed: \(error.localizedDescription)"
            }
        }
    }

    func sendBootstrapPayload(_ payload: LiveKitBootstrapPayload) async {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(payload)
            let opts = DataPublishOptions(topic: bootstrapTopic, reliable: true)
            try await room.localParticipant.publish(data: data, options: opts)
            print("📤 iOS sent bootstrap payload")
        } catch {
            errorMessage = "Bootstrap send failed: \(error.localizedDescription)"
        }
    }

    private func sendPendingBootstrapPayload() async {
        guard let payload = pendingBootstrapPayload else { return }
        pendingBootstrapPayload = nil
        await sendBootstrapPayload(payload)
    }

    // MARK: - Participants

    private func refreshParticipants() {
        var names: [String] = []

        names.append(room.localParticipant.identity?.stringValue ?? "local")

        for (_, p) in room.remoteParticipants {
            names.append(p.identity?.stringValue ?? "remote")
        }

        participants = Array(Set(names)).sorted()
    }

    // MARK: - Microphone

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            audioSession.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func enableMicrophone(skipPermissionCheck: Bool = false) async {
        do {
            if !skipPermissionCheck {
                let granted = await requestMicPermission()
                guard granted else {
                    errorMessage = "Microphone permission denied"
                    return
                }
            }

            // allowBluetooth is deprecated; use allowBluetoothHFP
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .defaultToSpeaker,
                    .allowBluetoothHFP,
                    .allowBluetoothA2DP
                ]
            )
            try audioSession.setActive(true)

            let track = LocalAudioTrack.createTrack()
            micPublication = try await room.localParticipant.publish(audioTrack: track)
            isMicOn = true
        } catch {
            errorMessage = "Mic start failed: \(error.localizedDescription)"
            isMicOn = false
            await room.disconnect()
            isConnected = false
            refreshParticipants()
        }
    }

    func disableMicrophone() async {
        do {
            if let pub = micPublication {
                try await room.localParticipant.unpublish(publication: pub)
                micPublication = nil
            }
            isMicOn = false
        } catch {
            errorMessage = "Mic stop failed: \(error.localizedDescription)"
        }
    }

    // MARK: - URL Normalization

    static func normalizeLiveKitURL(_ input: String) -> String {
        let extra = CharacterSet(charactersIn: "\u{00A0}\u{202F}\u{2007}\u{200B}")
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines.union(extra))

        s = s
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{2007}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")

        if s == "wss://" || s == "ws://" { return s }

        if s.hasPrefix("https://") { s = "wss://" + s.dropFirst("https://".count) }
        if s.hasPrefix("http://")  { s = "ws://"  + s.dropFirst("http://".count)  }

        if !s.hasPrefix("wss://") && !s.hasPrefix("ws://") {
            s = "wss://" + s
        }

        return s
    }

    // MARK: - Decode

    private func decodeChatMessage(from data: Data, fallbackSender: String) -> LiveKitChatMessage {
        // 1) Decode canonical model (your LiveKitChatMessage supports aliases)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(LiveKitChatMessage.self, from: data)
        } catch {
            // 2) Dictionary fallback
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let from = (obj["from"] as? String)
                    ?? (obj["sender"] as? String)
                    ?? (obj["name"] as? String)
                    ?? fallbackSender

                let text = (obj["text"] as? String)
                    ?? (obj["message"] as? String)
                    ?? String(data: data, encoding: .utf8)
                    ?? "<non-utf8>"

                let ts = obj["timestamp"]
                let date: Date
                if let t = ts as? Double {
                    date = Date(timeIntervalSince1970: t)
                } else if let t = ts as? Int {
                    date = Date(timeIntervalSince1970: TimeInterval(t))
                } else if let t = ts as? String, let d = Double(t) {
                    date = Date(timeIntervalSince1970: d)
                } else {
                    date = Date()
                }

                return LiveKitChatMessage(from: from, text: text, timestamp: date)
            }

            // 3) Plain text fallback
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            return LiveKitChatMessage(from: fallbackSender, text: raw)
        }
    }

    // MARK: - Central handler (topic/participant may be nil depending on SDK/build)

    private func handleIncomingData(_ data: Data, participant: RemoteParticipant?, topic: String?) {
        let t = (topic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Some 2.10.x builds deliver nil/empty topic; don’t drop it.
        if !(t.isEmpty || t == chatTopic) {
            print("📩 iOS received non-chat topic=\(t) bytes=\(data.count)")
            return
        }

        // participant is often nil for server/agent published data
        let sender = participant?.identity?.stringValue ?? "server"

        let msg = decodeChatMessage(from: data, fallbackSender: sender)
        messages.append(msg)

        print("📩 iOS received chat:",
              msg.from, ":", msg.text,
              "topic:", t.isEmpty ? "<nil/empty>" : t,
              "participant:", participant?.identity?.stringValue ?? "<nil>")
    }
}

// MARK: - RoomDelegate (LiveKit iOS 2.10.2)

extension LiveKitManager: RoomDelegate {

    nonisolated func room(_ room: Room,
                          didUpdate connectionState: ConnectionState,
                          oldState: ConnectionState) {
        Task { @MainActor in
            switch connectionState {
            case .connected:
                self.isConnected = true
                self.errorMessage = nil
                self.refreshParticipants()
            case .disconnected:
                self.isConnected = false
                self.refreshParticipants()
                self.isMicOn = false
                self.micPublication = nil
            default:
                break
            }
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in self.refreshParticipants() }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in self.refreshParticipants() }
    }

    /// ✅ Match RoomDelegate optional requirement AND expose to Obj-C
    @objc
    nonisolated func room(_ room: Room,
                          participant: RemoteParticipant?,
                          didReceiveData data: Data,
                          forTopic topic: String,
                          encryptionType: EncryptionType) {
        Task { @MainActor in
            self.handleIncomingData(data, participant: participant, topic: topic)
        }
    }
}
