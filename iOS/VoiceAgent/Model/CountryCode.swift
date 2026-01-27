//
//  CountryCode.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation

/// 国家/地区区号数据模型
struct CountryCode: Identifiable, Codable {
    let id: String
    let name: String
    let code: String
    let flag: String
    
    init(id: String, name: String, code: String, flag: String) {
        self.id = id
        self.name = name
        self.code = code
        self.flag = flag
    }
    
    /// 显示格式：🇨🇳 +86
    var displayText: String {
        return "\(flag) \(code)"
    }
    
}

/// 常用国家/地区区号列表
class CountryCodeManager {
    static let shared = CountryCodeManager()
    
    let countryCodes: [CountryCode] = [
        // 常用国家/地区
        CountryCode(id: "CN", name: "中国", code: "+86", flag: "🇨🇳"),
        CountryCode(id: "US", name: "美国", code: "+1", flag: "🇺🇸"),
        CountryCode(id: "HK", name: "香港", code: "+852", flag: "🇭🇰"),
        CountryCode(id: "TW", name: "台湾", code: "+886", flag: "🇹🇼"),
        CountryCode(id: "MO", name: "澳门", code: "+853", flag: "🇲🇴"),
        CountryCode(id: "JP", name: "日本", code: "+81", flag: "🇯🇵"),
        CountryCode(id: "KR", name: "韩国", code: "+82", flag: "🇰🇷"),
        CountryCode(id: "SG", name: "新加坡", code: "+65", flag: "🇸🇬"),
        CountryCode(id: "MY", name: "马来西亚", code: "+60", flag: "🇲🇾"),
        CountryCode(id: "TH", name: "泰国", code: "+66", flag: "🇹🇭"),
        CountryCode(id: "GB", name: "英国", code: "+44", flag: "🇬🇧"),
        CountryCode(id: "AU", name: "澳大利亚", code: "+61", flag: "🇦🇺"),
        CountryCode(id: "CA", name: "加拿大", code: "+1", flag: "🇨🇦"),
        CountryCode(id: "DE", name: "德国", code: "+49", flag: "🇩🇪"),
        CountryCode(id: "FR", name: "法国", code: "+33", flag: "🇫🇷"),
        CountryCode(id: "IT", name: "意大利", code: "+39", flag: "🇮🇹"),
        CountryCode(id: "ES", name: "西班牙", code: "+34", flag: "🇪🇸"),
        CountryCode(id: "RU", name: "俄罗斯", code: "+7", flag: "🇷🇺"),
        CountryCode(id: "IN", name: "印度", code: "+91", flag: "🇮🇳"),
        CountryCode(id: "BR", name: "巴西", code: "+55", flag: "🇧🇷"),
    ]
    
    /// 默认区号（中国）
    var defaultCountryCode: CountryCode {
        return countryCodes.first { $0.id == "CN" } ?? countryCodes[0]
    }
    
}

