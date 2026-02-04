//
//  TaskManagementView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI

/// View for managing all tasks (view, edit, delete)
struct TaskManagementView: View {
    @State private var tasks: [TaskItem] = []
    @State private var selectedTask: TaskItem?
    @State private var showDeleteAlert = false
    @State private var taskToDelete: TaskItem?
    
    var body: some View {
        NavigationStack {
            Group {
                if tasks.isEmpty {
                    emptyStateView
                } else {
                    taskListView
                }
            }
            .navigationTitle("My Tasks")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadTasks()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TaskListNeedsUpdate"))) { _ in
                loadTasks()
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task) {
                    loadTasks()
                }
            }
            .alert("Delete Task", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let task = taskToDelete {
                        deleteTask(task)
                    }
                }
            } message: {
                if let task = taskToDelete {
                    Text("Are you sure you want to delete this task?\n\n\(task.serviceItemTitle) - \(task.merchant)")
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("No Tasks")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("You haven't created any tasks yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var taskListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Group tasks by category
                let groupedTasks = Dictionary(grouping: tasks) { $0.categoryName }
                let sortedCategories = groupedTasks.keys.sorted()
                
                ForEach(sortedCategories, id: \.self) { categoryName in
                    categorySection(categoryName: categoryName, tasks: groupedTasks[categoryName] ?? [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private func categorySection(categoryName: String, tasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header
            HStack {
                Text(categoryName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(tasks.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Tasks in this category
            ForEach(tasks) { task in
                taskRow(task: task)
            }
        }
        .padding(.bottom, 8)
    }
    
    private func taskRow(task: TaskItem) -> some View {
        Button(action: {
            selectedTask = task
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Service item title (small category)
                    Text(task.serviceItemTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Spacer()
                    
                    // Delete button
                    Button(action: {
                        taskToDelete = task
                        showDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Merchant and amount
                HStack {
                    Text(task.merchant)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(formatCurrency(task.amount, currency: task.currency))
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                // Date
                Text(formatDate(task.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func loadTasks() {
        tasks = DisputeCaseService.loadAllTasks()
    }
    
    private func deleteTask(_ task: TaskItem) {
        do {
            try DisputeCaseService.deleteTask(fileURL: task.fileURL)
            loadTasks()
            NotificationCenter.default.post(name: NSNotification.Name("TaskListNeedsUpdate"), object: nil)
        } catch {
            print("❌ Error deleting task: \(error.localizedDescription)")
        }
    }
    
    private func formatCurrency(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.2f", amount))"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// View for displaying and editing task details
struct TaskDetailView: View {
    let task: TaskItem
    let onUpdate: () -> Void
    @Environment(\.dismiss) private var dismiss

    private struct LiveKitJoinInfo: Identifiable {
        let id = UUID()
        let url: String
        let token: String
        let code: String
        let bankPhoneNumber: String?
        let bootstrapPayload: LiveKitBootstrapPayload?
    }
    
    @State private var disputeCase: DisputeCase?
    @State private var summary: String = ""
    @State private var amount: String = ""
    @State private var currency: String = "USD"
    @State private var merchant: String = ""
    @State private var txnDate: Date = Date()
    @State private var reason: String = ""
    @State private var cardNumber: String = ""  // Store full card number
    @State private var originalCardNumber: String = ""  // Store original card number for cancel
    @State private var canEditCardNumber = false  // Control if card number can be edited
    @State private var showPasswordAlert = false  // Show password input dialog
    @State private var passwordInput = ""  // Store password input
    @State private var passwordError = ""  // Store password error message
    private var lastFourDigits: String {
        // Extract last 4 digits from full card number
        let digitsOnly = cardNumber.filter { $0.isNumber }
        return String(digitsOnly.suffix(4))
    }
    @State private var selectedBank: Bank? = nil  // Selected bank
    @State private var customBankName: String = ""  // Custom bank name for "Others"
    @State private var customBankPhone: String = ""  // Custom bank phone for "Others"
    @State private var selectedCountryCode: CountryCode = CountryCodeManager.shared.defaultCountryCode  // Country code for custom phone
    @State private var showCountryCodePicker = false  // Show country code picker
    @State private var showDeleteAlert = false
    @State private var showSaveAlert = false
    @State private var alertMessage = ""
    @State private var joinInfo: LiveKitJoinInfo? = nil
    @State private var isStartingRoom = false
    @StateObject private var liveKitManager = LiveKitManager()
    
    private let currencies = ["USD", "CNY", "EUR", "HKD", "JPY", "GBP", "AUD", "CAD"]
    private let banks = Bank.allBanks
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    profileSection
                    formSection
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadTaskData()
            }
            .alert("Delete Task", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteTask()
                }
            } message: {
                Text("Are you sure you want to delete this task? This action cannot be undone.")
            }
            .alert("Save", isPresented: $showSaveAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showPasswordAlert) {
                PasswordVerificationSheet(
                    passwordInput: $passwordInput,
                    passwordError: $passwordError,
                    isPresented: $showPasswordAlert,
                    onVerify: {
                        verifyPasswordAndEnableEditing()
                    }
                )
            }
            .sheet(isPresented: $showCountryCodePicker) {
                CountryCodePickerView(selectedCountryCode: $selectedCountryCode)
            }
            .fullScreenCover(item: $joinInfo) { info in
                NavigationView {
                        LiveKitRoomView(
                            manager: liveKitManager,
                            roomUrl: info.url,
                            token: info.token,
                            shortCode: info.code,
                            bankPhoneNumber: info.bankPhoneNumber,
                            bootstrapPayload: info.bootstrapPayload
                        )
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .frame(width: 100, height: 100)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(20)
            
            Text(task.serviceItemTitle)
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
    
    private var profileSection: some View {
        VStack(spacing: 20) {
            SectionHeader(title: "Profile Information", icon: "person.fill")
            
            if let profile = disputeCase?.profile {
                VStack(spacing: 16) {
                    // Name
                    HStack {
                        Text("Name")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .leading)
                        Text("\(profile.first_name) \(profile.last_name)")
                            .font(.body)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    Divider()
                    
                    // Email
                    HStack {
                        Text("Email")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .leading)
                        Text(profile.email)
                            .font(.body)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    Divider()
                    
                    // Phone
                    HStack {
                        Text("Phone")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .leading)
                        Text(profile.phone)
                            .font(.body)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    Divider()
                    
                    // Address
                    HStack(alignment: .top) {
                        Text("Address")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .leading)
                        Text(profile.address)
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
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
            } else {
                Text("Loading profile information...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
            }
        }
    }
    
    private var formSection: some View {
        VStack(spacing: 20) {
            SectionHeader(title: "Task Information", icon: "list.bullet.clipboard")
            
            // Summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Summary")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("Enter a brief summary", text: $summary)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                    )
            }
            
            // Amount & Currency
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                        )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Currency")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Menu {
                        ForEach(currencies, id: \.self) { code in
                            Button(action: {
                                currency = code
                            }) {
                                HStack {
                                    Text(code)
                                    if currency == code {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(currency)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                        )
                    }
                }
            }
            
            // Merchant
            VStack(alignment: .leading, spacing: 8) {
                Text("Merchant")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("Enter merchant name", text: $merchant)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                    )
            }
            
            // Transaction date
            VStack(alignment: .leading, spacing: 8) {
                Text("Transaction Date")
                    .font(.subheadline)
                    .fontWeight(.medium)
                DatePicker("", selection: $txnDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                    )
            }
            
            // Reason
            VStack(alignment: .leading, spacing: 8) {
                Text("Reason")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("Describe the issue", text: $reason, axis: .vertical)
                    .lineLimit(2, reservesSpace: true)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                    )
            }
            
            // Bank selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Bank Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Menu {
                    ForEach(banks) { bank in
                        Button(action: {
                            selectedBank = bank
                            // Clear custom inputs when selecting a predefined bank
                            if !bank.isOthers {
                                customBankName = ""
                                customBankPhone = ""
                            }
                        }) {
                            HStack {
                                Text(bank.name)
                                if selectedBank?.id == bank.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        if let bank = selectedBank, bank.isOthers {
                            Text("Others")
                                .foregroundColor(.primary)
                        } else {
                            Text(selectedBank?.name ?? "Select a bank")
                                .foregroundColor(selectedBank == nil ? .secondary : .primary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                    )
                }
                
                // Show custom input fields if "Others" is selected
                if let bank = selectedBank, bank.isOthers {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bank Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter bank name", text: $customBankName)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                            )
                        
                        Text("Phone Number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            // Country code selector
                            Button(action: {
                                showCountryCodePicker = true
                            }) {
                                HStack(spacing: 4) {
                                    Text(selectedCountryCode.flag)
                                        .font(.system(size: 16))
                                    Text(selectedCountryCode.code)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                            }
                            
                            // Phone number input
                            TextField("Enter phone number", text: $customBankPhone)
                                .keyboardType(.phonePad)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                                )
                        }
                    }
                    .padding(.top, 8)
                } else if let bank = selectedBank, !bank.isOthers {
                    // Display bank phone number if selected (and not Others)
                    HStack {
                        Image(systemName: "phone.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Phone: \(bank.phoneNumber)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            
            // Credit card number (display masked, store full)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Credit Card Number")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    if !canEditCardNumber {
                        Button(action: {
                            showPasswordAlert = true
                            passwordInput = ""
                            passwordError = ""
                        }) {
                            Text("Edit")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    } else {
                        Button(action: {
                            // Restore original card number and disable editing
                            cardNumber = originalCardNumber
                            canEditCardNumber = false
                        }) {
                            Text("Cancel")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                
                // Display masked or full card number based on edit mode
                if canEditCardNumber {
                    // Show full card number when editing
                    TextField("Enter card number", text: $cardNumber)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                        )
                        .onChange(of: cardNumber) { newValue in
                            // Only allow digits and limit to 19 digits (max card length)
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered.count <= 19 {
                                if cardNumber != filtered {
                                    cardNumber = filtered
                                }
                            } else {
                                cardNumber = String(filtered.prefix(19))
                            }
                        }
                } else {
                    // Show masked card number when not editing
                    Text(maskedCardNumber.isEmpty ? "No card number" : maskedCardNumber)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray5))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                        )
                }
                
                // Show message if card number is locked
                if !canEditCardNumber {
                    HStack {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Enter app password to edit card number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
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
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Save button
            Button(action: saveTask) {
                HStack {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 18))
                    Text("Save Changes")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isFormValid ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!isFormValid)
            
            // Delete button
            Button(action: {
                showDeleteAlert = true
            }) {
                HStack {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18))
                    Text("Delete Task")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            Button(action: createChatroom) {
                HStack {
                    if isStartingRoom {
                        ProgressView()
                    } else {
                        Image(systemName: "message.fill")
                            .font(.system(size: 18))
                    }
                    Text(isStartingRoom ? "Starting…" : "Create Chatroom")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background((isFormValid && !isStartingRoom) ? Color.green : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!isFormValid || isStartingRoom)
        }
    }
    
    private var maskedCardNumber: String {
        let digitsOnly = cardNumber.filter { $0.isNumber }
        if digitsOnly.count >= 4 {
            let lastFour = String(digitsOnly.suffix(4))
            let masked = String(repeating: "•", count: max(0, digitsOnly.count - 4))
            return masked + lastFour
        }
        return String(repeating: "•", count: digitsOnly.count)
    }
    
    private var isFormValid: Bool {
        !summary.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidAmount(amount) &&
        !merchant.trimmingCharacters(in: .whitespaces).isEmpty &&
        !reason.trimmingCharacters(in: .whitespaces).isEmpty &&
        isValidCardNumber(cardNumber)
    }
    
    private func isValidAmount(_ value: String) -> Bool {
        guard let number = Double(value), number >= 0 else { return false }
        return true
    }
    
    private func isValidCardNumber(_ value: String) -> Bool {
        let digitsOnly = value.filter { $0.isNumber }
        // Accept at least 4 digits (last 4) or full card number (13-19 digits)
        return digitsOnly.count >= 4 && digitsOnly.count <= 19
    }
    
    private func loadTaskData() {
        do {
            let data = try Data(contentsOf: task.fileURL)
            let decoder = JSONDecoder()
            disputeCase = try decoder.decode(DisputeCase.self, from: data)
            
            print("📥 Loaded task data from: \(task.fileURL.lastPathComponent)")
            
            if let dispute = disputeCase {
                print("   Merchant: \(dispute.dispute.merchant)")
                print("   Amount: \(dispute.dispute.amount)")
                print("   Currency: \(dispute.dispute.currency)")
                summary = dispute.dispute.summary
                amount = String(format: "%.2f", dispute.dispute.amount)
                currency = dispute.dispute.currency
                merchant = dispute.dispute.merchant
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                if let date = dateFormatter.date(from: dispute.dispute.txn_date) {
                    txnDate = date
                }
                
                reason = dispute.dispute.reason
                // Load full card number if available, otherwise use last4
                if let fullCardNumber = dispute.dispute.fullCardNumber, !fullCardNumber.isEmpty {
                    cardNumber = fullCardNumber
                    originalCardNumber = fullCardNumber
                } else {
                    // Fallback to last4 for backward compatibility
                    cardNumber = dispute.dispute.last4
                    originalCardNumber = dispute.dispute.last4
                }
                
                // Load bank information if available
                if let bankName = dispute.dispute.bankName, let bankPhone = dispute.dispute.bankPhoneNumber {
                    // Find matching bank from the list
                    if let matchingBank = banks.first(where: { $0.name == bankName && $0.phoneNumber == bankPhone && !$0.isOthers }) {
                        selectedBank = matchingBank
                    } else {
                        // If not found in list, it's a custom bank (Others)
                        selectedBank = banks.first { $0.isOthers }
                        customBankName = bankName
                        
                        // Parse country code and phone number
                        let countryCodeManager = CountryCodeManager.shared
                        var phoneNumber = bankPhone
                        var foundCountryCode = countryCodeManager.defaultCountryCode
                        
                        // Try to find matching country code at the beginning
                        for countryCode in countryCodeManager.countryCodes {
                            if bankPhone.hasPrefix(countryCode.code) {
                                foundCountryCode = countryCode
                                phoneNumber = String(bankPhone.dropFirst(countryCode.code.count))
                                break
                            }
                        }
                        
                        selectedCountryCode = foundCountryCode
                        customBankPhone = phoneNumber
                    }
                }
            }
        } catch {
            print("❌ Error loading task data: \(error.localizedDescription)")
        }
    }
    
    private func verifyPasswordAndEnableEditing() {
        do {
            let isValid = try KeychainService.verifyPassword(passwordInput)
            if isValid {
                // Save current card number as original before enabling editing
                originalCardNumber = cardNumber
                canEditCardNumber = true
                showPasswordAlert = false
                passwordInput = ""
                passwordError = ""
            } else {
                passwordError = "Incorrect password. Please try again."
                passwordInput = ""
            }
        } catch {
            passwordError = "Failed to verify password: \(error.localizedDescription)"
            passwordInput = ""
        }
    }
    
    private func saveTask() {
        guard isFormValid else {
            alertMessage = "Please complete all fields correctly."
            showSaveAlert = true
            return
        }
        
        guard let disputeCase = disputeCase,
              let amountValue = Double(amount) else {
            alertMessage = "Invalid amount."
            showSaveAlert = true
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: txnDate)
        
        let digitsOnly = cardNumber.filter { $0.isNumber }
        let fullCardNumber = digitsOnly.isEmpty ? nil : digitsOnly  // Save full card number
        
        // Get bank name and phone number from selected bank or custom input
        let bankName: String?
        let bankPhoneNumber: String?
        if let bank = selectedBank, bank.isOthers {
            // Use custom inputs for "Others"
            bankName = customBankName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : customBankName.trimmingCharacters(in: .whitespaces)
            // Combine country code with phone number
            let phoneNumber = customBankPhone.trimmingCharacters(in: .whitespaces)
            if phoneNumber.isEmpty {
                bankPhoneNumber = nil
            } else {
                bankPhoneNumber = "\(selectedCountryCode.code)\(phoneNumber)"
            }
        } else {
            // Use predefined bank info
            bankName = selectedBank?.name
            bankPhoneNumber = selectedBank?.phoneNumber
        }
        
        let updatedDispute = DisputeCase.Dispute(
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amountValue,
            currency: currency,
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            txn_date: dateString,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            last4: lastFourDigits,
            fullCardNumber: fullCardNumber,
            bankName: bankName,
            bankPhoneNumber: bankPhoneNumber
        )
        
        let updatedCase = DisputeCase(
            profile: disputeCase.profile,
            dispute: updatedDispute
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(updatedCase)
            try data.write(to: task.fileURL, options: .atomic)
            
            alertMessage = "Task updated successfully!"
            showSaveAlert = true
            onUpdate()
            NotificationCenter.default.post(name: NSNotification.Name("TaskListNeedsUpdate"), object: nil)
        } catch {
            alertMessage = "Failed to save task: \(error.localizedDescription)"
            showSaveAlert = true
        }
    }

    private func createChatroom() {
        guard isFormValid else {
            alertMessage = "Please complete all fields correctly."
            showSaveAlert = true
            return
        }

        guard let profile = disputeCase?.profile else {
            alertMessage = "Profile not found. Please load the task again."
            showSaveAlert = true
            return
        }

        let bankPhoneNumber = currentBankPhoneNumber()
        let disputePayload = makeDisputePayload()
        startLiveKitRoom(
            profile: profile,
            bankPhoneNumber: bankPhoneNumber,
            disputePayload: disputePayload
        )
    }

    private func currentBankPhoneNumber() -> String? {
        if let bank = selectedBank, bank.isOthers {
            let phoneNumber = customBankPhone.trimmingCharacters(in: .whitespaces)
            guard !phoneNumber.isEmpty else { return nil }
            return "\(selectedCountryCode.code)\(phoneNumber)"
        }

        return selectedBank?.phoneNumber
    }

    private func startLiveKitRoom(
        profile: DisputeCase.Profile,
        bankPhoneNumber: String?,
        disputePayload: DisputeCase.Dispute?
    ) {
        guard !isStartingRoom else { return }
        isStartingRoom = true

        Task {
            defer { Task { @MainActor in isStartingRoom = false } }

            do {
                let identity = "customer_\(profile.first_name.lowercased())_\(profile.last_name.lowercased())"
                let name = "\(profile.first_name) \(profile.last_name)"

                let resp = try await LiveKitTokenAPI.fetchSession(
                    identity: identity,
                    name: name
                )

                let candidate = resp.url.trimmingCharacters(in: .whitespacesAndNewlines)
                let rawUrl: String = {
                    if candidate.isEmpty || candidate == "wss://" || candidate == "ws://" {
                        return AppConfig.liveKitURL
                    }
                    return candidate
                }()

                let cleaned = LiveKitManager.normalizeLiveKitURL(rawUrl)

                guard let u = URL(string: cleaned), u.host != nil else {
                    throw NSError(
                        domain: "LiveKit",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid LiveKit URL after normalize: \(cleaned)"]
                    )
                }

                await MainActor.run {
                    let bootstrapPayload = LiveKitBootstrapPayload(
                        profile: .init(
                            firstName: profile.first_name,
                            lastName: profile.last_name,
                            email: profile.email,
                            address: profile.address,
                            phone: profile.phone
                        ),
                        dispute: disputePayload.map { .init(dispute: $0) }
                    )
                    
                    // Log the payload for debugging
                    if let dispute = disputePayload {
                        print("📤 Creating chatroom with payload:")
                        print("   Merchant: \(dispute.merchant)")
                        print("   Amount: \(dispute.amount)")
                        print("   Currency: \(dispute.currency)")
                        print("   Summary: \(dispute.summary)")
                        print("   Reason: \(dispute.reason)")
                        print("   Last4: \(dispute.last4)")
                    } else {
                        print("⚠️ No dispute payload in bootstrap")
                    }
                    
                    self.joinInfo = LiveKitJoinInfo(
                        url: cleaned,
                        token: resp.token,
                        code: resp.code,
                        bankPhoneNumber: bankPhoneNumber,
                        bootstrapPayload: bootstrapPayload
                    )
                }

            } catch {
                await MainActor.run {
                    self.alertMessage = "Failed to get token: \(error.localizedDescription)"
                    self.showSaveAlert = true
                }
            }
        }
    }

    private func makeDisputePayload() -> DisputeCase.Dispute? {
        guard let amountValue = Double(amount) else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: txnDate)

        let digitsOnly = cardNumber.filter { $0.isNumber }
        let fullCardNumber = digitsOnly.isEmpty ? nil : digitsOnly
        let bankInfo = currentBankInfo()

        return DisputeCase.Dispute(
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amountValue,
            currency: currency,
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            txn_date: dateString,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            last4: lastFourDigits,
            fullCardNumber: fullCardNumber,
            bankName: bankInfo.name,
            bankPhoneNumber: bankInfo.phoneNumber
        )
    }

    private func currentBankInfo() -> (name: String?, phoneNumber: String?) {
        if let bank = selectedBank, bank.isOthers {
            let bankName = customBankName.trimmingCharacters(in: .whitespaces)
            let phoneNumber = customBankPhone.trimmingCharacters(in: .whitespaces)

            if bankName.isEmpty && phoneNumber.isEmpty {
                return (name: nil, phoneNumber: nil)
            }

            let formattedPhone: String?
            if phoneNumber.isEmpty {
                formattedPhone = nil
            } else {
                formattedPhone = "\(selectedCountryCode.code)\(phoneNumber)"
            }

            return (name: bankName.isEmpty ? nil : bankName, phoneNumber: formattedPhone)
        }

        return (name: selectedBank?.name, phoneNumber: selectedBank?.phoneNumber)
    }
    
    private func deleteTask() {
        do {
            try DisputeCaseService.deleteTask(fileURL: task.fileURL)
            onUpdate()
            NotificationCenter.default.post(name: NSNotification.Name("TaskListNeedsUpdate"), object: nil)
            dismiss()
        } catch {
            alertMessage = "Failed to delete task: \(error.localizedDescription)"
            showSaveAlert = true
        }
    }
}

/// Sheet for password verification
struct PasswordVerificationSheet: View {
    @Binding var passwordInput: String
    @Binding var passwordError: String
    @Binding var isPresented: Bool
    let onVerify: () -> Void
    @FocusState private var isPasswordFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 40)
                
                // Title
                Text("Enter App Password")
                    .font(.title2)
                    .fontWeight(.bold)
                
                // Description
                Text("Please enter your app password to edit the credit card number.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                // Password input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    SecureField("Enter password", text: $passwordInput)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(passwordError.isEmpty ? Color(.separator).opacity(0.4) : Color.red.opacity(0.6), lineWidth: 0.5)
                        )
                        .focused($isPasswordFocused)
                        .onSubmit {
                            verifyPassword()
                        }
                    
                    if !passwordError.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                            Text(passwordError)
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Buttons
                VStack(spacing: 12) {
                    Button(action: verifyPassword) {
                        Text("Verify")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(passwordInput.isEmpty ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(passwordInput.isEmpty)
                    
                    Button(action: {
                        passwordInput = ""
                        passwordError = ""
                        isPresented = false
                    }) {
                        Text("Cancel")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        passwordInput = ""
                        passwordError = ""
                        isPresented = false
                    }
                }
            }
            .onAppear {
                isPasswordFocused = true
            }
        }
        .presentationDetents([.height(400)])
    }
    
    private func verifyPassword() {
        if passwordInput.isEmpty {
            passwordError = "Password cannot be empty"
            return
        }
        onVerify()
    }
}

#Preview {
    TaskManagementView()
}
