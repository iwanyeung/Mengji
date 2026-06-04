//
//  StarMapPlaceholderView.swift
//  MengjiApp
//

import SwiftUI
import Foundation

struct StarMapView: View {
    @EnvironmentObject private var store: DreamStore
    @StateObject private var viewModel = StarMapViewModel()

    /// 由 `MainTabView` 传入：仅在「潜意识星图」Tab 选中时为 `true`，用于暂停 MTKView 降低发热。
    var isTabActive: Bool = true

    /// 用于点击节点后打开“梦析页”（由外部注入；星图本身也可先不跳转）
    var onSelectDream: (UUID) -> Void = { _ in }
    /// 用于点击节点后直接回看四格（当该梦已落成）
    var onViewComic: (UUID) -> Void = { _ in }

    @AppStorage(StarfieldSettings.appStorageKey) private var storedStarfieldModeRaw = StarfieldBackgroundMode.full.rawValue
    @State private var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var starfieldRampUp = true

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    @State private var selectedDream: Dream?
    @State private var preFocusOffset: CGSize?
    @State private var preFocusScale: CGFloat?
    /// 节点点击节流：150ms 内只处理一次，防止快速连击堆叠 spring 动画
    @State private var isFocusTapThrottled = false
    /// 画布实际尺寸（由 starCanvas GeometryReader 捕获），避免 dreamDetailOverlay 自带 GeometryReader
    @State private var canvasSize: CGSize = .zero
    /// 粒子层种子：仅在首次选中时赋值，切换节点时保持稳定，避免粒子层重算/重启动画
    @State private var particleSeed: UUID = UUID()

