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
                Text("显化工坊")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(AppTheme.text)
                Text("从梦析中选择一条梦，生成四格漫画")
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundColor(AppTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle("显化工坊")
    }
}
