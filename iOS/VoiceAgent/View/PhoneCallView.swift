//
//  PhoneCallView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI
import Combine
import Contacts

// MARK: - Main View
struct PhoneCallView: View {
    @StateObject private var viewModel = PhoneCallViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                PhoneCallInputSection(viewModel: viewModel)
                PhoneCallHistorySection(viewModel: viewModel)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Make Phone Call")
        .navigationBarTitleDisplayMode(.large)
        .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage)
        }
        .sheet(item: $viewModel.editingRecord) { record in
            PhoneCallEditNoteView(record: record, viewModel: viewModel)
        }
        .sheet(item: $viewModel.savingContact) { contactInfo in
            SaveContactView(contactInfo: contactInfo, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showContactPicker) {
            ContactPickerView(selectedPhoneNumber: Binding(
                get: { viewModel.phoneNumber },
                set: { newValue in
                    viewModel.handleContactSelected(phoneNumber: newValue)
                }
            ))
        }
    }
}

// MARK: - Input Section Component
struct PhoneCallInputSection: View {
    @ObservedObject var viewModel: PhoneCallViewModel
    @FocusState private var isPhoneNumberFocused: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            inputSection
            buttonsSection
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "phone.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Enter Phone Number")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Phone Number", icon: "phone.fill")
            
            // 从通讯录选择按钮
            Button(action: {
                viewModel.showContactPicker = true
            }) {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 16))
                    Text("Select from Contacts")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            }
            
            // 区号和电话号码输入行
            HStack(spacing: 12) {
                // 区号选择按钮
                Button(action: {
                    viewModel.showCountryCodePicker = true
                }) {
                    HStack(spacing: 6) {
                        Text(viewModel.selectedCountryCode.flag)
                            .font(.system(size: 20))
                        Text(viewModel.selectedCountryCode.code)
                            .font(.system(size: 16, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator).opacity(0.6), lineWidth: 0.5)
                    )
                }
                .foregroundColor(.primary)
                
                // 电话号码输入框
                TextField("Enter phone number", text: $viewModel.phoneNumber)
                    .keyboardType(.phonePad)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isPhoneNumberFocused ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.6), lineWidth: isPhoneNumberFocused ? 1 : 0.5)
                    )
                    .focused($isPhoneNumberFocused)
                    .font(.system(size: 18, weight: .medium))
            }
            
            // 完整号码预览
            if !viewModel.phoneNumber.isEmpty {
                HStack {
                    Text("Full Number: ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(viewModel.fullPhoneNumber)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
            
            // 电话号码验证提示
            if !viewModel.phoneNumber.isEmpty {
                HStack {
                    if PhoneCallService.isValidPhoneNumber(viewModel.fullPhoneNumber) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Valid phone number format")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text("Please enter a valid phone number (7-15 digits)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .sheet(isPresented: $viewModel.showCountryCodePicker) {
            CountryCodePickerView(selectedCountryCode: $viewModel.selectedCountryCode)
        }
    }
    
    private var buttonsSection: some View {
        VStack(spacing: 12) {
            // 拨打电话按钮
            Button(action: {
                viewModel.handlePhoneCall()
            }) {
                HStack {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 18))
                    Text("Make Call")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(viewModel.isPhoneNumberValid ? Color.green : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(viewModel.isPhoneNumberValid ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
            .disabled(!viewModel.isPhoneNumberValid)
            
            // 保存联系人按钮
            Button(action: {
                viewModel.saveCurrentNumberToContacts()
            }) {
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 18))
                    Text("Save to Contacts")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(viewModel.isPhoneNumberValid ? Color.orange : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(viewModel.isPhoneNumberValid ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
            .disabled(!viewModel.isPhoneNumberValid)
        }
        .padding(.top, 8)
    }
}

// MARK: - History Section Component
struct PhoneCallHistorySection: View {
    @ObservedObject var viewModel: PhoneCallViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "History", icon: "clock.fill")
            
            if viewModel.records.isEmpty {
                emptyStateView
            } else {
                recordsListView
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var emptyStateView: some View {
                Text("No history records")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
    }
    
    private var recordsListView: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.records) { record in
                PhoneCallRecordRow(record: record, viewModel: viewModel)
            }
        }
    }
}

// MARK: - History Record Row Component
struct PhoneCallRecordRow: View {
    let record: PhoneCallRecord
    @ObservedObject var viewModel: PhoneCallViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: "phone.fill")
                .foregroundColor(.blue)
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            
            // 信息区域
            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(record.formattedPhoneNumber)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 8) {
                // 保存联系人按钮
                Button(action: {
                    viewModel.saveToContacts(record: record)
                }) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))
                }
                
                // 编辑备注按钮
                Button(action: {
                    viewModel.editRecord(record)
                }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                }
                
                // 拨打电话按钮
                Button(action: {
                    viewModel.callRecord(record)
                }) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }
}

