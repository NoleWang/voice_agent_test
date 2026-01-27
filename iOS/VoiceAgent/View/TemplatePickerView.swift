//
//  TemplatePickerView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI
import Combine

/// View for selecting a profile template
struct TemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TemplatePickerViewModel()
    let onTemplateSelected: (ProfileTemplate) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                if viewModel.templates.isEmpty {
                    emptyStateView
                } else {
                    ForEach(viewModel.templates) { template in
                        TemplatePickerRow(template: template) {
                            // Fill form with template data first
                            onTemplateSelected(template)
                            // Then close the picker sheet with a delay to ensure data is loaded and displayed
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadTemplates()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No Templates")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Create templates in Profile Templates section")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Template picker row component
struct TemplatePickerRow: View {
    let template: ProfileTemplate
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(template.fullName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(template.email)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

/// ViewModel for template picker
@MainActor
class TemplatePickerViewModel: ObservableObject {
    @Published var templates: [ProfileTemplate] = []
    
    func loadTemplates() {
        templates = ProfileTemplateService.loadTemplates()
    }
}

#Preview {
    TemplatePickerView { _ in }
}

