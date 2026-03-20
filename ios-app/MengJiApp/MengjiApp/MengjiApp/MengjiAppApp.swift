//
//  MengjiAppApp.swift
//  MengjiApp
//
//  Created by VeriTrust on 16/3/2026.
//

import SwiftUI

@main
struct MengjiAppApp: App {
    @State private var showSettings = false

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .topTrailing) {
                MainTabView()

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .foregroundColor(AppTheme.muted)
                        .padding(.top, 20)
                        .padding(.trailing, 20)
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}
