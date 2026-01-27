//
//  TaskListView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI
import UIKit

/// View for displaying active tasks in a pull-down sheet
struct TaskListView: View {
    @Binding var isPresented: Bool
    @State private var tasks: [TaskItem] = []
    @State private var showDeleteAlert = false
    @State private var taskToDelete: TaskItem?
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary)
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 12)
            
            // Header
            HStack {
                Text("Active Tasks")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // Task list
            if tasks.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Group tasks by category
                        let groupedTasks = Dictionary(grouping: tasks) { $0.categoryName }
                        let sortedCategories = groupedTasks.keys.sorted()
                        
                        ForEach(sortedCategories, id: \.self) { categoryName in
                            categorySection(categoryName: categoryName, tasks: groupedTasks[categoryName] ?? [])
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -5)
        .onAppear {
            loadTasks()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TaskListNeedsUpdate"))) { _ in
            loadTasks()
        }
        .alert("Delete Task", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let task = taskToDelete {
                    deleteTask(task)
                }
            }
        } message: {
            if let task = taskToDelete {
                Text("Are you sure you want to delete this task?\n\n\(task.serviceItemTitle) - \(task.merchant)")
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("No Active Tasks")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("All tasks have been completed")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
    
    private func categorySection(categoryName: String, tasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header
            HStack {
                Text(categoryName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(tasks.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Tasks in this category
            ForEach(tasks) { task in
                taskRow(task: task)
            }
        }
        .padding(.bottom, 8)
    }
    
    private func taskRow(task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Service item title (small category)
                Text(task.serviceItemTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                
                // Cancel button
                Button(action: {
                    taskToDelete = task
                    showDeleteAlert = true
                }) {
                    Text("Cancel")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(8)
                }
            }
            
            // Merchant and amount
            HStack {
                Text(task.merchant)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(formatCurrency(task.amount, currency: task.currency))")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            // Date
            Text(formatDate(task.createdAt))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
    
    private func loadTasks() {
        tasks = DisputeCaseService.loadAllTasks()
    }
    
    private func deleteTask(_ task: TaskItem) {
        do {
            try DisputeCaseService.deleteTask(fileURL: task.fileURL)
            loadTasks()
            // Notify other views to update
            NotificationCenter.default.post(name: NSNotification.Name("TaskListNeedsUpdate"), object: nil)
        } catch {
            print("❌ Error deleting task: \(error.localizedDescription)")
        }
    }
    
    private func formatCurrency(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.2f", amount))"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Extension for rounded corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    TaskListView(isPresented: .constant(true))
}

