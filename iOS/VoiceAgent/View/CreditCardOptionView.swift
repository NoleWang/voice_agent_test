//
//  CreditCardOptionView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI

/// View for selecting credit card related options
struct CreditCardOptionView: View {
    let serviceItem: ServiceItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header section
                headerSection
                
                // Options section
                optionsSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(serviceItem.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") {
                    dismiss()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DismissToBankPage"))) { _ in
            // Dismiss this view when notification is received
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                dismiss()
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: serviceItem.icon)
                .font(.system(size: 60))
                .foregroundColor(serviceItem.iconColor)
                .frame(width: 100, height: 100)
                .background(serviceItem.iconColor.opacity(0.1))
                .cornerRadius(20)
            
            Text("What would you like to do?")
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
    
    private var optionsSection: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Select an Option", icon: "list.bullet")
            
            // Monthly fee option
            NavigationLink(destination: PhoneCallView()) {
                optionRow(
                    title: "Monthly Fee Related",
                    subtitle: "Questions or issues about monthly fees",
                    icon: "calendar",
                    iconColor: .blue
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Dispute transaction option
            NavigationLink(destination: DisputeTransactionFormView(serviceItem: serviceItem)) {
                optionRow(
                    title: "Dispute Transaction",
                    subtitle: "Report and dispute unauthorized or incorrect transactions",
                    icon: "exclamationmark.shield.fill",
                    iconColor: .orange
                )
            }
            .buttonStyle(PlainButtonStyle())
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
    
    private func optionRow(title: String, subtitle: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(iconColor)
                .frame(width: 50, height: 50)
                .background(iconColor.opacity(0.1))
                .cornerRadius(12)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
}

#Preview {
    NavigationView {
        CreditCardOptionView(serviceItem: ServiceItem(
            title: "Credit Card Issues",
            icon: "creditcard.fill",
            iconColor: .blue,
            description: "Credit card problems and inquiries"
        ))
    }
}

