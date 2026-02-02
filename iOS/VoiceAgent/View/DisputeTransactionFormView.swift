//
//  DisputeTransactionFormView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI

struct DisputeTransactionFormView: View {
    let serviceItem: ServiceItem
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form state
    @State private var summary: String = ""
    @State private var amount: String = ""
    @State private var currency: String = "USD"
    @State private var merchant: String = ""
    @State private var txnDate: Date = Date()
    @State private var reason: String = ""
    @State private var cardNumber: String = ""  // Store full card number
    @State private var selectedBank: Bank? = nil  // Selected bank
    @State private var customBankName: String = ""  // Custom bank name for "Others"
    @State private var customBankPhone: String = ""  // Custom bank phone for "Others"
    @State private var selectedCountryCode: CountryCode = CountryCodeManager.shared.defaultCountryCode  // Country code for custom phone
    @State private var showCountryCodePicker = false  // Show country code picker
    private var lastFourDigits: String {
        let digitsOnly = cardNumber.filter { $0.isNumber }
        return String(digitsOnly.suffix(4))
    }

    // MARK: - Alerts
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    // MARK: - LiveKit presentation (FIX: atomic payload)
    private struct LiveKitJoinInfo: Identifiable {
        let id = UUID()
        let url: String
        let token: String
        let bankPhoneNumber: String?  // Bank phone number for user-initiated call
        let bootstrapPayload: LiveKitBootstrapPayload?
    }

    @State private var joinInfo: LiveKitJoinInfo? = nil
    @State private var isStartingRoom = false
    @StateObject private var liveKitManager = LiveKitManager()

