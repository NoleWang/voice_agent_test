//
//  LiveKitStartView.swift
//  VoiceAgent
//
//  Created by WangSimin on 12/25/25.
//

import SwiftUI

struct LiveKitStartView: View {
    @StateObject private var manager = LiveKitManager()

    @State private var token: String?
    @State private var roomUrl: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let token = token, let roomUrl = roomUrl {
                // 已拿到 token + url，显示真正的房间界面
                LiveKitRoomView(
                    manager: manager,
                    roomUrl: roomUrl,
                    token: token
                )
            } else {
                // 创建房间 / 获取 token 的加载界面
                VStack(spacing: 16) {
                    if isLoading {
                        ProgressView("正在创建客服房间…")
                    } else {
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            createRoom()
                        } label: {
                            HStack {
                                Image(systemName: "phone.and.waveform.fill")
                                Text("开始智能语音客服")
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .navigationTitle("智能语音客服")
            }
        }
        .onAppear {
            // 如果希望一进来就自动创建房间，可以在这里调用
            if token == nil && !isLoading {
                createRoom()
            }
        }
    }

    private func createRoom() {
        isLoading = true
        errorMessage = nil

        // TODO: 这里应该真正调用你的 Python/后端接口，
        //       创建 LiveKit 房间并返回 token + url。
        //       下面是一个示例结构，你可以替换成实际的网络请求。

        // 示例：假装从服务器返回
        // ***** 替换成你自己的 LiveKit 服务器地址和测试 token *****
        let demoUrl = "wss://your-livekit-server.example.com"
        let demoToken = "REPLACE_WITH_REAL_JWT"

        // 模拟网络延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isLoading = false
            // 正常情况下需要检查请求是否成功
            self.roomUrl = demoUrl
            self.token = demoToken
        }
    }
}
