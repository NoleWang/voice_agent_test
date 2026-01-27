//
//  ContentViewModel.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ContentViewModel: ObservableObject {
    @Published var isLoggedIn = false
    
    init() {
        checkLoginStatus()
    }
    
    // 检查登录状态
    func checkLoginStatus() {
        // 可以根据需要添加自动登录逻辑
        // 目前设置为需要用户手动登录
        isLoggedIn = false
    }
    
    // 处理登录成功
    func handleLoginSuccess() {
        isLoggedIn = true
    }
    
    // 处理退出登录
    func handleLogout() {
        isLoggedIn = false
    }
    
    // 获取当前显示的视图
    func getCurrentView() -> AnyView {
        if isLoggedIn {
            return AnyView(MenuView(viewModel: self))
        } else {
            return AnyView(AuthView(viewModel: self))
        }
    }
}

