//
//  ContactService.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation
import Contacts

/// 联系人服务
class ContactService {
    private static let contactStore = CNContactStore()
    
    /// 检查通讯录访问权限
    /// - Returns: 权限状态
    static func checkAuthorizationStatus() -> CNAuthorizationStatus {
        return CNContactStore.authorizationStatus(for: .contacts)
    }
    
    /// 请求通讯录访问权限
    /// - Parameter completion: 权限请求完成回调
    static func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        contactStore.requestAccess(for: .contacts) { granted, error in
            DispatchQueue.main.async {
                completion(granted, error)
            }
        }
    }
    
    /// 保存联系人到通讯录
    /// - Parameters:
    ///   - phoneNumber: 电话号码
    ///   - name: 联系人姓名
    ///   - note: 备注信息
    /// - Returns: 是否成功保存
    static func saveContact(phoneNumber: String, name: String, note: String = "") throws -> Bool {
        // 检查权限
        let authStatus = checkAuthorizationStatus()
        
        if authStatus == .notDetermined {
            // 如果权限未确定，抛出错误提示需要先请求权限
            throw ContactError.authorizationNotDetermined
        }
        
        if authStatus != .authorized {
            throw ContactError.authorizationDenied
        }
        
        // 创建联系人
        let contact = CNMutableContact()
        
        // 设置姓名
        if !name.isEmpty {
            contact.givenName = name
        } else {
            // 如果没有提供姓名，使用电话号码作为姓名
            contact.givenName = PhoneCallService.formatPhoneNumber(phoneNumber)
        }
        
        // 设置电话号码
        let phoneNumberValue = CNPhoneNumber(stringValue: phoneNumber)
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: phoneNumberValue)]
        
        // 设置备注
        if !note.isEmpty {
            contact.note = note
        }
        
        // 保存联系人
        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        
        do {
            try contactStore.execute(saveRequest)
            return true
        } catch {
            throw ContactError.saveFailed(error.localizedDescription)
        }
    }
    
    /// 检查联系人是否已存在（根据电话号码）
    /// - Parameter phoneNumber: 电话号码
    /// - Returns: 如果存在返回联系人，否则返回 nil
    static func findContact(by phoneNumber: String) -> CNContact? {
        let authStatus = checkAuthorizationStatus()
        
        // 如果权限未确定或被拒绝，返回 nil
        guard authStatus == .authorized else {
            return nil
        }
        
        let cleanedNumber = PhoneCallService.cleanPhoneNumber(phoneNumber)
        
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactNoteKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        
        var foundContact: CNContact?
        
        do {
            try contactStore.enumerateContacts(with: request) { (contact, stop) in
                for phone in contact.phoneNumbers {
                    let contactNumber = phone.value.stringValue
                    let cleanedContactNumber = PhoneCallService.cleanPhoneNumber(contactNumber)
                    
                    // 比较清理后的电话号码
                    if cleanedContactNumber == cleanedNumber || 
                       cleanedContactNumber.hasSuffix(cleanedNumber) ||
                       cleanedNumber.hasSuffix(cleanedContactNumber) {
                        foundContact = contact
                        stop.pointee = true // 停止枚举
                        return
                    }
                }
            }
        } catch {
            // 不抛出错误，只返回 nil
        }
        
        return foundContact
    }
    
    /// 获取所有联系人
    /// - Returns: 联系人数组
    static func getAllContacts() -> [CNContact] {
        let authStatus = checkAuthorizationStatus()
        guard authStatus == .authorized else {
            return []
        }
        
        let keys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey,
            CNContactOrganizationNameKey
        ] as [CNKeyDescriptor]
        
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName
        
        var contacts: [CNContact] = []
        
        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                // 只包含有电话号码的联系人
                if !contact.phoneNumbers.isEmpty {
                    contacts.append(contact)
                }
            }
        } catch {
        }
        
        return contacts
    }
    
    /// 获取联系人的主要电话号码
    /// - Parameter contact: 联系人
    /// - Returns: 主要电话号码，如果没有则返回第一个电话号码
    static func getPrimaryPhoneNumber(from contact: CNContact) -> String? {
        guard !contact.phoneNumbers.isEmpty else {
            return nil
        }
        
        // 优先选择标记为"手机"的号码
        if let mobilePhone = contact.phoneNumbers.first(where: { $0.label == CNLabelPhoneNumberMobile }) {
            return mobilePhone.value.stringValue
        }
        
        // 否则返回第一个电话号码
        return contact.phoneNumbers.first?.value.stringValue
    }
    
    /// 更新现有联系人
    /// - Parameters:
    ///   - contact: 要更新的联系人
    ///   - phoneNumber: 新的电话号码（可选）
    ///   - name: 新的姓名（可选）
    ///   - note: 新的备注（可选）
    static func updateContact(_ contact: CNContact, phoneNumber: String? = nil, name: String? = nil, note: String? = nil) throws {
        let authStatus = checkAuthorizationStatus()
        guard authStatus == .authorized else {
            throw ContactError.authorizationDenied
        }
        
        let mutableContact = contact.mutableCopy() as! CNMutableContact
        
        if let name = name, !name.isEmpty {
            mutableContact.givenName = name
        }
        
        if let phoneNumber = phoneNumber {
            let phoneNumberValue = CNPhoneNumber(stringValue: phoneNumber)
            mutableContact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: phoneNumberValue)]
        }
        
        if let note = note {
            mutableContact.note = note
        }
        
        let saveRequest = CNSaveRequest()
        saveRequest.update(mutableContact)
        
        do {
            try contactStore.execute(saveRequest)
        } catch {
            throw ContactError.saveFailed(error.localizedDescription)
        }
    }
    
}

/// 联系人错误类型
enum ContactError: LocalizedError {
    case authorizationNotDetermined
    case authorizationDenied
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .authorizationNotDetermined:
            return "需要访问通讯录权限，请先授权"
        case .authorizationDenied:
            return "通讯录访问权限被拒绝，请在设置中允许访问"
        case .saveFailed(let message):
            return "保存联系人失败：\(message)"
        }
    }
}

