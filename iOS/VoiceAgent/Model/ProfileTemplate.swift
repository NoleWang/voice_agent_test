//
//  ProfileTemplate.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation

/// Profile template model
struct ProfileTemplate: Identifiable, Codable {
    let id: UUID
    let name: String
    let firstName: String
    let lastName: String
    let email: String
    let address: String
    let phoneNumber: String
    let createdAt: Date
    let updatedAt: Date
    
    init(id: UUID = UUID(), name: String, firstName: String, lastName: String, email: String, address: String, phoneNumber: String, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.address = address
        self.phoneNumber = phoneNumber
        self.createdAt = createdAt ?? Date()
        self.updatedAt = updatedAt ?? Date()
    }
    
    var fullName: String {
        return "\(firstName) \(lastName)"
    }
    
    /// Create template from UserProfile
    static func from(profile: UserProfile, name: String) -> ProfileTemplate {
        return ProfileTemplate(
            name: name,
            firstName: profile.firstName,
            lastName: profile.lastName,
            email: profile.email,
            address: profile.address,
            phoneNumber: profile.phoneNumber
        )
    }
    
    /// Convert to UserProfile
    func toUserProfile() -> UserProfile {
        return UserProfile(
            firstName: firstName,
            lastName: lastName,
            email: email,
            address: address,
            phoneNumber: phoneNumber
        )
    }
}

/// Service for managing profile templates (user-specific)
class ProfileTemplateService {
    /// Get storage key for current user
    private static func storageKey() -> String {
        if let userInfo = try? KeychainService.loadUserInfo() {
            return "profileTemplates_\(userInfo.username)"
        }
        return "profileTemplates_default"
    }
    
    /// Save all templates for current user
    static func saveTemplates(_ templates: [ProfileTemplate]) {
        if let encoded = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(encoded, forKey: storageKey())
        }
    }
    
    /// Load all templates for current user
    static func loadTemplates() -> [ProfileTemplate] {
        if let data = UserDefaults.standard.data(forKey: storageKey()),
           let templates = try? JSONDecoder().decode([ProfileTemplate].self, from: data) {
            return templates
        }
        return []
    }
    
    /// Add a new template
    static func addTemplate(_ template: ProfileTemplate) {
        var templates = loadTemplates()
        templates.append(template)
        saveTemplates(templates)
    }
    
    /// Update an existing template
    static func updateTemplate(_ template: ProfileTemplate) {
        var templates = loadTemplates()
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            // Preserve createdAt, update updatedAt
            let originalTemplate = templates[index]
            templates[index] = ProfileTemplate(
                id: originalTemplate.id,
                name: template.name,
                firstName: template.firstName,
                lastName: template.lastName,
                email: template.email,
                address: template.address,
                phoneNumber: template.phoneNumber,
                createdAt: originalTemplate.createdAt,
                updatedAt: Date()
            )
            saveTemplates(templates)
        }
    }
    
    /// Delete a template
    static func deleteTemplate(_ template: ProfileTemplate) {
        var templates = loadTemplates()
        templates.removeAll { $0.id == template.id }
        saveTemplates(templates)
    }
    
    /// Delete template by ID
    static func deleteTemplate(id: UUID) {
        var templates = loadTemplates()
        templates.removeAll { $0.id == id }
        saveTemplates(templates)
    }
}