    @FocusState private var searchFocused: Bool
    @Environment(\.openPersonalCenter) private var openPersonalCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 星图能量涟漪：点击节点时更新中心；持续动画由 TimelineView 驱动
    @State private var rippleOrigin: CGPoint = .zero

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN_POSIX")
        formatter.dateFormat = "MM.dd"
        return formatter
    }()

    private var storedStarfieldMode: StarfieldBackgroundMode {
        StarfieldBackgroundMode(rawValue: storedStarfieldModeRaw) ?? .full
    }

    private var effectiveStarfieldMode: StarfieldBackgroundMode {
        StarfieldSettings.effectiveMode(stored: storedStarfieldMode, isLowPower: isLowPowerMode)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 1. 背景层：动态星野（Metal / 静态）+ 轻量微光压暗边缘
                ZStack {
                    starfieldBackgroundLayer

                    // 选中梦境时略压暗星野，让霓虹关联线更易读（与略降星点密度同档组合拳）
                    if selectedDream != nil {
                        Color.black.opacity(0.24)
                            .allowsHitTesting(false)
                    }

                    RadialGradient(
                        gradient: Gradient(colors: [AppTheme.surface.opacity(0.22), AppTheme.background.opacity(0.0)]),
                        center: .center,
                        startRadius: 80,
                        endRadius: 520
                    )
                }
                .ignoresSafeArea()

                // 2. 画布层
                starCanvas

                // 3. UI 交互层
                VStack(spacing: 0) {
                    // 右下角重置罗盘
                    HStack {
                        Spacer()
                        resetCompassButton
                            .padding(.trailing, 20)
                            .padding(.bottom, 10)
                    }
                    
                    bottomControls
                        .padding(.bottom, 2)
                }

                // 节点详情：不使用 .id() 强制重建（代价太高），让 SwiftUI diff 更新内容即可
                if let dream = selectedDream {
                    dreamDetailOverlay(dream: dream, canvasSize: canvasSize)
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileNavButton(style: .compact) {
                        openPersonalCenter()
                    }
                }
            }
            .navigationTitle("潜意识星图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
        }
        .onAppear {
            startStarfieldRampIfNeeded()
        }
        .onChange(of: isTabActive) { _, active in
            if active { startStarfieldRampIfNeeded() }
        }
        .onChange(of: storedStarfieldModeRaw) { _, _ in
            startStarfieldRampIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    /// 当前生效的 Metal 配置：节点面板展开时降至 12fps 以减少 GPU 热量
    private var activeMetalConfig: StarfieldMetalConfig? {
        guard var cfg = StarfieldMetalConfig.forMode(effectiveStarfieldMode) else { return nil }
        if selectedDream != nil { cfg.preferredFPS = 12 }
        return cfg
    }

    @ViewBuilder
    private var starfieldBackgroundLayer: some View {
        switch effectiveStarfieldMode {
        case .off:
            StaticStarfieldBackgroundView()
        case .full, .powerSaving:
            if starfieldRampUp {
                StaticStarfieldBackgroundView()
            } else if let cfg = activeMetalConfig {
                StarFieldMetalBackgroundView(config: cfg, isPaused: !isTabActive)
            }
        }
    }

    private func startStarfieldRampIfNeeded() {
        guard effectiveStarfieldMode != .off else {
            starfieldRampUp = false
            return
        }
        starfieldRampUp = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            starfieldRampUp = false
        }
    }

    /// 底部浮窗：canvasSize 由外部传入，避免此处 GeometryReader 在每次节点切换时触发额外布局轮
    private func dreamDetailOverlay(dream: Dream, canvasSize: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            // 全屏透传层：Sheet 面板以上的星图区域不拦截触摸，让节点 tap 能直接到达画布
            Color.clear
                .allowsHitTesting(false)

            // 粒子层：seed 固定（首次选中时赋值），切换节点时不重算，避免 TimelineView 重启
            StarDustParticlesLayer(
                seed: particleSeed,
                rippleOrigin: rippleOrigin,
                canvasSize: canvasSize
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // 弹窗内容容器：放在底部
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        dreamDetailSheet(dream: dream)
                    }
                }
                .frame(maxWidth: canvasSize.width * 0.94)
                .background(
                    // 玻璃感背景
                    AppTheme.surface.opacity(0.25)
                        .background(.ultraThinMaterial)
                )
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.muted.opacity(0.35), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .shadow(color: .black.opacity(0.3), radius: 25, x: 0, y: -5)
                .frame(maxHeight: canvasSize.height * 0.60)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// 少量“星尘粒子”层：放在遮罩层上方，但不吃触摸。
    private struct StarDustParticlesLayer: View {
        let seed: UUID
        let rippleOrigin: CGPoint
        let canvasSize: CGSize

        private let count: Int = 16

        private struct Spec {
            let cosA: CGFloat
            let sinA: CGFloat
            let radius: CGFloat
            let amp: Double
            let kx: Double
            let px: Double
            let ky: Double
            let py: Double
            let size: CGFloat
            let opacityMul: Double
        }

        var body: some View {
            let minDim = min(canvasSize.width, canvasSize.height)
            let specs: [Spec] = (0..<count).map { i in
                let s1 = Self.stableUnit(seed: seed, salt: UInt64(i) * 3 + 1)
                let s2 = Self.stableUnit(seed: seed, salt: UInt64(i) * 3 + 2)
                let s3 = Self.stableUnit(seed: seed, salt: UInt64(i) * 3 + 3)

                let s1d = Double(s1)
                let s2d = Double(s2)
                let s3d = Double(s3)

                let angle = 2 * Double.pi * s1d
                let cosA = CGFloat(cos(angle))
                let sinA = CGFloat(sin(angle))
                let radius = (minDim * 0.22) * CGFloat(0.35 + 0.65 * s2d)

                let amp = 2 + 6 * s3d
                let kx = 0.6 + 1.1 * s2d
                let px = s1d * 6.28
                let ky = 0.5 + 1.0 * s3d
                let py = s2d * 6.28

                let size = CGFloat(2 + 2 * s2d)
                let opacityMul = 0.9 + s1d

                return Spec(
                    cosA: cosA,
                    sinA: sinA,
                    radius: radius,
                    amp: amp,
                    kx: kx,
                    px: px,
                    ky: ky,
                    py: py,
                    size: size,
                    opacityMul: opacityMul
                )
            }

            // Canvas 单遍绘制所有粒子，addFilter(.blur) 仅产生 1 次 GPU offscreen（原 16 次）
            return TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { ctx, _ in
                    ctx.addFilter(.blur(radius: 1.5))
                    for i in 0..<count {
                        let spec = specs[i]
                        let baseX = rippleOrigin.x + spec.cosA * spec.radius
                        let baseY = rippleOrigin.y + spec.sinA * spec.radius
                        let dx = cos(t * spec.kx + spec.px) * spec.amp
                        let dy = sin(t * spec.ky + spec.py) * spec.amp
                        let x = min(max(baseX + CGFloat(dx), 0), canvasSize.width)
                        let y = min(max(baseY + CGFloat(dy), 0), canvasSize.height)
                        let opacityD = 0.10 + 0.22 * (0.5 + 0.5 * sin(t * spec.opacityMul + Double(i)))
                        ctx.fill(
                            Path(ellipseIn: CGRect(
                                x: x - spec.size / 2,
                                y: y - spec.size / 2,
                                width: spec.size,
                                height: spec.size
                            )),
                            with: .color(AppTheme.primaryColor.opacity(CGFloat(opacityD)))
                        )
                    }
                }
            }
            .allowsHitTesting(false)
        }

        private static func stableUnit(seed: UUID, salt: UInt64) -> CGFloat {
            let input = "\(seed.uuidString)-\(salt)"
            let bytes = Array(input.utf8)

            var hash: UInt64 = 14695981039346656037
            for b in bytes {
                hash ^= UInt64(b)
                hash &*= 1099511628211
            }

            let v = Double(hash % 10001) / 10000.0 // [0,1]
            return CGFloat(v)
        }
    }

    // 稳定伪随机：用于粒子/涟漪的细节抖动
    private func stableParticleUnit(seed: UUID, salt: UInt64) -> CGFloat {
        let input = "\(seed.uuidString)-\(salt)"
        let bytes = Array(input.utf8)

        // FNV-1a 64-bit
        var hash: UInt64 = 14695981039346656037
        for b in bytes {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }

        let v = Double(hash % 10001) / 10000.0 // [0,1]
        return CGFloat(v)
    }

    private var resetCompassButton: some View {
        Button(action: resetView) {
            ZStack {
                Circle()
                    .fill(AppTheme.surface.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(AppTheme.muted.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 10)
                
                Image(systemName: "safari.fill") // 罗盘图标
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(scale == 1.0 && offset == .zero ? AppTheme.muted : AppTheme.primaryColor)
                    .rotationEffect(.degrees(Double(-offset.width / 10))) // 随平移轻微摆动，增加动态感
            }
        }
        .buttonStyle(.plain)
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            searchBar
            filterRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            AppTheme.background.opacity(0.42)
                .background(.ultraThinMaterial)
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.muted)

            TextField("搜索梦境…", text: $viewModel.searchText)
                .foregroundColor(AppTheme.text)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                .onSubmit {
                    searchFocused = false
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(AppTheme.surface.opacity(0.58))
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(AppTheme.muted.opacity(0.45), lineWidth: 1)
        )
    }

    private var filterRow: some View {
        Toggle(isOn: $viewModel.onlyHasComic) {
            Text("仅已落成")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundColor(AppTheme.muted)
        }
        .tint(AppTheme.primaryColor)
        .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundColor(AppTheme.muted)
            Text("没有符合条件的梦境")
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundColor(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let target = lastScale * value
                scale = clampScale(target)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.35), 3.0)
    }

    private func resetView() {
        offset = .zero
        lastOffset = .zero
        scale = 1
        lastScale = 1
    }

    private var starCanvas: some View {
        GeometryReader { geometry in
            let canvasSize = geometry.size
            let filtered = viewModel.filteredDreams(store.visibleDreams())
            let nodes = viewModel.cachedLayoutNodes(dreams: filtered, in: canvasSize)
            let edges = viewModel.cachedLayoutEdges(nodes: nodes, focusDreamId: selectedDream?.id)

            ZStack {
                // 背景捕获层：点击空白处关闭详情
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 点击搜索框以外的空白处：直接收起键盘（不依赖系统默认失焦时机）
                        searchFocused = false
                        if selectedDream != nil {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                if let preOff = preFocusOffset, let preScale = preFocusScale {
                                    offset = preOff
                                    scale = preScale
                                    lastOffset = offset
                                    lastScale = scale
                                }
                                selectedDream = nil
                            }
                            particleSeed = UUID()
                        }
                    }

                if nodes.isEmpty {
                    emptyState
                } else {
                    // 仅选中梦境时绘制关联边：霓虹 + 沿路径流动的能量高光
                    if !edges.isEmpty {
                        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 5.0 : 1.0 / 10.0)) { context in
                            let t = context.date.timeIntervalSinceReferenceDate
                            let phase = reduceMotion ? 0 : CGFloat(t * 38)
                            highlightedEdgesLayer(edges: edges, dashPhase: phase)
                        }
                    }

                    // 节点层：highPriorityGesture 让 tap 先于父级 DragGesture 识别。
                    // 首次进入焦点时执行 zoom + pan；已在焦点模式时仅替换内容，
                    // 避免 spring 动画堆叠导致画布运动期间被触摸触发 gesture gate timeout。
                    ForEach(nodes) { node in
                        starNodeView(node: node)
                            .position(node.position)
                            .highPriorityGesture(
                                TapGesture().onEnded {
                                    guard !isFocusTapThrottled else { return }
                                    isFocusTapThrottled = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        isFocusTapThrottled = false
                                    }

                                    searchFocused = false
                                    let focusY = canvasSize.height * 0.25
                                    let centerX = canvasSize.width * 0.5
                                    let centerY = canvasSize.height * 0.5
                                    let ripple = CGPoint(x: centerX, y: focusY)

                                    if selectedDream == nil {
                                        // 首次进入焦点：记录当前位置，执行平移 + 缩放动画；
                                        // 同时固定粒子层 seed，后续切换节点不再重算粒子
                                        preFocusOffset = offset
                                        preFocusScale = scale
                                        particleSeed = node.dream.id
                                        let newScale = max(scale, 1.2)
                                        let rawOffsetW = centerX - centerX - (node.position.x - centerX) * newScale
                                        let rawOffsetH = focusY - centerY - (node.position.y - centerY) * newScale
                                        // 限制 pan 距离，防止边缘节点画布运动过远导致动画期间手势竞争
                                        let maxPan = canvasSize.height * 0.75
                                        let newOffset = CGSize(
                                            width: max(-maxPan, min(maxPan, rawOffsetW)),
                                            height: max(-maxPan, min(maxPan, rawOffsetH))
                                        )
                                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                            offset = newOffset
                                            scale = newScale
                                            lastOffset = newOffset
                                            lastScale = newScale
                                            rippleOrigin = ripple
                                            selectedDream = node.dream
                                        }
                                    } else {
                                        // 已在焦点模式：直接切换内容，不做位移动画，防止 spring 堆叠
                                        rippleOrigin = ripple
                                        selectedDream = node.dream
                                    }
                                }
                            )
                    }
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(dragGesture)
            .simultaneousGesture(magnificationGesture)
            .onAppear { self.canvasSize = geometry.size }
            .onChange(of: geometry.size) { _, newSize in self.canvasSize = newSize }
        }
    }

    private func starNodeView(node: StarMapNode) -> some View {
        let isComic = node.dream.hasComic
        let showDetail = scale > 1.2 // LOD 阈值
        // 显式放大命中区域，避免“可视光点很小，但手指触控落点偏差导致点不到”。
        // 因为节点是用 `.position(...)` 放到画布上，所以 frame/cosntentShape 会直接决定 hit-test 范围。
        let hitSize: CGFloat = max(44, 30 * node.scale)
        
        // 方案 1：命中区只约束星点层；日期/标签用同级 ZStack 叠放，避免被 hitSize 宽度压成两行。
        let isSelected = selectedDream?.id == node.dream.id
        return ZStack(alignment: .center) {
            if isSelected {
                ContinuousRippleRingsLocal(
                    period: 2.6,
                    ringCount: 3,
                    baseWidth: 40,
                    opacityScale: 1.0
                )
                .frame(width: 110, height: 110)
                .allowsHitTesting(false)
            }

            // Canvas 单遍绘制星点光晕 + 核心，消除 .blur() 离屏渲染
            // drawLayer 让模糊仅作用于光晕子层，核心圆点保持清晰
            let glowColor = isComic ? AppTheme.primaryColor : AppTheme.text
            let glowBlur = (isComic ? CGFloat(6) : CGFloat(4)) * 0.55
            let coreR = 3 * node.scale
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: glowBlur))
                    layer.fill(
                        Path(ellipseIn: CGRect(x: c.x - 7 * node.scale, y: c.y - 7 * node.scale,
                                               width: 14 * node.scale, height: 14 * node.scale)),
                        with: .color(glowColor.opacity(node.brightness * 0.5))
                    )
                }
                ctx.fill(
                    Path(ellipseIn: CGRect(x: c.x - coreR, y: c.y - coreR,
                                           width: coreR * 2, height: coreR * 2)),
                    with: .color(glowColor)
                )
            }
            .frame(width: hitSize, height: hitSize)
            .contentShape(Circle())

            VStack(alignment: .center, spacing: 4) {
                if scale > 0.7 {
                    HStack(spacing: 4) {
                        Text(Self.monthDayFormatter.string(from: node.dream.createdAt))
                            .font(.system(size: 10, weight: .bold))

                        if let tag = node.dream.tags.first {
                            Text("[\(tag)]")
                                .font(.system(size: 9))
                        }
                    }
                    .lineLimit(1)
                    .foregroundColor(isSelected ? AppTheme.primaryColor : (isComic ? AppTheme.primaryColor : AppTheme.muted))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.surface.opacity(0.6))
                    .clipShape(Capsule())
                    .offset(y: -20 * node.scale)
                }

                if showDetail {
                    Text(snippetText(from: node.dream.organizedText))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.text)
                        .lineLimit(2)
                        .frame(width: 120)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.surface.opacity(0.85))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(isComic ? AppTheme.primaryColor.opacity(0.5) : AppTheme.muted.opacity(0.3), lineWidth: 0.5))
                        )
                        .offset(y: 20 * node.scale)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // Canvas 单遍绘制所有关联边：直接 Metal 渲染，无 SwiftUI 视图分配、无 drawingGroup 合成层。
    private func highlightedEdgesLayer(edges: [StarMapEdge], dashPhase: CGFloat) -> some View {
        Canvas { ctx, _ in
            for edge in edges {
                let strength = min(max(edge.strength, 0), 1)
                let baseOpacity = 0.38 + 0.48 * Double(strength)
                let coreWidth = 1.4 + 3.2 * strength
                let phase = dashPhase * (1.0 + CGFloat(strength) * 0.35)

                var path = Path()
                path.move(to: edge.from)
                path.addQuadCurve(to: edge.to, control: edge.control)

                // 外发光层
                ctx.stroke(path,
                    with: .color(AppTheme.primaryColor.opacity(baseOpacity * 0.18)),
                    style: StrokeStyle(lineWidth: coreWidth * 5.5, lineCap: .round, lineJoin: .round))

                // 中层光晕
                ctx.stroke(path,
                    with: .color(AppTheme.primaryColor.opacity(baseOpacity * 0.40)),
                    style: StrokeStyle(lineWidth: coreWidth * 2.2, lineCap: .round, lineJoin: .round))

                // 主虚线流动核心
                ctx.stroke(path,
                    with: .color(AppTheme.primaryColor.opacity(baseOpacity * 0.92)),
                    style: StrokeStyle(lineWidth: coreWidth, lineCap: .round, lineJoin: .round,
                                       dash: [7, 11], dashPhase: phase))

                // 白色细线高光（相位错开，产生闪烁感）
                ctx.stroke(path,
                    with: .color(Color.white.opacity(0.22 + 0.38 * Double(strength))),
                    style: StrokeStyle(lineWidth: max(0.6, coreWidth * 0.42), lineCap: .round, lineJoin: .round,
                                       dash: [7, 11], dashPhase: phase + 5))
            }
        }
        // Canvas 默认对整个矩形帧命中检测，必须关闭，否则会拦截画布空白处的 dismiss 点击
        .allowsHitTesting(false)
    }

    private func snippetText(from text: String) -> String {
        let first = text
            .split(whereSeparator: \.isNewline)
            .first.map { String($0) } ?? text

        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 48 { return trimmed }

        let cutIndex = trimmed.index(trimmed.startIndex, offsetBy: 48)
        return String(trimmed[..<cutIndex]) + "…"
    }

    private func comicDateTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: date)
    }

    private func dreamDetailSheet(dream: Dream) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.monthDayFormatter.string(from: dream.createdAt))
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .kerning(1.2)
                        .foregroundColor(AppTheme.muted)

                    Text(dream.title)
                        .font(AppTheme.titleFont(size: 19))
                        .kerning(-0.25)
                        .foregroundColor(AppTheme.text)
                }

                Spacer()

                if dream.hasComic {
                    Image(systemName: "sparkles")
                        .foregroundColor(AppTheme.primaryColor)
                        .font(.system(size: 16))
                }
            }

            Divider()
                .background(AppTheme.muted.opacity(0.25))
                .padding(.vertical, 4)

            WrapView(tags: Array(dream.tags.prefix(6)))

            Text(snippetText(from: dream.organizedText))
                .font(.system(size: 15, weight: .medium, design: .default))
                .foregroundColor(AppTheme.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)

            Button {
                // 点击详情卡片内控件：收起键盘（选项 A）
                searchFocused = false
                onSelectDream(dream.id)
                selectedDream = nil
            } label: {
                Text("查看详情")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.primaryColor)
                    .foregroundColor(AppTheme.background)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            if dream.hasComic {
                if let latestComic = dream.comicArtifacts.max(by: { $0.createdAt < $1.createdAt }) {
                    HStack(spacing: 8) {
                        Text("共 \(dream.comicArtifacts.count) 版")
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .foregroundColor(AppTheme.muted)

                        Text("最近落成：\(comicDateTimeString(from: latestComic.createdAt))")
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundColor(AppTheme.muted.opacity(0.95))
                    }
                    .padding(.top, 2)
                }

                Button {
                    searchFocused = false
                    onViewComic(dream.id)
                    selectedDream = nil
                } label: {
                    HStack {
                        Text("回看已落成的四格故事")
                        Spacer()
                        Image(systemName: "sparkles.rectangle.stack.fill")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(AppTheme.surface.opacity(0.7))
                    .foregroundColor(AppTheme.text)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.muted.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }

            Text("声明：梦析为启发式建议，不提供医学/心理诊断。")
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundColor(AppTheme.muted.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
        .padding(20)
    }
}

// MARK: - 持续涟漪（TimelineView 循环相位）

/// 节点局部坐标：中心对齐星点；Canvas 单遍绘制，消除每帧 3 次 Core Image offscreen blur。
private struct ContinuousRippleRingsLocal: View {
    var period: Double = 2.6
    var ringCount: Int = 3
    var baseWidth: CGFloat = 40
    var opacityScale: CGFloat = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = t.truncatingRemainder(dividingBy: period) / period
            Canvas { ctx, size in
                ctx.addFilter(.blur(radius: 1.5))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<ringCount {
                    let stagger = Double(i) / Double(ringCount)
                    let p = CGFloat((phase + stagger).truncatingRemainder(dividingBy: 1.0))
                    let ringOpacity = Double((1 - p) * 0.55 * opacityScale)
                    let lineWidth = 1.0 + 1.6 * (1 - p)
                    let scaledR = Double(baseWidth / 2) * Double(0.4 + 1.8 * p)
                    ctx.stroke(
                        Path(ellipseIn: CGRect(
                            x: center.x - CGFloat(scaledR),
                            y: center.y - CGFloat(scaledR),
                            width: CGFloat(scaledR) * 2,
                            height: CGFloat(scaledR) * 2
                        )),
                        with: .color(AppTheme.primaryColor.opacity(ringOpacity)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 流式标签组件（用于 sheet 关键词区）。
private struct WrapView: View {
    let tags: [String]

    var body: some View {
        TagFlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                tagView(tag: tag)
            }
        }
    }

    private func tagView(tag: String) -> some View {
        Text(tag)
            .font(.system(size: 11, weight: .semibold, design: .default))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(AppTheme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(
                Capsule()
                    .stroke(AppTheme.muted.opacity(0.55), lineWidth: 1)
            )
            .background(AppTheme.surface.opacity(0.55))
            .clipShape(Capsule())
    }
}
