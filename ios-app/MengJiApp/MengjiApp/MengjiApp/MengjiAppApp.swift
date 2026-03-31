//
//  MengjiAppApp.swift
//  MengjiApp
//
//  Created by VeriTrust on 16/3/2026.
//

import SwiftUI
import UIKit

@main
struct MengjiAppApp: App {
    @State private var showSettings = false

    init() {
        // ScrollView 滑动结束后立刻分发触摸，不等待滚动意图判断，
        // 避免与画布 DragGesture / 节点 TapGesture 产生 "gesture gate timed out"。
        UIScrollView.appearance().delaysContentTouches = false
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.openPersonalCenter) {
                    Task { @MainActor in
                        if PersonalCenterBiometric.isEnabled {
                            guard PersonalCenterBiometric.canEvaluateBiometrics() else {
                                showSettings = true
                                return
                            }
                            let ok = await PersonalCenterBiometric.authenticateForEntry()
                            if ok {
                                showSettings = true
                            }
                        } else {
                            showSettings = true
                        }
                    }
                }
            .onAppear {
                // 仅在首次启动/空库时注入示例梦境，方便星图验证布局与交互。
                DreamStore.shared.seedDemoDreamsIfNeeded()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}
