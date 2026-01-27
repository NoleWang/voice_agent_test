//
//  ServiceDetailView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI

/// View for displaying service category details and actions
struct ServiceDetailView: View {
    let category: ServiceCategory
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header section
                    headerSection
                    
                    // Description section
                    if !category.description.isEmpty {
                        descriptionSection
                    }
                    
                    // Actions section
                    Group {
                        if !ServiceItemManager.shared.getServiceItems(for: category.name).isEmpty {
                            serviceItemsSection
                        } else {
                            defaultActionsSection
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DismissToServiceCategory"))) { _ in
                // Dismiss this view when notification is received
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dismiss()
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: category.icon)
                .font(.system(size: 80))
                .foregroundColor(category.iconColor)
                .frame(width: 120, height: 120)
                .background(category.iconColor.opacity(0.1))
                .cornerRadius(20)
            
            Text(category.name)
                .font(.title)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "About", icon: "info.circle.fill")
            
            Text(category.description)
                .font(.body)
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                )
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
    
    private var serviceItemsSection: some View {
        let serviceItems = ServiceItemManager.shared.getServiceItems(for: category.name)
        
        return VStack(spacing: 16) {
            SectionHeader(title: "Services", icon: "list.bullet")
            
            ForEach(serviceItems) { item in
                NavigationLink(destination: destinationView(for: item)) {
                    ServiceItemRow(item: item)
                }
                .buttonStyle(PlainButtonStyle())
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
    
    private var defaultActionsSection: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Actions", icon: "bolt.fill")
            
            // Make phone call button
            NavigationLink(destination: PhoneCallView()) {
                HStack {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 18))
                    Text("Make Phone Call")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .foregroundColor(.green)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Placeholder for future actions
            Text("More features coming soon...")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
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
    
    /// Get destination view for service item
    @ViewBuilder
    private func destinationView(for item: ServiceItem) -> some View {
        // All Bank services require profile form
        if category.name == "Bank" {
            UserProfileFormView(serviceItem: item)
        } else {
            PhoneCallView()
        }
    }
}

#Preview {
    ServiceDetailView(category: ServiceCategoryManager.shared.categories[0])
}

