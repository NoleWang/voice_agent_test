//
//  DisputeCase.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation

/// Bank information model
struct Bank: Identifiable, Codable {
    let id: String
    let name: String
    let phoneNumber: String
    
    static let allBanks: [Bank] = [
        // US Banks
        Bank(id: "chase", name: "Chase Bank", phoneNumber: "1-800-935-9935"),
        Bank(id: "bankofamerica", name: "Bank of America", phoneNumber: "1-800-432-1000"),
        Bank(id: "wellsfargo", name: "Wells Fargo", phoneNumber: "1-800-869-3557"),
        Bank(id: "citibank", name: "Citibank", phoneNumber: "1-800-374-9700"),
        Bank(id: "usbank", name: "U.S. Bank", phoneNumber: "1-800-872-2657"),
        Bank(id: "pnc", name: "PNC Bank", phoneNumber: "1-888-762-2265"),
        Bank(id: "capitalone", name: "Capital One", phoneNumber: "1-877-383-4802"),
        Bank(id: "tdbank", name: "TD Bank", phoneNumber: "1-888-751-9000"),
        Bank(id: "bbt", name: "BB&T (Truist)", phoneNumber: "1-800-226-5228"),
        Bank(id: "suntrust", name: "SunTrust (Truist)", phoneNumber: "1-800-786-8787"),
        
        // Chinese Banks
        Bank(id: "icbc", name: "中国工商银行 (ICBC)", phoneNumber: "95588"),
        Bank(id: "ccb", name: "中国建设银行 (CCB)", phoneNumber: "95533"),
        Bank(id: "abc", name: "中国农业银行 (ABC)", phoneNumber: "95599"),
        Bank(id: "boc", name: "中国银行 (BOC)", phoneNumber: "95566"),
        Bank(id: "cmb", name: "招商银行 (CMB)", phoneNumber: "95555"),
        Bank(id: "spdb", name: "浦发银行 (SPDB)", phoneNumber: "95528"),
        Bank(id: "cib", name: "兴业银行 (CIB)", phoneNumber: "95561"),
        Bank(id: "ceb", name: "光大银行 (CEB)", phoneNumber: "95595"),
        Bank(id: "pingan", name: "平安银行 (Ping An)", phoneNumber: "95511"),
        Bank(id: "citic", name: "中信银行 (CITIC)", phoneNumber: "95558"),
        
        // Other International Banks
        Bank(id: "hsbc", name: "HSBC", phoneNumber: "1-888-662-4722"),
        Bank(id: "barclays", name: "Barclays", phoneNumber: "1-888-232-0780"),
        Bank(id: "deutsche", name: "Deutsche Bank", phoneNumber: "1-800-728-3340"),
        Bank(id: "jpmorgan", name: "JPMorgan Chase", phoneNumber: "1-212-270-6000"),
        Bank(id: "goldmansachs", name: "Goldman Sachs", phoneNumber: "1-212-902-1000"),
        
        // Credit Card Companies
        Bank(id: "amex", name: "American Express", phoneNumber: "1-800-528-4800"),
        Bank(id: "discover", name: "Discover", phoneNumber: "1-800-347-2683"),
        Bank(id: "mastercard", name: "Mastercard", phoneNumber: "1-800-627-8372"),
        Bank(id: "visa", name: "Visa", phoneNumber: "1-800-847-2911"),
        
        // Others option
        Bank(id: "others", name: "Others", phoneNumber: "")
    ]
    
    /// Check if this is the "Others" option
    var isOthers: Bool {
        return id == "others"
    }
}

/// Payload structures for saving dispute cases to JSON
struct DisputeCase: Codable {
    struct Profile: Codable {
        let first_name: String
        let last_name: String
        let email: String
        let address: String
        let phone: String
    }
    
    struct Dispute: Codable {
        let summary: String
        let amount: Double
        let currency: String
        let merchant: String
        let txn_date: String
        let reason: String
        let last4: String  // Last 4 digits for display
        let fullCardNumber: String?  // Full card number (optional for backward compatibility)
        let bankName: String?  // Bank name (optional for backward compatibility)
        let bankPhoneNumber: String?  // Bank phone number (optional for backward compatibility)
        
