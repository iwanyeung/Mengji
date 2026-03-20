import SwiftUI

struct RecordingView: View {
    var onFinishRecording: ((UUID) -> Void)? = nil
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

            // 右下录音主按钮
            recordButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 24)
                .padding(.bottom, 80)

            // 左下「完成并整理」按钮
            finishButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 24)
                .padding(.bottom, 24)
        }
        .onAppear {
            viewModel.onFinishRecording = onFinishRecording
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
        List {
            // 当前录制中的实时转写
            if viewModel.isRecording && !viewModel.liveTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前录制中…")
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundColor(AppTheme.muted)
                    Text(viewModel.liveTranscript)
                        .foregroundColor(AppTheme.text.opacity(0.9))
                        .font(.system(size: 16, weight: .regular, design: .default))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // 左滑删除提示
            if !viewModel.segments.isEmpty {
                Text("向左滑动梦境片段即可删除")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundColor(AppTheme.muted.opacity(0.7))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // 片段列表
            ForEach(Array(viewModel.segments.enumerated()), id: \.element.id) { index, segment in
                HStack {
                    VStack(alignment: .leading, spacing: 10) {
                        // 第 1 行：日期 + 梦段编号
                        Text(title(for: segment, at: index))
                            .foregroundColor(AppTheme.text.opacity(0.9))
                            .font(.system(size: 14, weight: .semibold, design: .default))

                        // 第 2 行：转写摘要
                        Text(preview(for: segment))
                            .foregroundColor(AppTheme.text.opacity(0.9))
                            .font(.system(size: 16, weight: .regular, design: .default))

                        // 第 3 行：小黄线 + 时间 · 时长
                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(AppTheme.primaryColor)
                                .frame(width: 16, height: 1)

                            Text("\(timeLabel(for: segment)) · 时长 \(segment.durationText)")
                                .font(.system(size: 11, weight: .semibold, design: .default))
                                .textCase(.uppercase)
                                .kerning(1.2)
                                .foregroundColor(AppTheme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.6, alignment: .leading)
                    .opacity(opacityForIndex(index))

                    Spacer(minLength: 0)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteSegment(id: segment.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }

            // 底部占位行，避免被录音按钮遮挡
            if !viewModel.segments.isEmpty {
                Color.clear
                    .frame(height: 120)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .padding(.top, 40)
        .padding(.bottom, 40)
    }

    private var recordButton: some View {
        VStack(spacing: 8) {
            Text(viewModel.buttonHint)
                .font(.system(size: 10, weight: .bold, design: .default))
                .textCase(.uppercase)
                .kerning(2)
                .foregroundColor(viewModel.isRecording ? AppTheme.accent : AppTheme.primaryColor)

            if viewModel.isRecording && !viewModel.isLocked {
                Text("上滑锁定")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .textCase(.uppercase)
                    .kerning(1.5)
                    .foregroundColor(AppTheme.muted)
            }

            // 简单声波动效
            if viewModel.isRecording {
                HStack(spacing: 4) {
                    ForEach(0..<6) { index in
                        Capsule()
                            .fill(AppTheme.primaryColor)
                            .frame(width: 3, height: waveHeight(index: index))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.formattedCurrentDuration)
            }

            ZStack {
                Circle()
                    .fill(viewModel.isRecording ? AppTheme.accent : AppTheme.primaryColor)
                    .frame(width: 120, height: 120)
                    .shadow(
                        color: (viewModel.isRecording ? AppTheme.accent : AppTheme.primaryColor)
                            .opacity(viewModel.isRecording ? 0.9 : 0.6),
                        radius: viewModel.isRecording ? 32 : 24
                    )
                    .scaleEffect(viewModel.isRecording ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)

                Image(systemName: "mic.fill")
                    .font(.system(size: 40))
                    .foregroundColor(AppTheme.background)
            }
            .padding(.bottom, 40)
        }
        // 固定自身宽度，避免因文字长度不同导致整体水平位置变化
        .frame(width: 180)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    if value.translation.height < -40 && viewModel.isRecording && !viewModel.isLocked {
                        viewModel.lockRecording()
                    }
                }
        )
        .onLongPressGesture(
            minimumDuration: 0.2,
            pressing: { isPressing in
                if isPressing {
                    viewModel.beginRecording()
                } else {
                    if !viewModel.isLocked {
                        viewModel.endRecording()
                    }
                }
            },
            perform: { }
        )
        .onTapGesture {
            if viewModel.isLocked {
                viewModel.endRecording()
            }
        }
    }

    private var finishButton: some View {
        Group {
            if !viewModel.segments.isEmpty && !viewModel.isRecording {
                Button {
                    viewModel.finishAllSegments()
                } label: {
                    Text("完成并整理")
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .textCase(.uppercase)
                        .kerning(1.5)
                        .foregroundColor(AppTheme.background)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(AppTheme.primaryColor)
                }
            }
        }
    }

    private func waveHeight(index: Int) -> CGFloat {
        // 根据当前录制时长简单波动，营造声波感
        let base: CGFloat = 10 + CGFloat(index) * 2
        let t = CGFloat(sin((viewModel.currentDuration * 2) + Double(index)))
        return base + t * 6
    }

    private func title(for segment: RecordingViewModel.Segment, at index: Int) -> String {
        let calendar = Calendar.current
        let daySegments = viewModel.segments.enumerated().filter {
            calendar.isDate($0.element.occurredAt, inSameDayAs: segment.occurredAt)
        }
        // 以时间顺序给当天片段编号，从 1 开始
        let sorted = daySegments.sorted { $0.element.occurredAt < $1.element.occurredAt }
        let position = (sorted.firstIndex { $0.offset == index } ?? 0) + 1

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "MMM dd"
        let dayString = dayFormatter.string(from: segment.occurredAt).uppercased()

        return "\(dayString) · 梦段 \(String(format: "%02d", position))"
    }

    private func preview(for segment: RecordingViewModel.Segment) -> String {
        let text = segment.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "（这一段主要是沉默或环境声）" }
        let limit = 16
        if text.count <= limit { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index]) + "…"
    }

    private func timeLabel(for segment: RecordingViewModel.Segment) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: segment.occurredAt)
    }

    private func opacityForIndex(_ index: Int) -> Double {
        // 最近的片段最清晰，往下逐渐淡出
        switch index {
        case 0: return 1.0
        case 1: return 0.9
        case 2: return 0.8
        case 3: return 0.7
        default: return 0.6
        }
    }
}

struct RecordingView_Previews: PreviewProvider {
    static var previews: some View {
        RecordingView()
    }
}

