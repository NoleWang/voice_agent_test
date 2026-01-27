//
//  PhoneNumberPickerView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI
import Contacts

// MARK: - Phone Number Picker View (for selecting multiple phone numbers from a contact)
struct PhoneNumberPickerView: View {
    let contact: CNContact
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // 联系人信息
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Text(contactInitials)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.blue)
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(contactFullName)
                                .font(.headline)
                            Text("\(contact.phoneNumbers.count) phone numbers")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // 电话号码列表
                Section("Select Phone Number") {
                    ForEach(Array(contact.phoneNumbers.enumerated()), id: \.offset) { index, phoneNumber in
                        Button(action: {
                            onSelect(phoneNumber.value.stringValue)
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(phoneLabel(phoneNumber.label))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Text(PhoneCallService.formatPhoneNumber(phoneNumber.value.stringValue))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "phone.fill")
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle("Select Number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // 联系人全名
    private var contactFullName: String {
        let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        if !fullName.isEmpty {
            return fullName
        }
        return contact.organizationName.isEmpty ? "Unknown Contact" : contact.organizationName
    }
    
    // 联系人首字母
    private var contactInitials: String {
        let fullName = contactFullName
        if fullName.count >= 2 {
            return String(fullName.prefix(2)).uppercased()
        } else if fullName.count == 1 {
            return String(fullName.prefix(1)).uppercased()
        }
        return "?"
    }
    
    // 电话号码标签
    private func phoneLabel(_ label: String?) -> String {
        guard let label = label else {
            return "Phone"
        }
        
        // 使用已知的常量进行比较
        if label == CNLabelPhoneNumberMobile {
            return "Mobile"
        } else if label == CNLabelPhoneNumberiPhone {
            return "iPhone"
        } else if label == CNLabelPhoneNumberMain {
            return "Main"
        } else if label == CNLabelPhoneNumberPager {
            return "Pager"
        }
        
        // 对于可能不可用的常量，使用字符串匹配
        // CNLabelPhoneNumberHome 和 CNLabelPhoneNumberWork 在某些版本可能不可用
        let homeLabels = ["_$!<Home>!$_", "Home"]
        let workLabels = ["_$!<Work>!$_", "Work"]
        let homeFaxLabels = ["_$!<HomeFAX>!$_", "HomeFAX", "HomeFax"]
        let workFaxLabels = ["_$!<WorkFAX>!$_", "WorkFAX", "WorkFax"]
        let otherFaxLabels = ["_$!<OtherFAX>!$_", "OtherFAX", "OtherFax"]
        
        if homeLabels.contains(where: { label.contains($0) || label == $0 }) {
            return "Home"
        } else if workLabels.contains(where: { label.contains($0) || label == $0 }) {
            return "Work"
        } else if homeFaxLabels.contains(where: { label.contains($0) || label == $0 }) {
            return "Home Fax"
        } else if workFaxLabels.contains(where: { label.contains($0) || label == $0 }) {
            return "Work Fax"
        } else if otherFaxLabels.contains(where: { label.contains($0) || label == $0 }) {
            return "Other Fax"
        } else {
            // 处理自定义标签
            var cleanedLabel = label
            cleanedLabel = cleanedLabel.replacingOccurrences(of: "_$!<", with: "")
            cleanedLabel = cleanedLabel.replacingOccurrences(of: ">!$_", with: "")
            return cleanedLabel.isEmpty ? "电话" : cleanedLabel
        }
    }
}

#Preview {
    let contact = CNMutableContact()
    contact.givenName = "Test"
    contact.familyName = "Contact"
    let phone1 = CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+8613800138000"))
    let phone2 = CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+8613800138001"))
    contact.phoneNumbers = [phone1, phone2]
    
    return PhoneNumberPickerView(contact: contact as CNContact, onSelect: { _ in })
}

