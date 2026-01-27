//
//  KeychainService.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation
import Security
import CryptoKit

// 用户信息数据模型
struct UserInfo: Codable {
    let username: String
    let firstName: String
    let lastName: String
    let email: String
    let phone: String
    let address: String
    let timestamp: Date
    
    init(username: String, firstName: String, lastName: String, email: String, phone: String, address: String) {
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.address = address
        self.timestamp = Date()
    }
    
    var fullName: String {
        return "\(firstName) \(lastName)"
    }
}

class KeychainService {
    private static let service = "com.voiceagent.userinfo"
    private static let account = "userInformation"
    private static let passwordAccount = "userPassword"
    
    // 保存用户信息到 Keychain（加密存储）
    static func saveUserInfo(_ userInfo: UserInfo) throws {
        // 将用户信息编码为 JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(userInfo)
        
        // 加密数据
        let encryptedData = try EncryptionService.encrypt(data)
        
        // 准备 Keychain 查询
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: encryptedData
        ]
        
        // 删除旧数据（如果存在）
        SecItemDelete(query as CFDictionary)
        
        // 添加新数据
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    // 从 Keychain 加载用户信息（解密）
    static func loadUserInfo() throws -> UserInfo? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.loadFailed(status)
        }
        
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }
        
        // 解密数据
        let decryptedData = try EncryptionService.decrypt(data)
        
        // 解码 JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UserInfo.self, from: decryptedData)
    }
    
    // 删除用户信息
    static func deleteUserInfo() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    // 检查用户信息是否存在
    static func userInfoExists() -> Bool {
        do {
            return try loadUserInfo() != nil
        } catch {
            return false
        }
    }
    
    // 保存密码（使用哈希存储）
    static func savePassword(_ password: String) throws {
        // 使用 SHA256 哈希密码
        let passwordData = password.data(using: .utf8)!
        let hashed = SHA256.hash(data: passwordData)
        let hashedData = Data(hashed)
        
        // 加密哈希后的密码
        let encryptedData = try EncryptionService.encrypt(hashedData)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
            kSecValueData as String: encryptedData
        ]
        
        // 删除旧密码（如果存在）
        SecItemDelete(query as CFDictionary)
        
        // 添加新密码
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    // 验证密码
    static func verifyPassword(_ password: String) throws -> Bool {
        // 计算输入密码的哈希
        let passwordData = password.data(using: .utf8)!
        let hashed = SHA256.hash(data: passwordData)
        let inputHashedData = Data(hashed)
        
        // 从 Keychain 加载存储的密码哈希
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return false
            }
            throw KeychainError.loadFailed(status)
        }
        
        guard let encryptedData = result as? Data else {
            throw KeychainError.invalidData
        }
        
        // 解密存储的密码哈希
        let storedHashedData = try EncryptionService.decrypt(encryptedData)
        
        // 比较哈希值
        return inputHashedData == storedHashedData
    }
    
    // 检查密码是否已设置
    static func passwordExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain. Status: \(status)"
        case .loadFailed(let status):
            return "Failed to load from Keychain. Status: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain. Status: \(status)"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

