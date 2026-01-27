//
//  LiveKitChatMessage.swift
//  VoiceAgent
//
//  Created by WangSimin on 1/6/26.
//

import Foundation

/// Canonical chat message model for LiveKit DataPackets.
/// Compatible with Python payload:
/// {
///   "id": "...",
///   "from": "agent",
///   "text": "Hello",
///   "timestamp": 1736200000.123
/// }
struct LiveKitChatMessage: Identifiable, Codable, Equatable {

    let id: String
    let from: String
    let text: String
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        from: String,
        text: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.from = from
        self.text = text
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case from
        case sender
        case name
        case text
        case message
        case timestamp
    }

    /// Custom decoder so we never silently fail.
    /// Supports:
    /// - JSON object payloads (normal path)
    /// - plain string payloads (fallback path)
    init(from decoder: Decoder) throws {
        // 1) Try keyed container (JSON object)
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString

            self.from =
                (try? c.decode(String.self, forKey: .from))
                ?? (try? c.decode(String.self, forKey: .sender))
                ?? (try? c.decode(String.self, forKey: .name))
                ?? "unknown"

            self.text =
                (try? c.decode(String.self, forKey: .text))
                ?? (try? c.decode(String.self, forKey: .message))
                ?? ""

            if let d = try? c.decode(Double.self, forKey: .timestamp) {
                self.timestamp = Date(timeIntervalSince1970: d)
            } else if let i = try? c.decode(Int.self, forKey: .timestamp) {
                self.timestamp = Date(timeIntervalSince1970: TimeInterval(i))
            } else if let s = try? c.decode(String.self, forKey: .timestamp),
                      let d = Double(s) {
                self.timestamp = Date(timeIntervalSince1970: d)
            } else if let date = try? c.decode(Date.self, forKey: .timestamp) {
                self.timestamp = date
            } else {
                self.timestamp = Date()
            }
            return
        }

        // 2) Fallback: single value container (plain string payload)
        let single = try decoder.singleValueContainer()
        let raw = (try? single.decode(String.self)) ?? ""
        self.id = UUID().uuidString
        self.from = "unknown"
        self.text = raw
        self.timestamp = Date()
    }

    /// Encoder always matches Python `time.time()` (unix seconds)
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(from, forKey: .from)
        try c.encode(text, forKey: .text)
        try c.encode(timestamp.timeIntervalSince1970, forKey: .timestamp)
    }
}

extension LiveKitChatMessage {
    var role: ChatRole {
        let f = from.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if f == "system" { return .system }

        // Your backend uses "agent" (and sometimes agent-xxx). Handle both.
        if f == "agent" || f.hasPrefix("agent") { return .agent }

        // If you want customer messages to be "me":
        if f == "ios user" || f.hasPrefix("customer") { return .me }

        return .other
    }
}
