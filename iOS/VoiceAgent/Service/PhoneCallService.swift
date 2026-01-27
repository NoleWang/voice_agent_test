//
//  PhoneCallService.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation
import UIKit

class PhoneCallService {
    /// 拨打电话号码
    /// - Parameter phoneNumber: 要拨打的电话号码
    /// - Returns: 是否成功发起呼叫
    static func makePhoneCall(_ phoneNumber: String) -> Bool {
        // 清理电话号码，移除所有非数字字符（除了+号）
        let cleanedNumber = cleanPhoneNumber(phoneNumber)
        
        // 验证电话号码格式
        guard isValidPhoneNumber(cleanedNumber) else {
            return false
        }
        
        // 检查是否在模拟器上运行
        #if targetEnvironment(simulator)
        // 在模拟器上，tel:// URL 无法正常工作
        print("⚠️ 模拟器不支持拨打电话功能，请在真机上测试")
        return false
        #else
        // 构建电话 URL
        // 注意：tel:// URL scheme 会直接拨打电话，telprompt:// 会先显示确认对话框
        let phoneURLString = "tel://\(cleanedNumber)"
        guard let phoneURL = URL(string: phoneURLString) else {
            print("❌ 无法创建电话 URL: \(phoneURLString)")
            return false
        }
        
        // 在真机上，直接打开电话 URL（会立即拨打电话）
        // 注意：这会直接拨打电话，不会显示确认对话框
        DispatchQueue.main.async {
            if UIApplication.shared.canOpenURL(phoneURL) {
                UIApplication.shared.open(phoneURL, options: [:], completionHandler: { success in
                    if success {
                        print("✅ 成功打开电话应用，正在拨打: \(cleanedNumber)")
                    } else {
                        print("❌ 无法打开电话 URL: \(phoneURL)")
                    }
                })
            } else {
                print("❌ 设备不支持拨打电话功能")
            }
        }
        return true
        #endif
    }
    
    /// 拨打电话号码（带确认提示）
    /// - Parameter phoneNumber: 要拨打的电话号码
    /// - Returns: 是否成功发起呼叫
    /// - Note: 使用 telprompt:// 会先显示确认对话框，用户确认后才会拨打电话
    static func makePhoneCallWithPrompt(_ phoneNumber: String) -> Bool {
        // 清理电话号码
        let cleanedNumber = cleanPhoneNumber(phoneNumber)
        
        // 验证电话号码格式
        guard isValidPhoneNumber(cleanedNumber) else {
            return false
        }
        
        #if targetEnvironment(simulator)
        print("⚠️ 模拟器不支持拨打电话功能，请在真机上测试")
        return false
        #else
        // 使用 telprompt:// 会先显示确认对话框
        let phoneURLString = "telprompt://\(cleanedNumber)"
        guard let phoneURL = URL(string: phoneURLString) else {
            return false
        }
        
        DispatchQueue.main.async {
            if UIApplication.shared.canOpenURL(phoneURL) {
                UIApplication.shared.open(phoneURL, options: [:], completionHandler: nil)
            }
        }
        return true
        #endif
    }
    
    /// 清理电话号码，移除空格、连字符等字符
    /// - Parameter phoneNumber: 原始电话号码
    /// - Returns: 清理后的电话号码
    static func cleanPhoneNumber(_ phoneNumber: String) -> String {
        // 保留数字和+号
        return phoneNumber.filter { $0.isNumber || $0 == "+" }
    }
    
    /// 验证电话号码格式
    /// - Parameter phoneNumber: 要验证的电话号码
    /// - Returns: 是否为有效的电话号码格式
    static func isValidPhoneNumber(_ phoneNumber: String) -> Bool {
        let cleaned = cleanPhoneNumber(phoneNumber)
        
        // 基本验证：至少包含一定数量的数字
        // 国际号码可能以+开头，本地号码通常是7-15位数字
        let digitsOnly = cleaned.filter { $0.isNumber }
        
        // 电话号码通常至少7位，最多15位（国际标准）
        return digitsOnly.count >= 7 && digitsOnly.count <= 15
    }
    
    /// 格式化电话号码显示
    /// - Parameter phoneNumber: 原始电话号码
    /// - Returns: 格式化后的电话号码字符串
    static func formatPhoneNumber(_ phoneNumber: String) -> String {
        let cleaned = cleanPhoneNumber(phoneNumber)
        let digitsOnly = cleaned.filter { $0.isNumber }
        
        // 简单的格式化：如果是11位数字，假设是中国手机号，格式化为 xxx-xxxx-xxxx
        if digitsOnly.count == 11 {
            let index1 = digitsOnly.index(digitsOnly.startIndex, offsetBy: 3)
            let index2 = digitsOnly.index(digitsOnly.startIndex, offsetBy: 7)
            return "\(digitsOnly[..<index1])-\(digitsOnly[index1..<index2])-\(digitsOnly[index2...])"
        }
        
        // 其他情况返回清理后的号码
        return cleaned
    }
}