        init(summary: String, amount: Double, currency: String, merchant: String, txn_date: String, reason: String, last4: String, fullCardNumber: String? = nil, bankName: String? = nil, bankPhoneNumber: String? = nil) {
            self.summary = summary
            self.amount = amount
            self.currency = currency
            self.merchant = merchant
            self.txn_date = txn_date
            self.reason = reason
            self.last4 = last4
            self.fullCardNumber = fullCardNumber
            self.bankName = bankName
            self.bankPhoneNumber = bankPhoneNumber
        }
    }
    
    let profile: Profile
    let dispute: Dispute
}

/// Task item model for displaying active tasks
struct TaskItem: Identifiable {
    let id: String
    let fileURL: URL
    let categoryName: String
    let serviceItemTitle: String
    let merchant: String
    let amount: Double
    let currency: String
    let createdAt: Date
}

/// Service to persist dispute cases as JSON files under "dispute transaction" folder
enum DisputeCaseService {
    
    /// Save a dispute case to disk. Returns saved file URL on success.
    static func saveCase(profile: UserProfile, dispute: DisputeCase.Dispute, categoryName: String, serviceItemTitle: String) throws -> URL {
        let casePayload = DisputeCase(
            profile: .init(
                first_name: profile.firstName,
                last_name: profile.lastName,
                email: profile.email,
                address: profile.address,
                phone: profile.phoneNumber
            ),
            dispute: dispute
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(casePayload)
        
        let folderURL = try ensureFolder(categoryName: categoryName)
        let fileName = makeFileName()
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
    
    /// Get current username from Keychain
    private static func getCurrentUsername() -> String? {
        guard let userInfo = try? KeychainService.loadUserInfo() else {
            return nil
        }
        return userInfo.username
    }
    
    /// Ensure the category folder exists under user's folder in UserData
    /// Tries project directory first, falls back to Documents if permission denied
    private static func ensureFolder(categoryName: String) throws -> URL {
        guard let username = getCurrentUsername() else {
            throw NSError(
                domain: "DisputeCaseService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No user logged in. Please login first."]
            )
        }
        
        let fm = FileManager.default
        
        // First, try to use project's UserData folder: UserData/[username]/[categoryName]
        let userDataPath = "/Users/alexliu/Desktop/VoiceAgent/iOS/VoiceAgent/UserData"
        let userFolder = (userDataPath as NSString).appendingPathComponent(username)
        let categoryFolder = (userFolder as NSString).appendingPathComponent(categoryName)
        let projectFolderURL = URL(fileURLWithPath: categoryFolder, isDirectory: true)
        
        // Check if base UserData folder exists, create if not
        let baseFolderURL = URL(fileURLWithPath: userDataPath, isDirectory: true)
        if !fm.fileExists(atPath: baseFolderURL.path) {
            do {
                try fm.createDirectory(at: baseFolderURL, withIntermediateDirectories: true, attributes: [
                    .posixPermissions: 0o755
                ])
            } catch {
                // If creation fails, fall back to Documents
                return try ensureFolderInDocuments(username: username, categoryName: categoryName)
            }
        }
        
        // Check if user folder exists, create if not
        let userFolderURL = URL(fileURLWithPath: userFolder, isDirectory: true)
        if !fm.fileExists(atPath: userFolderURL.path) {
            do {
                try fm.createDirectory(at: userFolderURL, withIntermediateDirectories: true, attributes: [
                    .posixPermissions: 0o755
                ])
            } catch {
                // If creation fails, fall back to Documents
                return try ensureFolderInDocuments(username: username, categoryName: categoryName)
            }
        }
        
        // Check if category folder exists, create if not
        if !fm.fileExists(atPath: projectFolderURL.path) {
            do {
                try fm.createDirectory(at: projectFolderURL, withIntermediateDirectories: true, attributes: [
                    .posixPermissions: 0o755
                ])
            } catch {
                // If creation fails, fall back to Documents
                return try ensureFolderInDocuments(username: username, categoryName: categoryName)
            }
        }
        
        // Verify write permissions by attempting to create a test file
        let testFile = projectFolderURL.appendingPathComponent(".write_test")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: testFile)  // Clean up test file
            // Success! Return project folder
            return projectFolderURL
        } catch {
            // Write test failed, fall back to Documents directory
            return try ensureFolderInDocuments(username: username, categoryName: categoryName)
        }
    }
    
    /// Fallback: Ensure the category folder exists under Documents: UserData/[username]/[categoryName]
    private static func ensureFolderInDocuments(username: String, categoryName: String) throws -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let userDataFolder = docs.appendingPathComponent("UserData", isDirectory: true)
        let userFolder = userDataFolder.appendingPathComponent(username, isDirectory: true)
        let categoryFolder = userFolder.appendingPathComponent(categoryName, isDirectory: true)
        
        if !fm.fileExists(atPath: categoryFolder.path) {
            try fm.createDirectory(at: categoryFolder, withIntermediateDirectories: true)
        }
        
        return categoryFolder
    }
    
    /// Build a file name with timestamp
    private static func makeFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let ts = formatter.string(from: Date())
        return "dispute_\(ts).json"
    }
    
    /// Load all saved dispute files as task items from current user's folders
    /// Checks both project directory and Documents directory
    static func loadAllTasks() -> [TaskItem] {
        guard let username = getCurrentUsername() else {
            return []
        }
        
        let fm = FileManager.default
        var tasks: [TaskItem] = []
        
        // Try to load from project directory first: UserData/[username]/[categoryName]
        let userDataPath = "/Users/alexliu/Desktop/VoiceAgent/iOS/VoiceAgent/UserData"
        let userFolder = (userDataPath as NSString).appendingPathComponent(username)
        let userFolderURL = URL(fileURLWithPath: userFolder, isDirectory: true)
        
        if fm.fileExists(atPath: userFolderURL.path) {
            if let categoryFolders = try? fm.contentsOfDirectory(at: userFolderURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                tasks.append(contentsOf: loadTasksFromFolders(categoryFolders: categoryFolders))
            }
        }
        
        // Also load from Documents directory (fallback location): UserData/[username]/[categoryName]
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let userDataFolder = docs.appendingPathComponent("UserData")
            let userFolder = userDataFolder.appendingPathComponent(username, isDirectory: true)
            if fm.fileExists(atPath: userFolder.path) {
                if let categoryFolders = try? fm.contentsOfDirectory(at: userFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    tasks.append(contentsOf: loadTasksFromFolders(categoryFolders: categoryFolders))
                }
            }
        }
        
        // Sort by creation date, most recent first
        return tasks.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Helper method to load tasks from category folders
    private static func loadTasksFromFolders(categoryFolders: [URL]) -> [TaskItem] {
        let fm = FileManager.default
        var tasks: [TaskItem] = []
        
        for categoryFolder in categoryFolders {
            // Check if it's a directory
            guard let isDirectory = try? categoryFolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDirectory == true else {
                continue
            }
            
            let categoryName = categoryFolder.lastPathComponent
            
            // Get all JSON files in this category folder
            guard let files = try? fm.contentsOfDirectory(at: categoryFolder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            
            for file in files where file.pathExtension == "json" {
                do {
                    let data = try Data(contentsOf: file)
                    let decoder = JSONDecoder()
                    let disputeCase = try decoder.decode(DisputeCase.self, from: data)
                    
                    // Get file attributes
                    let attributes = try? fm.attributesOfItem(atPath: file.path)
                    let createdAt = attributes?[.creationDate] as? Date ?? 
                                   (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                    
                    // Use default service item title
                    let serviceItemTitle = "Dispute Transaction"
                    
                    let task = TaskItem(
                        id: file.lastPathComponent,
                        fileURL: file,
                        categoryName: categoryName,
                        serviceItemTitle: serviceItemTitle,
                        merchant: disputeCase.dispute.merchant,
                        amount: disputeCase.dispute.amount,
                        currency: disputeCase.dispute.currency,
                        createdAt: createdAt
                    )
                    tasks.append(task)
                } catch {
                    print("⚠️ Failed to decode file \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        
        return tasks
    }
    
    /// Delete a dispute file
    static func deleteTask(fileURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try fm.removeItem(at: fileURL)
        }
    }
}
