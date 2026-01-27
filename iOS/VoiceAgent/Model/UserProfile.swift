//
//  UserProfile.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation

/// User profile model for service-specific information
struct UserProfile: Codable {
    let firstName: String
    let lastName: String
    let email: String
    let address: String
    let phoneNumber: String
    let timestamp: Date
    
    init(firstName: String, lastName: String, email: String, address: String, phoneNumber: String) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.address = address
        self.phoneNumber = phoneNumber
        self.timestamp = Date()
    }
    
    var fullName: String {
        return "\(firstName) \(lastName)"
    }
}

/// Service for managing user profiles
class UserProfileService {
    private static let profileFileName = "profile.json"
    
    /// Get current username from Keychain
    private static func getCurrentUsername() -> String? {
        guard let userInfo = try? KeychainService.loadUserInfo() else {
            return nil
        }
        return userInfo.username
    }
    
    /// Get user folder path in UserData
    private static func getUserFolderURL(username: String) throws -> URL {
        let fm = FileManager.default
        
        // Try project directory first
        let userDataPath = "/Users/alexliu/Desktop/VoiceAgent/iOS/VoiceAgent/UserData"
        let userFolder = (userDataPath as NSString).appendingPathComponent(username)
        let projectFolderURL = URL(fileURLWithPath: userFolder, isDirectory: true)
        
        // Check if base UserData folder exists, create if not
        let baseFolderURL = URL(fileURLWithPath: userDataPath, isDirectory: true)
        if !fm.fileExists(atPath: baseFolderURL.path) {
            do {
                try fm.createDirectory(at: baseFolderURL, withIntermediateDirectories: true, attributes: [
                    .posixPermissions: 0o755
                ])
            } catch {
                // Fall back to Documents
                return try getUserFolderURLInDocuments(username: username)
            }
        }
        
        // Check if user folder exists, create if not
        if !fm.fileExists(atPath: projectFolderURL.path) {
            do {
                try fm.createDirectory(at: projectFolderURL, withIntermediateDirectories: true, attributes: [
                    .posixPermissions: 0o755
                ])
            } catch {
                // Fall back to Documents
                return try getUserFolderURLInDocuments(username: username)
            }
        }
        
        // Verify write permissions
        let testFile = projectFolderURL.appendingPathComponent(".write_test")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: testFile)
            return projectFolderURL
        } catch {
            // Fall back to Documents
            return try getUserFolderURLInDocuments(username: username)
        }
    }
    
    /// Fallback: Get user folder in Documents
    private static func getUserFolderURLInDocuments(username: String) throws -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let userDataFolder = docs.appendingPathComponent("UserData", isDirectory: true)
        let userFolder = userDataFolder.appendingPathComponent(username, isDirectory: true)
        
        if !fm.fileExists(atPath: userFolder.path) {
            try fm.createDirectory(at: userFolder, withIntermediateDirectories: true)
        }
        
        return userFolder
    }
    
    /// Save user profile to user's folder
    static func saveProfile(_ profile: UserProfile) throws -> URL {
        guard let username = getCurrentUsername() else {
            throw NSError(
                domain: "UserProfileService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No user logged in. Please login first."]
            )
        }
        
        let userFolderURL = try getUserFolderURL(username: username)
        let profileFileURL = userFolderURL.appendingPathComponent(profileFileName)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        
        try data.write(to: profileFileURL, options: .atomic)
        
        return profileFileURL
    }
    
    /// Load user profile from user's folder
    static func loadProfile() -> UserProfile? {
        guard let username = getCurrentUsername() else {
            return nil
        }
        
        // Try project directory first
        let userDataPath = "/Users/alexliu/Desktop/VoiceAgent/iOS/VoiceAgent/UserData"
        let userFolder = (userDataPath as NSString).appendingPathComponent(username)
        let projectProfileURL = URL(fileURLWithPath: userFolder).appendingPathComponent(profileFileName)
        
        if let data = try? Data(contentsOf: projectProfileURL),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            return profile
        }
        
        // Fall back to Documents directory
        let fm = FileManager.default
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let userDataFolder = docs.appendingPathComponent("UserData")
            let userFolder = userDataFolder.appendingPathComponent(username)
            let profileFileURL = userFolder.appendingPathComponent(profileFileName)
            
            if let data = try? Data(contentsOf: profileFileURL),
               let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
                return profile
            }
        }
        
        return nil
    }
    
    /// Delete user profile
    static func deleteProfile() throws {
        guard let username = getCurrentUsername() else {
            return
        }
        
        let userFolderURL = try getUserFolderURL(username: username)
        let profileFileURL = userFolderURL.appendingPathComponent(profileFileName)
        
        let fm = FileManager.default
        if fm.fileExists(atPath: profileFileURL.path) {
            try fm.removeItem(at: profileFileURL)
        }
    }
}

