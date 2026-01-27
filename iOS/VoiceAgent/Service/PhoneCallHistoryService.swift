//
//  PhoneCallHistoryService.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation

/// 电话号码历史记录服务
class PhoneCallHistoryService {
    private static let userDefaultsKey = "phoneCallHistory"
    private static let maxHistoryCount = 50 // 最多保存50条记录
    
    /// 保存电话号码记录
    /// - Parameter record: 电话号码记录
    static func saveRecord(_ record: PhoneCallRecord) {
        var records = loadAllRecords()
        
        // 检查是否已存在相同的电话号码
        if let existingIndex = records.firstIndex(where: { $0.phoneNumber == record.phoneNumber }) {
            // 更新现有记录
            var updatedRecord = records[existingIndex]
            updatedRecord.lastCalledAt = Date()
            // 如果新记录有备注且旧记录没有，则更新备注
            if !record.note.isEmpty && updatedRecord.note.isEmpty {
                updatedRecord.note = record.note
            }
            records[existingIndex] = updatedRecord
        } else {
            // 添加新记录
            records.insert(record, at: 0)
        }
        
        // 限制记录数量
        if records.count > maxHistoryCount {
            records = Array(records.prefix(maxHistoryCount))
        }
        
        // 保存到 UserDefaults
        saveRecords(records)
    }
    
    /// 更新记录的备注
    /// - Parameters:
    ///   - recordId: 记录ID
    ///   - note: 新的备注
    static func updateNote(recordId: UUID, note: String) {
        var records = loadAllRecords()
        if let index = records.firstIndex(where: { $0.id == recordId }) {
            records[index].note = note
            saveRecords(records)
        }
    }
    
    /// 删除记录
    /// - Parameter recordId: 记录ID
    static func deleteRecord(recordId: UUID) {
        var records = loadAllRecords()
        records.removeAll { $0.id == recordId }
        saveRecords(records)
    }
    
    /// 加载所有记录
    /// - Returns: 电话号码记录数组，按最后拨打时间倒序排列
    static func loadAllRecords() -> [PhoneCallRecord] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let records = try decoder.decode([PhoneCallRecord].self, from: data)
            // 按最后拨打时间倒序排列
            return records.sorted { $0.lastCalledAt > $1.lastCalledAt }
        } catch {
            print("Failed to load phone call history: \(error.localizedDescription)")
            return []
        }
    }
    
    /// 保存记录数组到 UserDefaults
    /// - Parameter records: 记录数组
    private static func saveRecords(_ records: [PhoneCallRecord]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Failed to save phone call history: \(error.localizedDescription)")
        }
    }
    
    /// 清空所有历史记录
    static func clearAllRecords() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

