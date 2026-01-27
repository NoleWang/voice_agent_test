//
//  MenuView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI

struct MenuView: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var userInfo: UserInfo?
    @State private var showLogoutAlert = false
    @State private var showServiceCategoryPicker = false
    @State private var selectedCategory: ServiceCategory?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 用户信息区域
                    userInfoSection
                    
                    // 功能菜单区域
                    menuSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showLogoutAlert = true
                    }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
            }
            .alert("Logout", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    viewModel.handleLogout()
                }
            } message: {
                Text("Are you sure you want to logout?")
            }
            .onAppear {
                loadUserInfo()
            }
        }
    }
    
    // 用户信息区域
    private var userInfoSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            if let userInfo = userInfo {
                Text(userInfo.fullName)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("@\(userInfo.username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Loading...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
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
    
    // 功能菜单区域 - 设计为方便扩展的结构
    private var menuSection: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Features", icon: "square.grid.2x2.fill")
            
            // 使用 MenuItem 组件，方便扩展
            // 服务板块选择
            Button(action: {
                showServiceCategoryPicker = true
            }) {
                HStack(spacing: 16) {
                    // 图标
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                        .frame(width: 40, height: 40)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    
                    // 标题
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Service Categories")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        if let category = selectedCategory {
                            Text(category.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Select a service category")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // 箭头
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
            .buttonStyle(PlainButtonStyle())
            
            // Profile Templates
            MenuItem(
                title: "Profile Templates",
                icon: "doc.text.fill",
                iconColor: .purple,
                destination: AnyView(ProfileTemplateListView())
            )
            
            // Task Management
            MenuItem(
                title: "My Tasks",
                icon: "list.bullet.clipboard.fill",
                iconColor: .orange,
                destination: AnyView(TaskManagementView())
            )
            
            // 拨打电话功能
            MenuItem(
                title: "Make Phone Call",
                icon: "phone.fill",
                iconColor: .green,
                destination: AnyView(PhoneCallView())
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
        .sheet(isPresented: $showServiceCategoryPicker) {
            ServiceCategoryView { category in
                selectedCategory = category
            }
        }
        .sheet(item: $selectedCategory) { category in
            ServiceDetailView(category: category)
        }
    }
    
    // 加载用户信息
    private func loadUserInfo() {
        do {
            userInfo = try KeychainService.loadUserInfo()
        } catch {
            print("Failed to load user info: \(error.localizedDescription)")
        }
    }
}

// 菜单项组件 - 可复用的菜单项设计，方便扩展
struct MenuItem: View {
    let title: String
    let icon: String
    let iconColor: Color
    let destination: AnyView
    
    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 16) {
                // 图标
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)
                    .frame(width: 40, height: 40)
                    .background(iconColor.opacity(0.1))
                    .cornerRadius(10)
                
                // 标题
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // 箭头
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
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    MenuView(viewModel: ContentViewModel())
}

