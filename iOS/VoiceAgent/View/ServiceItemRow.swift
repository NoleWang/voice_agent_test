//
//  ServiceItemRow.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI

/// Service item row component
struct ServiceItemRow: View {
    let item: ServiceItem
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: item.icon)
                .font(.system(size: 24))
                .foregroundColor(item.iconColor)
                .frame(width: 44, height: 44)
                .background(item.iconColor.opacity(0.1))
                .cornerRadius(10)
            
            // Title and description
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if item.isOptional {
                        Text("(Optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Arrow
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }
}

#Preview {
    ServiceItemRow(item: ServiceItem(
        title: "Credit Card Issues",
        icon: "creditcard.fill",
        iconColor: .blue,
        description: "Credit card problems and inquiries"
    ))
}




