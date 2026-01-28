//
//  UserProfileFormView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI
import Foundation
import Combine

/// View for collecting user profile information
struct UserProfileFormView: View {
    let serviceItem: ServiceItem
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = UserProfileFormViewModel()
    @FocusState private var focusedField: Field?
    @State private var navigateToPhoneCall = false
    @State private var navigateToCreditCardOption = false
    @State private var showTemplatePicker = false
    
    enum Field {
        case firstName, lastName, email, address, phoneNumber
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header section
                headerSection
                
                // Form section
                formSection
                
                // Submit button
                submitButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(serviceItem.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage)
        }
        .navigationDestination(isPresented: $navigateToCreditCardOption) {
            CreditCardOptionView(serviceItem: serviceItem)
        }
        .navigationDestination(isPresented: $navigateToPhoneCall) {
            PhoneCallView()
        }
        .onChange(of: viewModel.profileSubmitted) { submitted in
            if submitted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if serviceItem.title == "Credit Card Issues" {
                        navigateToCreditCardOption = true
                    } else {
                        navigateToPhoneCall = true
                    }
                }
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            TemplatePickerView { template in
                // Load template data into form
                viewModel.loadFromTemplate(template)
                // Keep the form view open, only close the picker
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: serviceItem.icon)
                .font(.system(size: 60))
                .foregroundColor(serviceItem.iconColor)
                .frame(width: 100, height: 100)
                .background(serviceItem.iconColor.opacity(0.1))
                .cornerRadius(20)
            
            Text("Please provide your information")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
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
            SectionHeader(title: "Personal Information", icon: "person.fill")
            
            // Select from template button
            Button(action: {
                showTemplatePicker = true
            }) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 16))
                    Text("Choose from Template")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.purple.opacity(0.1))
                .foregroundColor(.purple)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
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
    
    private var submitButton: some View {
        Button(action: {
            viewModel.submitProfile()
        }) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                Text("Continue")
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

/// ViewModel for user profile form
@MainActor
class UserProfileFormViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var email = ""
    @Published var address = ""
    @Published var phoneNumber = ""
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var profileSubmitted = false
    
    var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidEmail(email) &&
        !address.trimmingCharacters(in: .whitespaces).isEmpty &&
        !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    func submitProfile() {
        guard isFormValid else {
            displayAlert(title: "Invalid Information", message: "Please fill in all required fields correctly.")
            return
        }
        
        // Save profile to user's folder (service-specific profile)
        let profile = UserProfile(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespaces),
            phoneNumber: phoneNumber.trimmingCharacters(in: .whitespaces)
        )
        
        do {
            _ = try UserProfileService.saveProfile(profile)
            profileSubmitted = true
        } catch {
            displayAlert(title: "Error", message: "Failed to save profile: \(error.localizedDescription)")
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func displayAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
    
    /// Load profile data from template
    func loadFromTemplate(_ template: ProfileTemplate) {
        // Update all form fields with template data
        // @Published properties will automatically trigger UI updates
        firstName = template.firstName
        lastName = template.lastName
        email = template.email
        address = template.address
        phoneNumber = template.phoneNumber
    }
}

#Preview {
    NavigationView {
        UserProfileFormView(serviceItem: ServiceItem(
            title: "Credit Card Issues",
            icon: "creditcard.fill",
            iconColor: .blue,
            description: "Credit card problems and inquiries"
        ))
    }
}