    // MARK: - Constants
    private let currencies = ["USD", "CNY", "EUR", "HKD", "JPY", "GBP", "AUD", "CAD"]
    private let banks = Bank.allBanks

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                formSection
                submitButton
                createChatroomButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dispute Transaction")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") { dismiss() }
            }
        }
        .alert(alertTitle.isEmpty ? "Notice" : alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showCountryCodePicker) {
            CountryCodePickerView(selectedCountryCode: $selectedCountryCode)
        }
        // ✅ FIX: Present only when BOTH url+token are ready
        .fullScreenCover(item: $joinInfo) { info in
            NavigationView {
                LiveKitRoomView(
                    manager: liveKitManager,
                    roomUrl: info.url,
                    token: info.token,
                    bankPhoneNumber: info.bankPhoneNumber,
                    bootstrapPayload: info.bootstrapPayload
                )
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
                .frame(width: 100, height: 100)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(20)

            Text("Provide details for your dispute")
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
            SectionHeader(title: "Dispute Details", icon: "list.bullet.clipboard")

            // Summary
            fieldBlock(title: "Summary") {
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
                fieldBlock(title: "Amount") {
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

                fieldBlock(title: "Currency") {
                    Menu {
                        ForEach(currencies, id: \.self) { code in
                            Button {
                                currency = code
                            } label: {
                                HStack {
                                    Text(code)
                                    if currency == code { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(currency).foregroundColor(.primary)
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
            fieldBlock(title: "Merchant") {
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
            fieldBlock(title: "Transaction Date") {
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
            fieldBlock(title: "Reason") {
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
                        Button {
                            selectedBank = bank
                            // Clear custom inputs when selecting a predefined bank
                            if !bank.isOthers {
                                customBankName = ""
                                customBankPhone = ""
                            }
                        } label: {
                            HStack {
                                Text(bank.name)
                                if selectedBank?.id == bank.id { Image(systemName: "checkmark") }
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

            // Credit card number
            VStack(alignment: .leading, spacing: 8) {
                Text("Credit Card Number")
                    .font(.subheadline)
                    .fontWeight(.medium)

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
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered.count <= 19 {
                            if cardNumber != filtered { cardNumber = filtered }
                        } else {
                            cardNumber = String(filtered.prefix(19))
                        }
                    }

                if !cardNumber.isEmpty {
                    HStack {
                        Text("Card: \(maskedCardNumber)")
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

    private func fieldBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            content()
        }
    }

    private var submitButton: some View {
        Button(action: handleSubmit) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 18))
                Text("Save")
                    .fontWeight(.semibold)
            }
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
        .disabled(!isFormValid || isStartingRoom)
    }

    private var createChatroomButton: some View {
        Button(action: handleCreateChatroom) {
            HStack(spacing: 10) {
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
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke((isFormValid && !isStartingRoom) ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .disabled(!isFormValid || isStartingRoom)
    }

    // MARK: - Validation / formatting

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
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidAmount(amount) &&
        !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isValidCardNumber(cardNumber)
    }

    private func isValidAmount(_ value: String) -> Bool {
        guard let number = Double(value), number >= 0 else { return false }
        return true
    }

    private func isValidCardNumber(_ value: String) -> Bool {
        let digitsOnly = value.filter { $0.isNumber }
        return digitsOnly.count >= 4 && digitsOnly.count <= 19
    }

    // MARK: - Helpers

    private func getCategoryName(for serviceItem: ServiceItem) -> String {
        let categories = ServiceCategoryManager.shared.categories
        for category in categories {
            let items = ServiceItemManager.shared.getServiceItems(for: category.name)
            if items.contains(where: { $0.id == serviceItem.id || $0.title == serviceItem.title }) {
                return category.name
            }
        }
        return "Other"
    }

    // MARK: - Submit

    private func handleSubmit() {
        guard isFormValid else {
            alertTitle = "Notice"
            alertMessage = "Please complete all fields correctly. Amount must be numeric and card number must be at least 4 digits."
            showAlert = true
            return
        }

        guard let profile = UserProfileService.loadProfile() else {
            alertTitle = "Profile Missing"
            alertMessage = "Profile not found. Please fill in your profile first."
            showAlert = true
            return
        }

        guard let amountValue = Double(amount) else {
            alertTitle = "Invalid Amount"
            alertMessage = "Amount must be numeric."
            showAlert = true
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: txnDate)

        let digitsOnly = cardNumber.filter { $0.isNumber }
        let fullCardNumber = digitsOnly.isEmpty ? nil : digitsOnly  // Save full card number
        let bankInfo = currentBankInfo()
        
        let disputePayload = DisputeCase.Dispute(
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

        do {
            let categoryName = getCategoryName(for: serviceItem)
            let savedURL = try DisputeCaseService.saveCase(
                profile: profile,
                dispute: disputePayload,
                categoryName: categoryName,
                serviceItemTitle: serviceItem.title
            )
            
            print("✅ Successfully saved dispute case")
            print("   File saved at: \(savedURL.path)")
            print("   You can find it in: ../UserData/[your_username]/\(categoryName)/")

            NotificationCenter.default.post(name: NSNotification.Name("TaskListNeedsUpdate"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("DismissToServiceCategory"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("DismissToBankPage"), object: nil)
            dismiss()

        } catch {
            print("❌ Failed to save dispute case: \(error.localizedDescription)")
            alertTitle = "Error"
            alertMessage = "Failed to save dispute: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func handleCreateChatroom() {
        guard isFormValid else {
            alertTitle = "Notice"
            alertMessage = "Please complete all fields correctly. Amount must be numeric and card number must be at least 4 digits."
            showAlert = true
            return
        }

        guard let profile = UserProfileService.loadProfile() else {
            alertTitle = "Profile Missing"
            alertMessage = "Profile not found. Please fill in your profile first."
            showAlert = true
            return
        }

        let bankInfo = currentBankInfo()
        let disputePayload = makeDisputePayload(bankInfo: bankInfo)
        startLiveKitRoom(
            profile: profile,
            bankPhoneNumber: bankInfo.phoneNumber,
            disputePayload: disputePayload
        )
    }

    private func currentBankInfo() -> (name: String?, phoneNumber: String?) {
        if let bank = selectedBank, bank.isOthers {
            let bankName = customBankName.trimmingCharacters(in: .whitespaces)
            let phoneNumber = customBankPhone.trimmingCharacters(in: .whitespaces)
            let formattedPhone: String?
            if phoneNumber.isEmpty {
                formattedPhone = nil
            } else {
                formattedPhone = "\(selectedCountryCode.code)\(phoneNumber)"
            }
            return (
                name: bankName.isEmpty ? nil : bankName,
                phoneNumber: formattedPhone
            )
        }

        return (name: selectedBank?.name, phoneNumber: selectedBank?.phoneNumber)
    }

    // MARK: - LiveKit start (FIXED)

    private func startLiveKitRoom(
        profile: UserProfile,
        bankPhoneNumber: String?,
        disputePayload: DisputeCase.Dispute?
    ) {
        guard !isStartingRoom else { return }
        isStartingRoom = true

        Task {
            defer { Task { @MainActor in isStartingRoom = false } }

            do {
                let roomName = AppConfig.liveKitRoom
                let identity = "customer_\(profile.firstName.lowercased())_\(profile.lastName.lowercased())"
                let name = "\(profile.firstName) \(profile.lastName)"

                let resp = try await LiveKitTokenAPI.fetchToken(
                    room: roomName,
                    identity: identity,
                    name: name
                )

                let candidate = (resp.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
                        profile: .init(userProfile: profile),
                        dispute: disputePayload.map { .init(dispute: $0) }
                    )
                    // ✅ atomic presentation payload with bank phone number
                    self.joinInfo = LiveKitJoinInfo(
                        url: cleaned,
                        token: resp.token,
                        bankPhoneNumber: bankPhoneNumber,
                        bootstrapPayload: bootstrapPayload
                    )
                }

            } catch {
                await MainActor.run {
                    self.alertTitle = "LiveKit Error"
                    self.alertMessage = "Failed to get token: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }

    private func makeDisputePayload(bankInfo: (name: String?, phoneNumber: String?)) -> DisputeCase.Dispute? {
        guard let amountValue = Double(amount) else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: txnDate)

        let digitsOnly = cardNumber.filter { $0.isNumber }
        let fullCardNumber = digitsOnly.isEmpty ? nil : digitsOnly

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
}

#Preview {
    NavigationView {
        DisputeTransactionFormView(
            serviceItem: ServiceItem(
                title: "Credit Card Issues",
                icon: "creditcard.fill",
                iconColor: .blue,
                description: "Credit card problems and inquiries"
            )
        )
    }
}
