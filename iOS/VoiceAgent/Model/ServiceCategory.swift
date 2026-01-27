//
//  ServiceCategory.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation
import SwiftUI

/// Service category model for organizing different service types
struct ServiceCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    let iconColorName: String
    let description: String
    
    var iconColor: Color {
        switch iconColorName {
        case "blue": return .blue
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "green": return .green
        case "yellow": return .yellow
        case "indigo": return .indigo
        case "gray": return .gray
        default: return .blue
        }
    }
    
    init(name: String, icon: String, iconColor: Color, description: String = "") {
        self.name = name
        self.icon = icon
        // Convert Color to string for Hashable conformance
        if iconColor == .blue {
            self.iconColorName = "blue"
        } else if iconColor == .orange {
            self.iconColorName = "orange"
        } else if iconColor == .red {
            self.iconColorName = "red"
        } else if iconColor == .purple {
            self.iconColorName = "purple"
        } else if iconColor == .green {
            self.iconColorName = "green"
        } else if iconColor == .yellow {
            self.iconColorName = "yellow"
        } else if iconColor == .indigo {
            self.iconColorName = "indigo"
        } else if iconColor == .gray {
            self.iconColorName = "gray"
        } else {
            self.iconColorName = "blue"
        }
        self.description = description
    }
}

/// Service category manager
class ServiceCategoryManager {
    static let shared = ServiceCategoryManager()
    
    /// Default service categories
    let categories: [ServiceCategory] = [
        ServiceCategory(
            name: "Bank",
            icon: "building.columns.fill",
            iconColor: .blue,
            description: "Banking services and financial institutions"
        ),
        ServiceCategory(
            name: "Merchant",
            icon: "storefront.fill",
            iconColor: .orange,
            description: "Merchants and retail services"
        ),
        ServiceCategory(
            name: "Healthcare",
            icon: "cross.case.fill",
            iconColor: .red,
            description: "Healthcare and medical services"
        ),
        ServiceCategory(
            name: "Government",
            icon: "building.2.fill",
            iconColor: .purple,
            description: "Government services and agencies"
        ),
        ServiceCategory(
            name: "Transportation",
            icon: "car.fill",
            iconColor: .green,
            description: "Transportation and logistics services"
        ),
        ServiceCategory(
            name: "Utilities",
            icon: "bolt.fill",
            iconColor: .yellow,
            description: "Utility services and providers"
        ),
        ServiceCategory(
            name: "Education",
            icon: "book.fill",
            iconColor: .indigo,
            description: "Educational institutions and services"
        ),
        ServiceCategory(
            name: "Other",
            icon: "ellipsis.circle.fill",
            iconColor: .gray,
            description: "Other services"
        )
    ]
    
    private init() {}
    
    /// Get sorted categories alphabetically
    var sortedCategories: [ServiceCategory] {
        return categories.sorted { $0.name < $1.name }
    }
    
    /// Get categories grouped by first letter
    var groupedCategories: [String: [ServiceCategory]] {
        Dictionary(grouping: sortedCategories) { category in
            String(category.name.prefix(1)).uppercased()
        }
    }
    
    /// Get sorted section headers (first letters)
    var sectionHeaders: [String] {
        return groupedCategories.keys.sorted()
    }
    
    /// Get category by name
    func getCategory(by name: String) -> ServiceCategory? {
        return categories.first { $0.name == name }
    }
}

