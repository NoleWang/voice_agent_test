//
//  ServiceItem.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation
import SwiftUI

/// Service item model for specific services within a category
struct ServiceItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let icon: String
    let iconColorName: String
    let description: String
    let isOptional: Bool
    
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
    
    init(title: String, icon: String, iconColor: Color, description: String = "", isOptional: Bool = false) {
        self.title = title
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
        self.isOptional = isOptional
    }
}

/// Service item manager
class ServiceItemManager {
    static let shared = ServiceItemManager()
    
    /// Get service items for a specific category
    func getServiceItems(for categoryName: String) -> [ServiceItem] {
        switch categoryName {
        case "Bank":
            return bankServiceItems
        case "Merchant":
            return merchantServiceItems
        case "Healthcare":
            return healthcareServiceItems
        case "Government":
            return governmentServiceItems
        case "Transportation":
            return transportationServiceItems
        case "Utilities":
            return utilitiesServiceItems
        case "Education":
            return educationServiceItems
        default:
            return []
        }
    }
    
    /// Bank service items
    private var bankServiceItems: [ServiceItem] {
        [
            ServiceItem(
                title: "Credit Card Issues",
                icon: "creditcard.fill",
                iconColor: .blue,
                description: "Credit card problems and inquiries"
            ),
            ServiceItem(
                title: "Bank Card / Savings Account Issues",
                icon: "banknote.fill",
                iconColor: .green,
                description: "Bank card and savings account problems"
            ),
            ServiceItem(
                title: "Loan / Installment Issues",
                icon: "doc.text.fill",
                iconColor: .orange,
                description: "Loan and installment payment problems"
            ),
            ServiceItem(
                title: "Account Anomaly / Restricted",
                icon: "exclamationmark.triangle.fill",
                iconColor: .red,
                description: "Account anomalies and restrictions"
            ),
            ServiceItem(
                title: "Complaint / Other",
                icon: "envelope.fill",
                iconColor: .gray,
                description: "Complaints and other inquiries",
                isOptional: true
            )
        ]
    }
    
    /// Merchant service items (placeholder for future expansion)
    private var merchantServiceItems: [ServiceItem] {
        []
    }
    
    /// Healthcare service items (placeholder for future expansion)
    private var healthcareServiceItems: [ServiceItem] {
        []
    }
    
    /// Government service items (placeholder for future expansion)
    private var governmentServiceItems: [ServiceItem] {
        []
    }
    
    /// Transportation service items (placeholder for future expansion)
    private var transportationServiceItems: [ServiceItem] {
        []
    }
    
    /// Utilities service items (placeholder for future expansion)
    private var utilitiesServiceItems: [ServiceItem] {
        []
    }
    
    /// Education service items (placeholder for future expansion)
    private var educationServiceItems: [ServiceItem] {
        []
    }
    
    private init() {}
}

