//
//  AuthView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI

struct AuthView: View {
    @ObservedObject var viewModel: ContentViewModel
    
    @State private var isLoginMode = true
    @State private var username = ""
    @State private var password = ""
    
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case username, password
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // 标题区域
                    headerSection
                    
                    // 登录表单
                    loginForm
                    
                    // 登录按钮
                    loginButton
                    
                    // 注册链接
                    registerLink
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Login")
            .navigationBarTitleDisplayMode(.large)
            .alert("Notice", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                checkIfRegistered()
            }
        }
    }
    
    // 检查是否已注册
    private func checkIfRegistered() {
        let isRegistered = KeychainService.userInfoExists() && KeychainService.passwordExists()
        if !isRegistered {
            // 如果未注册，跳转到注册界面
            isLoginMode = false
        }
    }
    
    // 标题区域
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Welcome Back")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }
    
    // 登录表单
    private var loginForm: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Login", icon: "person.circle.fill")
                
                CustomTextField(
                    title: "Username",
                    text: $username,
                    placeholder: "Enter your username",
                    keyboardType: .default
                )
                .focused($focusedField, equals: .username)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                
                CustomSecureField(
                    title: "Password",
                    text: $password,
                    placeholder: "Enter your password"
                )
                .focused($focusedField, equals: .password)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }
    
    // 登录按钮
    private var loginButton: some View {
        Button(action: {
            handleLogin()
        }) {
            HStack {
                Text("Login")
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
        .disabled(!isFormValid)
        .padding(.top, 8)
    }
    
    // 注册链接
    private var registerLink: some View {
        NavigationLink(destination: RegisterView()) {
            HStack {
                Text("Don't have an account?")
                    .foregroundColor(.secondary)
                Text("Register")
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
        .padding(.top, 8)
    }
    
    // 表单验证
    private var isFormValid: Bool {
        return !username.isEmpty && !password.isEmpty
    }
    
    // 处理登录
    private func handleLogin() {
        do {
            // 加载用户信息以验证用户名
            guard let userInfo = try KeychainService.loadUserInfo() else {
                alertMessage = "User not found. Please register first."
                showAlert = true
                return
            }
            
            // 验证用户名
            if userInfo.username != username {
                alertMessage = "Incorrect username. Please try again."
                showAlert = true
                username = ""
                password = ""
                return
            }
            
            // 验证密码
            let isValid = try KeychainService.verifyPassword(password)
            if isValid {
                alertMessage = "Login successful!\nWelcome back, \(userInfo.username)!"
                showAlert = true
                clearForm()
                // 登录成功后通知 ViewModel
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    viewModel.handleLoginSuccess()
                }
            } else {
                alertMessage = "Incorrect password. Please try again."
                showAlert = true
                password = ""
            }
        } catch {
            alertMessage = "Failed to verify login: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    // 清空表单
    private func clearForm() {
        password = ""
    }
}

// 注册界面
struct RegisterView: View {
    @State private var username = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var useSystemPassword = false
    @State private var generatedPassword = ""
    @State private var showGeneratedPassword = false
    
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss
    
    enum Field: Hashable {
        case username, firstName, lastName, email, phone, address, password, confirmPassword
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 标题区域
                headerSection
                
                // 表单区域
                formSection
                
                // 提交按钮
                submitButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Register")
        .navigationBarTitleDisplayMode(.large)
        .alert("Notice", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    // 标题区域
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.badge.plus.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Create Your Account")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }
    
    // 表单区域
    private var formSection: some View {
        VStack(spacing: 20) {
            // 用户名部分
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Username", icon: "person.circle.fill")
                
                CustomTextField(
                    title: "Username",
                    text: $username,
                    placeholder: "Enter username",
                    keyboardType: .default
                )
                .focused($focusedField, equals: .username)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            
            // 姓名部分
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Name", icon: "person.fill")
                
                HStack(spacing: 12) {
                    CustomTextField(
                        title: "First Name",
                        text: $firstName,
                        placeholder: "Enter first name",
                        keyboardType: .default
                    )
                    .focused($focusedField, equals: .firstName)
                    
                    CustomTextField(
                        title: "Last Name",
                        text: $lastName,
                        placeholder: "Enter last name",
                        keyboardType: .default
                    )
                    .focused($focusedField, equals: .lastName)
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
            
            // 联系方式部分
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Contact Information", icon: "phone.fill")
                
                CustomTextField(
                    title: "Email",
                    text: $email,
                    placeholder: "example@email.com",
                    keyboardType: .emailAddress
                )
                .focused($focusedField, equals: .email)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                
                // 邮箱格式验证提示
                if !email.isEmpty {
                    HStack {
                        if isValidEmail(email.trimmingCharacters(in: .whitespaces)) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        Text(isValidEmail(email.trimmingCharacters(in: .whitespaces)) ? "Valid email format" : "Invalid email format (e.g., example@email.com)")
                            .font(.caption)
                            .foregroundColor(isValidEmail(email.trimmingCharacters(in: .whitespaces)) ? .green : .red)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                }
                
                CustomTextField(
                    title: "Phone Number",
                    text: $phone,
                    placeholder: "Enter phone number",
                    keyboardType: .phonePad
                )
                .focused($focusedField, equals: .phone)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            
            // 地址部分
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Address", icon: "house.fill")
                
                CustomTextField(
                    title: "Address",
                    text: $address,
                    placeholder: "Enter your address",
                    keyboardType: .default
                )
                .focused($focusedField, equals: .address)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            
            // 密码部分
            passwordSection
        }
    }
    
    // 密码部分
    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Password", icon: "lock.fill")
            
            // 密码生成选项
            HStack {
                Toggle("Use system-generated password", isOn: Binding(
                    get: { useSystemPassword },
                    set: { newValue in
                        useSystemPassword = newValue
                        if newValue {
                            generatePassword()
                        } else {
                            generatedPassword = ""
                            showGeneratedPassword = false
                            password = ""
                            confirmPassword = ""
                        }
                    }
                ))
                .font(.subheadline)
                .tint(.blue)
                
                Spacer()
            }
            .padding(.bottom, 4)
            
            // 显示系统生成的密码（如果启用）
            if useSystemPassword && showGeneratedPassword && !generatedPassword.isEmpty {
                generatedPasswordSection
            }
            
            // 密码输入框（根据是否使用系统密码显示不同）
            if useSystemPassword && showGeneratedPassword {
                // 如果使用系统密码但还没接受，显示提示
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Please accept the generated password above to continue")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                    )
                }
            } else if useSystemPassword && !showGeneratedPassword && !password.isEmpty {
                // 已接受系统密码，显示确认信息
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Password has been set")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            } else if !useSystemPassword {
                // 手动输入模式
                CustomSecureField(
                    title: "Password",
                    text: $password,
                    placeholder: "Enter password (min 6 characters)"
                )
                .focused($focusedField, equals: .password)
                
                // 密码长度提示
                if !password.isEmpty {
                    HStack {
                        if password.count >= 6 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        Text("Password must be at least 6 characters")
                            .font(.caption)
                            .foregroundColor(password.count >= 6 ? .green : .red)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                }
                
                CustomSecureField(
                    title: "Confirm Password",
                    text: $confirmPassword,
                    placeholder: "Re-enter password"
                )
                .focused($focusedField, equals: .confirmPassword)
                
                // 密码匹配提示
                if !password.isEmpty && !confirmPassword.isEmpty {
                    HStack {
                        if password == confirmPassword {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        Text(password == confirmPassword ? "Passwords match" : "Passwords do not match")
                            .font(.caption)
                            .foregroundColor(password == confirmPassword ? .green : .red)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
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
    
    // 生成的密码显示区域
    private var generatedPasswordSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Generated Password")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: {
                    rejectGeneratedPassword()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            }
            
            // 显示生成的密码
            HStack {
                Text(generatedPassword)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                    )
                
                Button(action: {
                    UIPasteboard.general.string = generatedPassword
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                        .padding(8)
                }
            }
            
            // 接受/拒绝按钮
            HStack(spacing: 12) {
                Button(action: {
                    acceptGeneratedPassword()
                }) {
                    Text("Use This Password")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                }
                
                Button(action: {
                    rejectGeneratedPassword()
                }) {
                    Text("Generate New")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
    
    // 提交按钮
    private var submitButton: some View {
        VStack(spacing: 8) {
            // 如果表单无效，显示缺少的字段提示
            if !isFormValid {
                let missingFields = getMissingFields()
                if !missingFields.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Please complete the following:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(missingFields, id: \.self) { field in
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption2)
                                Text(field)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
                    )
                }
            }
            
            Button(action: {
                handleRegistration()
            }) {
                HStack {
                    Text("Register")
                        .fontWeight(.semibold)
                    if isFormValid {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isFormValid ? Color.blue : Color.gray.opacity(0.5))
                .foregroundColor(isFormValid ? .white : .gray)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFormValid ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
            .disabled(!isFormValid)
        }
        .padding(.top, 8)
    }
    
    // 获取缺少的字段列表
    private func getMissingFields() -> [String] {
        var missing: [String] = []
        
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        
        if trimmedUsername.isEmpty {
            missing.append("Username")
        }
        if trimmedFirstName.isEmpty {
            missing.append("First Name")
        }
        if trimmedLastName.isEmpty {
            missing.append("Last Name")
        }
        if trimmedEmail.isEmpty {
            missing.append("Email")
        } else if !isValidEmail(trimmedEmail) {
            missing.append("Valid Email (format: example@email.com)")
        }
        if trimmedPhone.isEmpty {
            missing.append("Phone Number")
        }
        if trimmedAddress.isEmpty {
            missing.append("Address")
        }
        
        // 检查密码
        if useSystemPassword {
            if password.isEmpty || confirmPassword.isEmpty || password != confirmPassword {
                missing.append("Accept generated password")
            }
        } else {
            if password.isEmpty {
                missing.append("Password")
            } else if password.count < 6 {
                missing.append("Password (at least 6 characters)")
            }
            if confirmPassword.isEmpty {
                missing.append("Confirm Password")
            } else if password != confirmPassword {
                missing.append("Passwords must match")
            }
        }
        
        return missing
    }
    
    // 表单验证
    private var isFormValid: Bool {
        // 检查基本信息是否填写
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        
        let hasUsername = !trimmedUsername.isEmpty
        let hasFirstName = !trimmedFirstName.isEmpty
        let hasLastName = !trimmedLastName.isEmpty
        let hasValidEmail = isValidEmail(trimmedEmail)
        let hasPhone = !trimmedPhone.isEmpty
        let hasAddress = !trimmedAddress.isEmpty
        
        let hasBasicInfo = hasUsername &&
                          hasFirstName &&
                          hasLastName &&
                          hasValidEmail &&
                          hasPhone &&
                          hasAddress
        
        // 检查密码是否有效
        let hasValidPassword: Bool
        if useSystemPassword {
            // 如果使用系统密码，必须已经接受密码（password 和 confirmPassword 都不为空且匹配）
            hasValidPassword = !password.isEmpty && 
                               !confirmPassword.isEmpty &&
                               password == confirmPassword
        } else {
            // 手动输入模式，检查密码长度和匹配
            // 确保密码不为空、确认密码不为空、两者匹配、且密码长度至少6位
            let passwordNotEmpty = !password.isEmpty
            let confirmPasswordNotEmpty = !confirmPassword.isEmpty
            let passwordsMatch = password == confirmPassword
            let passwordLengthValid = password.count >= 6
            
            hasValidPassword = passwordNotEmpty &&
                               confirmPasswordNotEmpty &&
                               passwordsMatch &&
                               passwordLengthValid
        }
        
        // 只有当所有基本信息都填写且密码有效时，表单才有效
        let isValid = hasBasicInfo && hasValidPassword
        return isValid
    }
    
    // 验证邮箱格式
    private func isValidEmail(_ email: String) -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty else { return false }
        
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: trimmedEmail)
    }
    
    // 处理注册
    private func handleRegistration() {
        // 如果使用系统密码但还没有接受，提示用户
        if useSystemPassword && password.isEmpty {
            alertMessage = "Please accept the generated password first by clicking 'Use This Password'"
            showAlert = true
            return
        }
        
        // 验证密码匹配
        if password != confirmPassword {
            alertMessage = "Passwords do not match"
            showAlert = true
            return
        }
        
        // 验证密码长度（如果不是系统生成的）
        if !useSystemPassword && password.count < 6 {
            alertMessage = "Password must be at least 6 characters"
            showAlert = true
            return
        }
        
        // 创建用户信息对象（使用 trim 后的值）
        let userInfo = UserInfo(
            username: username.trimmingCharacters(in: .whitespaces),
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces),
            phone: phone.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespaces)
        )
        
        do {
            // 保存用户信息到 Keychain
            try KeychainService.saveUserInfo(userInfo)
            
            // 保存密码到 Keychain
            try KeychainService.savePassword(password)
            
            alertMessage = "Registration successful!\n\nUsername: \(username)\nName: \(userInfo.fullName)\nEmail: \(email)\n\nYour account has been created and saved to Keychain."
            showAlert = true
            
            // 注册成功后返回登录界面
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                dismiss()
            }
        } catch {
            alertMessage = "Failed to save information to Keychain: \(error.localizedDescription)\n\nPlease try again."
            showAlert = true
        }
    }
    
    // 生成强密码
    private func generatePassword() {
        let length = 16
        let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let lowercase = "abcdefghijklmnopqrstuvwxyz"
        let numbers = "0123456789"
        let symbols = "!@#$%^&*"
        let allChars = uppercase + lowercase + numbers + symbols
        
        var password = ""
        
        // 确保至少包含一个大写、小写、数字和符号
        password += String(uppercase.randomElement()!)
        password += String(lowercase.randomElement()!)
        password += String(numbers.randomElement()!)
        password += String(symbols.randomElement()!)
        
        // 填充剩余长度
        for _ in 4..<length {
            password += String(allChars.randomElement()!)
        }
        
        // 打乱字符顺序
        generatedPassword = String(password.shuffled())
        showGeneratedPassword = true
    }
    
    // 接受生成的密码
    private func acceptGeneratedPassword() {
        password = generatedPassword
        confirmPassword = generatedPassword
        showGeneratedPassword = false
    }
    
    // 拒绝生成的密码，生成新的
    private func rejectGeneratedPassword() {
        generatePassword()
    }
}

// 自定义文本输入框
struct CustomTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
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
}

// 自定义安全输入框
struct CustomSecureField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var useSystemPassword: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .textContentType(useSystemPassword ? .newPassword : .password)
                .autocorrectionDisabled()
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
}

// 区域标题组件
struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.system(size: 16))
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    AuthView(viewModel: ContentViewModel())
}

