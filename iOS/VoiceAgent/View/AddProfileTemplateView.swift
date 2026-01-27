//
//  AddProfileTemplateView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI
import Combine

/// View for adding a new profile template
struct AddProfileTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ProfileTemplateFormViewModel()
    @FocusState private var focusedField: Field?
    
    let onSave: (ProfileTemplate) -> Void
    
    enum Field {
        case templateName, firstName, lastName, email, address, phoneNumber
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Form
                    formSection
                    
                    // Save button
                    saveButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadExistingProfile()
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("Create Profile Template")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var formSection: some View {
        VStack(spacing: 20) {
            SectionHeader(title: "Template Information", icon: "info.circle.fill")
            
            // Template Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Template Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("e.g., Personal, Work, Family", text: $viewModel.templateName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .templateName ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.4), lineWidth: focusedField == .templateName ? 1 : 0.5)
                    )
                    .focused($focusedField, equals: .templateName)
            }
            
            // First Name
            VStack(alignment: .leading, spacing: 8) {
                Text("First Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter first name", text: $viewModel.firstName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .firstName ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.4), lineWidth: focusedField == .firstName ? 1 : 0.5)
                    )
                    .focused($focusedField, equals: .firstName)
            }
            
            // Last Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Last Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter last name", text: $viewModel.lastName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .lastName ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.4), lineWidth: focusedField == .lastName ? 1 : 0.5)
                    )
                    .focused($focusedField, equals: .lastName)
            }
            
            // Email
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter email address", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .email ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.4), lineWidth: focusedField == .email ? 1 : 0.5)
                    )
                    .focused($focusedField, equals: .email)
            }
            
            // Address
            VStack(alignment: .leading, spacing: 8) {
                Text("Address")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter address", text: $viewModel.address)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .address ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.4), lineWidth: focusedField == .address ? 1 : 0.5)
                    )
                    .focused($focusedField, equals: .address)
            }
            
            // Phone Number
            VStack(alignment: .leading, spacing: 8) {
                Text("Phone Number")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter phone number", text: $viewModel.phoneNumber)
                    .keyboardType(.phonePad)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .phoneNumber ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.4), lineWidth: focusedField == .phoneNumber ? 1 : 0.5)
                    )
                    .focused($focusedField, equals: .phoneNumber)
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
    
    private var saveButton: some View {
        Button(action: {
            if let template = viewModel.createTemplate() {
                onSave(template)
                dismiss()
            }
        }) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                Text("Save Template")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(viewModel.isFormValid ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(viewModel.isFormValid ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .disabled(!viewModel.isFormValid)
    }
    
    private func loadExistingProfile() {
        if let userInfo = try? KeychainService.loadUserInfo() {
            viewModel.firstName = userInfo.firstName
            viewModel.lastName = userInfo.lastName
            viewModel.email = userInfo.email
            viewModel.address = userInfo.address
            viewModel.phoneNumber = userInfo.phone
        }
    }
}

/// ViewModel for profile template form
@MainActor
class ProfileTemplateFormViewModel: ObservableObject {
    @Published var templateName = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var email = ""
    @Published var address = ""
    @Published var phoneNumber = ""
    
    var isFormValid: Bool {
        !templateName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidEmail(email) &&
        !address.trimmingCharacters(in: .whitespaces).isEmpty &&
        !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    func createTemplate() -> ProfileTemplate? {
        guard isFormValid else { return nil }
        
        return ProfileTemplate(
            name: templateName.trimmingCharacters(in: .whitespaces),
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespaces),
            phoneNumber: phoneNumber.trimmingCharacters(in: .whitespaces)
        )
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

/// View for editing an existing profile template
struct EditProfileTemplateView: View {
    let template: ProfileTemplate
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ProfileTemplateFormViewModel
    @FocusState private var focusedField: AddProfileTemplateView.Field?
    
    let onSave: (ProfileTemplate) -> Void
    
    init(template: ProfileTemplate, onSave: @escaping (ProfileTemplate) -> Void) {
        self.template = template
        self.onSave = onSave
        _viewModel = StateObject(wrappedValue: {
            let vm = ProfileTemplateFormViewModel()
            vm.templateName = template.name
            vm.firstName = template.firstName
            vm.lastName = template.lastName
            vm.email = template.email
            vm.address = template.address
            vm.phoneNumber = template.phoneNumber
            return vm
        }())
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Form (reuse from AddProfileTemplateView)
                    formSection
                    
                    // Save button
                    saveButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Edit Template")
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
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("Edit Profile Template")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var formSection: some View {
        VStack(spacing: 20) {
            SectionHeader(title: "Template Information", icon: "info.circle.fill")
            
            // Template Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Template Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("e.g., Personal, Work, Family", text: $viewModel.templateName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .templateName ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.4), lineWidth: focusedField == .templateName ? 1 : 0.5)
                    )
                    .focused($focusedField, equals: .templateName)
            }
            
            // First Name
            VStack(alignment: .leading, spacing: 8) {
                Text("First Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter first name", text: $viewModel.firstName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .firstName ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.4), lineWidth: focusedField == .firstName ? 1 : 0.5)
                    )
                    .focused($focusedField, equals: .firstName)
            }
            
            // Last Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Last Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter last name", text: $viewModel.lastName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .lastName ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.4), lineWidth: focusedField == .lastName ? 1 : 0.5)
                    )
                    .focused($focusedField, equals: .lastName)
            }
            
            // Email
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter email address", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .email ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.4), lineWidth: focusedField == .email ? 1 : 0.5)
                    )
                    .focused($focusedField, equals: .email)
            }
            
            // Address
            VStack(alignment: .leading, spacing: 8) {
                Text("Address")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter address", text: $viewModel.address)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .address ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.4), lineWidth: focusedField == .address ? 1 : 0.5)
                    )
                    .focused($focusedField, equals: .address)
            }
            
            // Phone Number
            VStack(alignment: .leading, spacing: 8) {
                Text("Phone Number")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter phone number", text: $viewModel.phoneNumber)
                    .keyboardType(.phonePad)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .phoneNumber ? Color.blue.opacity(0.5) : Color(.separator).opacity(0.4), lineWidth: focusedField == .phoneNumber ? 1 : 0.5)
                    )
                    .focused($focusedField, equals: .phoneNumber)
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
    
    private var saveButton: some View {
        Button(action: {
            if let updatedTemplate = viewModel.createTemplate() {
                // Preserve original ID and createdAt, update updatedAt
                let finalTemplate = ProfileTemplate(
                    id: template.id,
                    name: updatedTemplate.name,
                    firstName: updatedTemplate.firstName,
                    lastName: updatedTemplate.lastName,
                    email: updatedTemplate.email,
                    address: updatedTemplate.address,
                    phoneNumber: updatedTemplate.phoneNumber,
                    createdAt: template.createdAt,
                    updatedAt: Date()
                )
                onSave(finalTemplate)
                dismiss()
            }
        }) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                Text("Save Changes")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(viewModel.isFormValid ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(viewModel.isFormValid ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .disabled(!viewModel.isFormValid)
    }
}

#Preview {
    AddProfileTemplateView { _ in }
}

