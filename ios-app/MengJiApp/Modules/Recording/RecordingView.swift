import SwiftUI

struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            VStack {
                header

                fragmentsList
                    .padding(.horizontal, 24)

                Spacer()
            }

            recordButton
        }
    }

    private var header: some View {
        HStack {
            Text("告诉我")
                .font(.system(size: 40, weight: .bold, design: .serif))
                .kerning(-2)
                .foregroundColor(AppTheme.text)
                .padding(.top, 32)
            Spacer()
        }
    }

    private var fragmentsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(viewModel.segments) { segment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(segment.preview)
                            .foregroundColor(AppTheme.text.opacity(0.9))
                            .font(.system(size: 16, weight: .regular, design: .default))

                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(AppTheme.primaryColor)
                                .frame(width: 16, height: 1)
                            Text(segment.meta)
                                .font(.system(size: 11, weight: .semibold, design: .default))
                                .textCase(.uppercase)
                                .kerning(1.2)
                                .foregroundColor(AppTheme.muted)
                        }
                    }
                }
            }
            .padding(.top, 80)
            .padding(.bottom, 160)
        }
    }

    private var recordButton: some View {
        VStack(spacing: 8) {
            Text(viewModel.buttonHint)
                .font(.system(size: 10, weight: .bold, design: .default))
                .textCase(.uppercase)
                .kerning(2)
                .foregroundColor(AppTheme.primaryColor)

            ZStack {
                Circle()
                    .fill(AppTheme.primaryColor)
                    .frame(width: 120, height: 120)
                    .shadow(color: AppTheme.primaryColor.opacity(0.6), radius: 24)

                Image(systemName: "mic.fill")
                    .font(.system(size: 40))
                    .foregroundColor(AppTheme.background)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 24)
        .padding(.bottom, 80)
    }
}

struct RecordingView_Previews: PreviewProvider {
    static var previews: some View {
        RecordingView()
    }
}

