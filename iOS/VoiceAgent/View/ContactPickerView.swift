//
//  ContactPickerView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI
import Contacts

// MARK: - Contact Picker View
struct ContactPickerView: View {
    @Binding var selectedPhoneNumber: String
    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [CNContact] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showPermissionAlert = false
    
    var filteredContacts: [CNContact] {
        if searchText.isEmpty {
            return contacts
        }
        return contacts.filter { contact in
            let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            return fullName.localizedCaseInsensitiveContains(searchText) ||
                   contact.organizationName.localizedCaseInsensitiveContains(searchText) ||
                   contact.phoneNumbers.contains { phone in
                       phone.value.stringValue.localizedCaseInsensitiveContains(searchText)
                   }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索框
                SearchBar(text: $searchText, placeholder: "Search contacts")
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                
                // 联系人列表
                if isLoading {
                    ProgressView("Loading contacts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if contacts.isEmpty {
                    emptyStateView
                } else {
                    contactsListView
                }
            }
            .navigationTitle("Select Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Contacts Permission Required", isPresented: $showPermissionAlert) {
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Contacts access is required to select contacts. Please allow access in Settings.")
            }
            .onAppear {
                loadContacts()
            }
        }
    }
    
    // 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Contacts")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Please ensure contacts access permission is granted")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 联系人列表视图
    private var contactsListView: some View {
        List {
            ForEach(filteredContacts, id: \.identifier) { contact in
                ContactRow(contact: contact) { phoneNumber in
                    selectedPhoneNumber = phoneNumber
                    dismiss()
                }
            }
        }
        .listStyle(.plain)
    }
    
    // 加载联系人
    private func loadContacts() {
        let authStatus = ContactService.checkAuthorizationStatus()
        
        if authStatus == .notDetermined {
            ContactService.requestAuthorization { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        loadContactsList()
                    } else {
                        isLoading = false
                        showPermissionAlert = true
                    }
                }
            }
        } else if authStatus == .authorized {
            loadContactsList()
        } else {
            isLoading = false
            showPermissionAlert = true
        }
    }
    
    // 加载联系人列表
    private func loadContactsList() {
        DispatchQueue.global(qos: .userInitiated).async {
            let allContacts = ContactService.getAllContacts()
            DispatchQueue.main.async {
                self.contacts = allContacts
                self.isLoading = false
            }
        }
    }
}

// MARK: - Contact Row Component
struct ContactRow: View {
    let contact: CNContact
    let onSelect: (String) -> Void
    @State private var showPhoneNumberPicker = false
    
    var body: some View {
        Button(action: {
            if contact.phoneNumbers.count == 1 {
                // 只有一个电话号码，直接选择
                if let phoneNumber = contact.phoneNumbers.first?.value.stringValue {
                    onSelect(phoneNumber)
                }
            } else {
                // 多个电话号码，显示选择器
                showPhoneNumberPicker = true
            }
        }) {
            HStack(spacing: 12) {
                // 头像占位符
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(contactInitials)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.blue)
                    )
                
                // 联系人信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(contactFullName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let phoneNumber = ContactService.getPrimaryPhoneNumber(from: contact) {
                        Text(PhoneCallService.formatPhoneNumber(phoneNumber))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 如果有多个电话号码，显示数量
                if contact.phoneNumbers.count > 1 {
                    VStack(spacing: 2) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("\(contact.phoneNumbers.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showPhoneNumberPicker) {
            PhoneNumberPickerView(contact: contact, onSelect: onSelect)
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
    
    // 联系人首字母（用于头像）
    private var contactInitials: String {
        let fullName = contactFullName
        if fullName.count >= 2 {
            return String(fullName.prefix(2)).uppercased()
        } else if fullName.count == 1 {
            return String(fullName.prefix(1)).uppercased()
        }
        return "?"
    }
}

#Preview {
    ContactPickerView(selectedPhoneNumber: .constant(""))
}