// MARK: - Edit Note View
struct PhoneCallEditNoteView: View {
    let record: PhoneCallRecord
    @ObservedObject var viewModel: PhoneCallViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    
    init(record: PhoneCallRecord, viewModel: PhoneCallViewModel) {
        self.record = record
        self.viewModel = viewModel
        _note = State(initialValue: record.note)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // 电话号码显示
                VStack(spacing: 8) {
                    Text("Phone Number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(record.formattedPhoneNumber)
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
                    viewModel.updateNote(recordId: record.id, note: note)
                    dismiss()
                }) {
                    Text("Save")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .padding()
            .navigationTitle("Edit Note")
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
}

// MARK: - View Model
@MainActor
class PhoneCallViewModel: ObservableObject {
    @Published var phoneNumber = ""
    @Published var selectedCountryCode: CountryCode
    @Published var showCountryCodePicker = false
    @Published var records: [PhoneCallRecord] = []
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var editingRecord: PhoneCallRecord?
    @Published var savingContact: ContactInfo?
    @Published var showContactPicker = false
    
    private let countryCodeManager = CountryCodeManager.shared
    
    init() {
        selectedCountryCode = countryCodeManager.defaultCountryCode
        loadHistory()
    }
    
    // MARK: - Computed Properties
    var isPhoneNumberValid: Bool {
        let trimmedNumber = phoneNumber.trimmingCharacters(in: .whitespaces)
        return !trimmedNumber.isEmpty &&
        PhoneCallService.isValidPhoneNumber(trimmedNumber)
    }
    
    /// Full phone number (including country code)
    var fullPhoneNumber: String {
        let trimmedNumber = phoneNumber.trimmingCharacters(in: .whitespaces)
        if trimmedNumber.isEmpty {
            return ""
        }
        if trimmedNumber.hasPrefix("+") {
            return trimmedNumber
        }
        return "\(selectedCountryCode.code)\(trimmedNumber)"
    }
    
    // MARK: - Methods
    
    /// Load history records
    func loadHistory() {
        records = PhoneCallHistoryService.loadAllRecords()
    }
    
    /// Handle phone call
    func handlePhoneCall() {
        let trimmedNumber = phoneNumber.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedNumber.isEmpty else {
            showAlert(title: "Error", message: "Please enter a phone number")
            return
        }
        
        let fullNumber = fullPhoneNumber
        
        guard PhoneCallService.isValidPhoneNumber(fullNumber) else {
            showAlert(title: "Error", message: "Invalid phone number format. Please enter 7-15 digits")
            return
        }
        
        let success = PhoneCallService.makePhoneCall(fullNumber)
        
        if success {
            let record = PhoneCallRecord(phoneNumber: fullNumber)
            PhoneCallHistoryService.saveRecord(record)
            loadHistory()
            
            showAlert(title: "Success", message: "Calling: \(PhoneCallService.formatPhoneNumber(fullNumber))")
            phoneNumber = ""
        } else {
            showAlert(title: "Error", message: "Unable to make phone call. Please check if your device supports phone functionality")
        }
    }
    
    /// Call phone number from history record
    func callRecord(_ record: PhoneCallRecord) {
        let success = PhoneCallService.makePhoneCall(record.phoneNumber)
        
        if success {
            let updatedRecord = PhoneCallRecord(
                phoneNumber: record.phoneNumber,
                note: record.note,
                id: record.id,
                createdAt: record.createdAt,
                lastCalledAt: Date()
            )
            PhoneCallHistoryService.saveRecord(updatedRecord)
            loadHistory()
            
            showAlert(title: "Success", message: "Calling: \(record.formattedPhoneNumber)")
        } else {
            showAlert(title: "Error", message: "Unable to make phone call. Please check if your device supports phone functionality")
        }
    }
    
    /// Edit record
    func editRecord(_ record: PhoneCallRecord) {
        editingRecord = record
    }
    
    /// Update note
    func updateNote(recordId: UUID, note: String) {
        PhoneCallHistoryService.updateNote(recordId: recordId, note: note)
        loadHistory()
    }
    
    /// Delete record
    func deleteRecord(_ record: PhoneCallRecord) {
        PhoneCallHistoryService.deleteRecord(recordId: record.id)
        loadHistory()
    }
    
    /// Save current phone number to contacts
    func saveCurrentNumberToContacts() {
        let trimmedNumber = phoneNumber.trimmingCharacters(in: .whitespaces)
        guard !trimmedNumber.isEmpty else {
            showAlert(title: "Error", message: "Please enter a phone number")
            return
        }
        
        let fullNumber = fullPhoneNumber
        guard PhoneCallService.isValidPhoneNumber(fullNumber) else {
            showAlert(title: "Error", message: "Invalid phone number format")
            return
        }
        
        let authStatus = ContactService.checkAuthorizationStatus()
        if authStatus == .notDetermined {
            ContactService.requestAuthorization { [weak self] granted, error in
                if granted {
                    self?.checkAndShowContactInfo(phoneNumber: fullNumber)
                } else {
                    self?.showAlert(
                        title: "Permission Denied",
                        message: "Contacts permission is required to save contacts.\n\nPlease allow access in Settings > Privacy & Security > Contacts."
                    )
                }
            }
        } else if authStatus == .authorized {
            checkAndShowContactInfo(phoneNumber: fullNumber)
        } else {
            showAlert(
                title: "Permission Denied",
                message: "Contacts access permission was denied.\n\nPlease allow access in Settings > Privacy & Security > Contacts."
            )
        }
    }
    
    /// Check and show contact information
    private func checkAndShowContactInfo(phoneNumber: String) {
        if let existingContact = ContactService.findContact(by: phoneNumber) {
            let contactInfo = ContactInfo(
                phoneNumber: phoneNumber,
                name: "\(existingContact.givenName) \(existingContact.familyName)".trimmingCharacters(in: .whitespaces),
                note: existingContact.note,
                existingContact: existingContact
            )
            savingContact = contactInfo
        } else {
            let contactInfo = ContactInfo(
                phoneNumber: phoneNumber,
                name: "",
                note: ""
            )
            savingContact = contactInfo
        }
    }
    
    /// Save phone number from history to contacts
    func saveToContacts(record: PhoneCallRecord) {
        // 先检查权限
        let authStatus = ContactService.checkAuthorizationStatus()
        if authStatus == .notDetermined {
            // 先请求权限
            ContactService.requestAuthorization { [weak self] granted, error in
                if granted {
                    self?.checkAndShowContactInfoForRecord(record: record)
                } else {
                    self?.showAlert(
                        title: "Permission Denied",
                        message: "Contacts permission is required to save contacts.\n\nPlease allow access in Settings > Privacy & Security > Contacts."
                    )
                }
            }
        } else if authStatus == .authorized {
            checkAndShowContactInfoForRecord(record: record)
        } else {
            showAlert(
                title: "Permission Denied",
                message: "Contacts access permission was denied.\n\nPlease allow access in Settings > Privacy & Security > Contacts."
            )
        }
    }
    
    /// Check and show contact information for history record
    private func checkAndShowContactInfoForRecord(record: PhoneCallRecord) {
        if let existingContact = ContactService.findContact(by: record.phoneNumber) {
            let contactInfo = ContactInfo(
                phoneNumber: record.phoneNumber,
                name: "\(existingContact.givenName) \(existingContact.familyName)".trimmingCharacters(in: .whitespaces),
                note: existingContact.note,
                existingContact: existingContact
            )
            savingContact = contactInfo
        } else {
            let contactInfo = ContactInfo(
                phoneNumber: record.phoneNumber,
                name: record.note.isEmpty ? "" : record.note,
                note: record.note
            )
            savingContact = contactInfo
        }
    }
    
    /// Save contact to address book
    func saveContact(name: String, phoneNumber: String, note: String, existingContact: CNContact?) {
        // 检查权限
        let authStatus = ContactService.checkAuthorizationStatus()
        
        if authStatus == .notDetermined {
            DispatchQueue.main.async { [weak self] in
                ContactService.requestAuthorization { granted, error in
                    DispatchQueue.main.async {
                        
                        if let error = error {
                            self?.showAlert(title: "Error", message: "Error requesting permission: \(error.localizedDescription)")
                            return
                        }
                        
                        if granted {
                            self?.performSaveContact(name: name, phoneNumber: phoneNumber, note: note, existingContact: existingContact)
                        } else {
                            self?.showAlert(
                                title: "Permission Denied",
                                message: "Contacts permission is required to save contacts.\n\nPlease allow access in Settings > Privacy & Security > Contacts."
                            )
                        }
                    }
                }
            }
        } else if authStatus == .authorized {
            performSaveContact(name: name, phoneNumber: phoneNumber, note: note, existingContact: existingContact)
        } else {
            showAlert(
                title: "Permission Denied",
                message: "Contacts access permission was denied.\n\nPlease allow access in Settings > Privacy & Security > Contacts."
            )
        }
    }
    
    /// Perform save contact
    private func performSaveContact(name: String, phoneNumber: String, note: String, existingContact: CNContact?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            do {
                if let existing = existingContact {
                    try ContactService.updateContact(existing, phoneNumber: phoneNumber, name: name, note: note)
                    self.showAlert(title: "Success", message: "Contact updated")
                } else {
                    let success = try ContactService.saveContact(phoneNumber: phoneNumber, name: name, note: note)
                    if success {
                        self.showAlert(title: "Success", message: "Contact saved to address book")
                    } else {
                        self.showAlert(title: "Error", message: "Failed to save contact")
                    }
                }
                self.savingContact = nil
            } catch {
                if let contactError = error as? ContactError {
                    self.showAlert(title: "Error", message: contactError.localizedDescription)
                } else {
                    let errorMessage = error.localizedDescription.isEmpty ? "Unknown error" : error.localizedDescription
                    self.showAlert(title: "Error", message: "Failed to save contact: \(errorMessage)")
                }
            }
        }
    }
    
    /// Handle phone number selected from contacts
    func handleContactSelected(phoneNumber: String) {
        let cleanedNumber = PhoneCallService.cleanPhoneNumber(phoneNumber)
        
        if cleanedNumber.hasPrefix("+") {
            let digitsOnly = cleanedNumber.filter { $0.isNumber }
            let countryCodeManager = CountryCodeManager.shared
            
            let sortedCodes = countryCodeManager.countryCodes.sorted { code1, code2 in
                let digits1 = code1.code.filter { $0.isNumber }
                let digits2 = code2.code.filter { $0.isNumber }
                return digits1.count > digits2.count
            }
            
            for countryCode in sortedCodes {
                let codeDigits = countryCode.code.filter { $0.isNumber }
                if digitsOnly.hasPrefix(codeDigits) && digitsOnly.count > codeDigits.count {
                    selectedCountryCode = countryCode
                    let localNumber = String(digitsOnly.dropFirst(codeDigits.count))
                    self.phoneNumber = localNumber
                    return
                }
            }
            
            self.phoneNumber = digitsOnly
        } else {
            self.phoneNumber = cleanedNumber
        }
    }
    
    /// Show alert
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        self.showAlert = true
    }
}

// MARK: - Contact Info Data Model
struct ContactInfo: Identifiable {
    let id = UUID()
    var phoneNumber: String
    var name: String
    var note: String
    var existingContact: CNContact?
    
    init(phoneNumber: String, name: String = "", note: String = "", existingContact: CNContact? = nil) {
        self.phoneNumber = phoneNumber
        self.name = name
        self.note = note
        self.existingContact = existingContact
    }
}

#Preview {
    NavigationView {
        PhoneCallView()
    }
}
