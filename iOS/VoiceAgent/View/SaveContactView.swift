//
//  SaveContactView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI
import Contacts

// MARK: - Save Contact View
struct SaveContactView: View {
    @ObservedObject var viewModel: PhoneCallViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String
    @State private var phoneNumber: String
    
    let contactInfo: ContactInfo
    
    init(contactInfo: ContactInfo, viewModel: PhoneCallViewModel) {
        self.contactInfo = contactInfo
        self.viewModel = viewModel
        _name = State(initialValue: contactInfo.name)
        _note = State(initialValue: contactInfo.note)
        _phoneNumber = State(initialValue: contactInfo.phoneNumber)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // 标题说明
                    if contactInfo.existingContact != nil {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("This number already exists in contacts. Contact information will be updated.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                    }
                    
                    // 电话号码显示
                    VStack(spacing: 8) {
                        Text("Phone Number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(PhoneCallService.formatPhoneNumber(phoneNumber))
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                    )
                    
                    // 联系人姓名输入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contact Name")
                            .font(.headline)
                        
                        TextField("Enter contact name", text: $name)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                            )
                    }
                    
                    // 备注输入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note")
                            .font(.headline)
                        
                        TextField("Enter note (optional)", text: $note)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                            )
                    }
                    
                    Spacer()
                    
                    // 保存按钮
                    Button(action: {
                        viewModel.saveContact(
                            name: name.trimmingCharacters(in: .whitespaces),
                            phoneNumber: phoneNumber,
                            note: note.trimmingCharacters(in: .whitespaces),
                            existingContact: contactInfo.existingContact
                        )
                        dismiss()
                    }) {
                        Text(contactInfo.existingContact != nil ? "Update Contact" : "Save to Contacts")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(isFormValid ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isFormValid ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                    }
                    .disabled(!isFormValid)
                }
                .padding()
            }
            .navigationTitle(contactInfo.existingContact != nil ? "Update Contact" : "Save Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // 表单验证
    private var isFormValid: Bool {
        // 至少需要姓名或备注其中一个不为空
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        return !trimmedName.isEmpty || !trimmedNote.isEmpty
    }
}

#Preview {
    SaveContactView(
        contactInfo: ContactInfo(phoneNumber: "+8613800138000", name: "Test", note: "Test note"),
        viewModel: PhoneCallViewModel()
    )
}

