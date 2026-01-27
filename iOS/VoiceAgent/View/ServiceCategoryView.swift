//
//  ServiceCategoryView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI

/// View for displaying and selecting service categories
struct ServiceCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    let onCategorySelected: (ServiceCategory) -> Void
    
    private let categoryManager = ServiceCategoryManager.shared
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(categoryManager.sectionHeaders, id: \.self) { header in
                    Section(header: Text(header)) {
                        ForEach(categoryManager.groupedCategories[header] ?? []) { category in
                            CategoryRow(category: category) {
                                onCategorySelected(category)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Select Service Category")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Category row component with icon
struct CategoryRow: View {
    let category: ServiceCategory
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: category.icon)
                    .font(.system(size: 24))
                    .foregroundColor(category.iconColor)
                    .frame(width: 40, height: 40)
                    .background(category.iconColor.opacity(0.1))
                    .cornerRadius(10)
                
                // Name and description
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if !category.description.isEmpty {
                        Text(category.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ServiceCategoryView { _ in }
}

