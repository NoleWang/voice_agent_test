//
//  EncryptionService.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation
import CryptoKit
import UIKit

class EncryptionService {
    // 生成加密密钥（使用设备的唯一标识）
    private static func getEncryptionKey() -> SymmetricKey {
        // 使用设备的唯一标识符作为密钥源
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "default-device-id"
        guard let keyData = deviceId.data(using: .utf8) else {
            // 如果无法获取设备ID，使用默认密钥
            let defaultKey = "default-encryption-key".data(using: .utf8)!
            let hashed = SHA256.hash(data: defaultKey)
            return SymmetricKey(data: hashed)
        }
        
        // 使用 SHA256 生成固定长度的密钥
        let hashed = SHA256.hash(data: keyData)
        return SymmetricKey(data: hashed)
    }
    
    // 加密数据
    static func encrypt(_ data: Data) throws -> Data {
        let key = getEncryptionKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        
        // 返回加密后的数据（nonce + ciphertext + tag）
        guard let encrypted = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }
        return encrypted
    }
    
    // 解密数据
    static func decrypt(_ encryptedData: Data) throws -> Data {
        let key = getEncryptionKey()
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decrypted = try AES.GCM.open(sealedBox, using: key)
        return decrypted
    }
    
    // 加密字符串
    static func encryptString(_ string: String) throws -> String {
        guard let data = string.data(using: .utf8) else {
            throw EncryptionError.invalidData
        }
        let encrypted = try encrypt(data)
        return encrypted.base64EncodedString()
    }
    
    // 解密字符串
    static func decryptString(_ encryptedString: String) throws -> String {
        guard let data = Data(base64Encoded: encryptedString) else {
            throw EncryptionError.invalidData
        }
        let decrypted = try decrypt(data)
        guard let string = String(data: decrypted, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }
        return string
    }
}

enum EncryptionError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Encryption failed"
        case .decryptionFailed:
            return "Decryption failed"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

