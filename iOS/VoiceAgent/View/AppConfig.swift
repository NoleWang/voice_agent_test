//
//  AppConfig.swift
//  VoiceAgent
//
//  Created by WangSimin on 12/25/25.
//

import Foundation

enum AppConfig {

    static var liveKitURL: String {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "LIVEKIT_URL"
        ) as? String else {
            fatalError("LIVEKIT_URL missing in Info.plist")
        }
        return value
    }

    static var liveKitRoom: String {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "LIVEKIT_ROOM"
        ) as? String else {
            fatalError("LIVEKIT_ROOM missing in Info.plist")
        }
        return value
    }
    
    static var liveAPIKey: String {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "LIVEKIT_API_KEY"
        ) as? String else {
            fatalError("LIVEKIT_API_KEY missing in Info.plist")
        }
        return value
    }
}
