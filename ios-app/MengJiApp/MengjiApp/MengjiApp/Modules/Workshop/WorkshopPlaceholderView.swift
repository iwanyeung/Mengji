//
//  WorkshopPlaceholderView.swift
//  MengjiApp
//

import SwiftUI

struct WorkshopPlaceholderView: View {
    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.system(size: 48))
                    .foregroundColor(AppTheme.muted)
                Text("梦作间")
                    .font(AppTheme.titleFont(size: 22))
                    .kerning(-0.4)
                    .foregroundColor(AppTheme.text)
                Text("从梦析中选一条梦，让它落成四格故事")
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundColor(AppTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle("梦作间")
    }
}
