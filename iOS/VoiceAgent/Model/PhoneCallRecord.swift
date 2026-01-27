//
//  PhoneCallRecord.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation

/// 电话号码记录数据模型
struct PhoneCallRecord: Codable, Identifiable {
    let id: UUID
    var phoneNumber: String
    var note: String
    var createdAt: Date
    var lastCalledAt: Date
    
    init(phoneNumber: String, note: String = "", id: UUID = UUID(), createdAt: Date = Date(), lastCalledAt: Date = Date()) {
        self.id = id
        self.phoneNumber = phoneNumber
        self.note = note
        self.createdAt = createdAt
        self.lastCalledAt = lastCalledAt
    }
    
    /// 格式化显示的电话号码
    var formattedPhoneNumber: String {
        return PhoneCallService.formatPhoneNumber(phoneNumber)
    }
    
    /// 显示名称（如果有备注则显示备注，否则显示格式化的电话号码）
    var displayName: String {
        return note.isEmpty ? formattedPhoneNumber : note
    }
}

