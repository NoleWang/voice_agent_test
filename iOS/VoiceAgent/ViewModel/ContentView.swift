//
//  ContentView.swift
//  VoiceAgent
//
//  Created by Alex Liuyz on 11/20/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var showTaskList = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Main content with pull-down gesture
                viewModel.getCurrentView()
                    .gesture(
                        DragGesture(minimumDistance: 30)
                            .onEnded { value in
                                // Detect downward swipe from top area
                                if value.startLocation.y < 150 && value.translation.height > 100 {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        showTaskList = true
                                    }
                                }
                            }
                    )
                
                // Task list overlay
                if showTaskList {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showTaskList = false
                            }
                        }
                    
                    VStack {
                        Spacer()
                        TaskListView(isPresented: $showTaskList)
                            .frame(height: min(700, geometry.size.height * 0.85))
                            .transition(.move(edge: .bottom))
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
