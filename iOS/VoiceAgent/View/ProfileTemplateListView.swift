//
//  ProfileTemplateListView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI
import Combine

/// View for displaying and managing profile templates
struct ProfileTemplateListView: View {
    @StateObject private var viewModel = ProfileTemplateListViewModel()
    @State private var showAddTemplate = false
    @State private var editingTemplate: ProfileTemplate?
    
    var body: some View {
        List {
            if viewModel.templates.isEmpty {
                emptyStateView
            } else {
                ForEach(viewModel.templates) { template in
                    TemplateRow(template: template) {
                        editingTemplate = template
                    }
                }
                .onDelete(perform: deleteTemplates)
            }
        }
        .navigationTitle("Profile Templates")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showAddTemplate = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                }
            }
        }
        .sheet(isPresented: $showAddTemplate) {
            AddProfileTemplateView { template in
                viewModel.addTemplate(template)
            }
        }
        .sheet(item: $editingTemplate) { template in
            EditProfileTemplateView(template: template) { updatedTemplate in
                viewModel.updateTemplate(updatedTemplate)
            }
        }
        .onAppear {
            viewModel.loadTemplates()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Templates")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Tap + to create your first profile template")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private func deleteTemplates(at offsets: IndexSet) {
        for index in offsets {
            viewModel.deleteTemplate(viewModel.templates[index])
        }
    }
}

/// Template row component
struct TemplateRow: View {
    let template: ProfileTemplate
    let onEdit: () -> Void
    
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
            
            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
    }
}

/// ViewModel for profile template list
@MainActor
class ProfileTemplateListViewModel: ObservableObject {
    @Published var templates: [ProfileTemplate] = []
    
    func loadTemplates() {
        templates = ProfileTemplateService.loadTemplates()
    }
    
    func addTemplate(_ template: ProfileTemplate) {
        ProfileTemplateService.addTemplate(template)
        loadTemplates()
    }
    
    func updateTemplate(_ template: ProfileTemplate) {
        ProfileTemplateService.updateTemplate(template)
        loadTemplates()
    }
    
    func deleteTemplate(_ template: ProfileTemplate) {
        ProfileTemplateService.deleteTemplate(template)
        loadTemplates()
    }
}

#Preview {
    NavigationView {
        ProfileTemplateListView()
    }
}

