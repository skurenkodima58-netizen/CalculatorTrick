import SwiftUI
import Photos

// MARK: - Model

struct CalcButtonModel: Identifiable {
    enum Kind { case digit, op, fn }
    let id = UUID()
    let label: String
    let kind: Kind
    let row: Int
    let col: Int
    let action: String

    init(_ label: String, _ kind: Kind, _ row: Int, _ col: Int, _ action: String) {
        self.label = label
        self.kind = kind
        self.row = row
        self.col = col
        self.action = action
    }
}

let calcButtons: [CalcButtonModel] = [
    .init("⌫", .fn, 0, 0, "back"), .init("AC", .fn, 0, 1, "ac"), .init("%", .fn, 0, 2, "pct"), .init("÷", .op, 0, 3, "op"),
    .init("7", .digit, 1, 0, "digit"), .init("8", .digit, 1, 1, "digit"), .init("9", .digit, 1, 2, "digit"), .init("×", .op, 1, 3, "op"),
    .init("4", .digit, 2, 0, "digit"), .init("5", .digit, 2, 1, "digit"), .init("6", .digit, 2, 2, "digit"), .init("−", .op, 2, 3, "op"),
    .init("1", .digit, 3, 0, "digit"), .init("2", .digit, 3, 1, "digit"), .init("3", .digit, 3, 2, "digit"), .init("+", .op, 3, 3, "op"),
    .init("+/-", .fn, 4, 0, "sign"), .init("0", .digit, 4, 1, "digit"), .init(",", .digit, 4, 2, "comma"), .init("=", .op, 4, 3, "eq"),
]

struct PhysicsBody {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
}

private func fmt(_ n: Double) -> String {
    if n.isNaN { return "Ошибка" }
    if n == n.rounded() && abs(n) < 1e10 { return String(Int(n)) }
    var s = String(format: "%.6f", n)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}
private func displayString(_ raw: String) -> String { raw.replacingOccurrences(of: ".", with: ",") }
private func toNum(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var motion = MotionManager()

    @State private var display = "0"
    @State private var prevValue: Double? = nil
    @State private var pendingOp: String? = nil
    @State private var waitingForOperand = false

    // trick state — 3-stage island tap sequence:
    // phase 0 normal -> tap -> 1 (number hidden) -> tap -> 2 (crashed) -> tap -> 3 (number shown, still crashed)
    // shake while phase 3 -> restore -> phase 0, armed = true
    @State private var phase = 0
    @State private var numberHidden = false
    @State private var crashed = false
    @State private var armed = false
    @State private var montageShown = false
    @State private var revealed = false
    @State private var galleryOpen = false
    @State private var pinchScale: CGFloat = 1.0
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeScale: CGFloat = 1.0

    @State private var bodies: [PhysicsBody] = []
    @State private var draggingIndex: Int? = nil

    @State private var playW: CGFloat = UIScreen.main.bounds.width - 18
    @State private var playH: CGFloat = UIScreen.main.bounds.height - 250
    @State private var btnD: CGFloat = 84
    private let gapX: CGFloat = 13

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private func baseX(_ col: Int) -> CGFloat { CGFloat(col) * (btnD + gapX) }
    private func baseY(_ row: Int) -> CGFloat { CGFloat(row) * (btnD + gapX) }

    var body: some View {
        GeometryReader { geo in
            let pw = geo.size.width - 18

            ZStack(alignment: .top) {
                Color.black

                VStack(spacing: 0) {
                    Spacer().frame(height: 4)
                    HStack {
                        Image(systemName: "clock")
                        Spacer()
                        Image(systemName: "square.grid.2x2")
                    }
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 24)
                    .opacity(revealed ? 0 : 1)
                    .animation(.easeOut(duration: 0.3), value: revealed)

                    HStack {
                        Spacer()
                        Text(montageShown ? "МОНТАЖ" : displayString(display))
                            .font(.system(size: montageShown ? 54 : 88, weight: montageShown ? .bold : .light))
                            .foregroundColor(.white)
                            .tracking(montageShown ? 5 : -1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                    }
                    .padding(.horizontal, 28)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .frame(height: crashed ? 90 : nil)
                    .opacity(numberHidden ? 0 : 1)

                    ZStack(alignment: .topLeading) {
                        if crashed {
                            ForEach(Array(calcButtons.enumerated()), id: \.element.id) { index, model in
                                crumbledButton(index: index, model: model)
                            }
                        } else if !revealed {
                            ForEach(calcButtons) { model in
                                normalButton(model)
                            }
                        }
                    }
                    .frame(width: playW,
                           height: crashed ? nil : (5 * btnD + 4 * gapX),
                           alignment: .topLeading)
                    .frame(maxHeight: crashed ? .infinity : nil)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 8)
                }
                .padding(.top, geo.safeAreaInsets.top)
                .padding(.bottom, geo.safeAreaInsets.bottom)
                .scaleEffect(pinchScale)

                // Photos single-image chrome — fades in over the exact same frame
                if revealed {
                    VStack {
                        HStack {
                            Label("Все фото", systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                                .foregroundColor(Color(red: 0.04, green: 0.52, blue: 1))
                            Spacer()
                            Text("•••").foregroundColor(.white)
                        }
                        .font(.system(size: 17))
                        .padding(.horizontal, 20)
                        .padding(.top, geo.safeAreaInsets.top + 6)
                        .padding(.bottom, 14)
                        .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))

                        Spacer()

                        HStack {
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                            Spacer()
                            Image(systemName: "heart")
                            Spacer()
                            Image(systemName: "trash")
                            Spacer()
                        }
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 22)
                        .padding(.top, 20)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    }
                    .transition(.opacity)
                }

                // hidden trigger — the status bar / Dynamic Island area
                Color.clear
                    .frame(height: geo.safeAreaInsets.top + 20)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { handleIslandTap() }
            }
            .ignoresSafeArea()
            .offset(y: swipeOffset)
            .scaleEffect(swipeScale)
            .cornerRadius(swipeOffset > 0 ? min(50, swipeOffset * 0.15) : 0)
            .contentShape(Rectangle())
            .onAppear { recomputeLayout(pw) }
            .onChange(of: geo.size) { _ in recomputeLayout(pw) }
            .gesture(
                montageShown ?
                MagnificationGesture()
                    .onChanged { value in pinchScale = min(max(value, 0.85), 1.25) }
                    .onEnded { value in
                        if value < 0.94 || value > 1.08 { revealTrick() }
                        else { withAnimation(.spring()) { pinchScale = 1.0 } }
                    }
                : nil
            )
            .simultaneousGesture(
                revealed ?
                DragGesture()
                    .onChanged { value in
                        let dy = max(0, value.translation.height)
                        swipeOffset = dy
                        swipeScale = max(0.7, 1 - dy / 900)
                    }
                    .onEnded { value in
                        if swipeOffset > 90 {
                            openGallery()
                        } else {
                            withAnimation(.easeOut(duration: 0.25)) { swipeOffset = 0; swipeScale = 1.0 }
                        }
                    }
                : nil
            )

            if galleryOpen {
                GalleryView(onClose: { resetAll() })
                    .transition(.move(edge: .bottom))
                    .zIndex(100)
            }
        }
        .background(Color.black)
        .statusBar(hidden: revealed || galleryOpen)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .onReceive(timer) { _ in if crashed { updatePhysics() } }
        .onChange(of: motion.shakeDetected) { shaken in
            if shaken && crashed && phase == 3 { restoreCalculator() }
        }
    }

    private func recomputeLayout(_ pw: CGFloat) {
        playW = pw
        btnD = (pw - 3 * gapX) / 4
    }

    // MARK: Buttons

    private func colorFor(_ model: CalcButtonModel) -> Color {
        switch model.kind {
        case .op: return .orange
        case .fn: return Color(white: 0.11)
        case .digit: return Color(white: 0.2)
        }
    }

    private func normalButton(_ model: CalcButtonModel) -> some View {
        Text(model.label)
            .font(.system(size: model.kind == .fn ? btnD * 0.34 : btnD * 0.38))
            .frame(width: btnD, height: btnD)
            .background(colorFor(model))
            .foregroundColor(.white)
            .clipShape(Circle())
            .position(x: baseX(model.col) + btnD / 2, y: baseY(model.row) + btnD / 2)
            .onTapGesture { handleTap(model) }
    }

    private func crumbledButton(index: Int, model: CalcButtonModel) -> some View {
        guard index < bodies.count else { return AnyView(EmptyView()) }
        let b = bodies[index]
        return AnyView(
            Text(model.label)
                .font(.system(size: model.kind == .fn ? btnD * 0.3 : btnD * 0.34))
                .frame(width: btnD, height: btnD)
                .background(colorFor(model))
                .foregroundColor(.white)
                .clipShape(Circle())
                .shadow(radius: 4, y: 3)
                .position(x: b.x + btnD / 2, y: b.y + btnD / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard index < bodies.count else { return }
                            draggingIndex = index
                            let nx = min(max(0, value.location.x - btnD / 2), playW - btnD)
                            let ny = min(max(0, value.location.y - btnD / 2), playH - btnD)
                            bodies[index].vx = (nx - bodies[index].x) * 5
                            bodies[index].vy = (ny - bodies[index].y) * 5
                            bodies[index].x = nx
                            bodies[index].y = ny
                        }
                        .onEnded { _ in draggingIndex = nil }
                )
        )
    }

    // MARK: Calculator logic

    private func handleTap(_ model: CalcButtonModel) {
        if montageShown {
            if model.action == "digit" { montageShown = false; armed = false; display = model.label; waitingForOperand = false; return }
            if model.action == "ac" { montageShown = false; armed = false; clearAll(); return }
        }
        switch model.action {
        case "ac": clearAll()
        case "back": display = display.count > 1 ? String(display.dropLast()) : "0"
        case "sign": display = fmt(-1 * toNum(display))
        case "pct": display = fmt(toNum(display) / 100)
        case "comma": if !display.contains(",") { display += "," }
        case "eq": handleEquals()
        case "op": chooseOp(model.label)
        default:
            if waitingForOperand { display = model.label; waitingForOperand = false }
            else { display = display == "0" ? model.label : display + model.label }
        }
    }

    private func clearAll() {
        display = "0"; prevValue = nil; pendingOp = nil; waitingForOperand = false
    }
    private func chooseOp(_ nextOp: String) {
        let cur = toNum(display)
        if let p = prevValue, let op = pendingOp, !waitingForOperand {
            let r = compute(p, cur, op); display = fmt(r); prevValue = r
        } else { prevValue = cur }
        pendingOp = nextOp; waitingForOperand = true
    }
    private func compute(_ a: Double, _ b: Double, _ op: String) -> Double {
        switch op {
        case "+": return a + b
        case "−": return a - b
        case "×": return a * b
        case "÷": return b == 0 ? .nan : a / b
        default: return b
        }
    }
    private func handleEquals() {
        if armed {
            armed = false
            withAnimation { montageShown = true }
            prevValue = nil; pendingOp = nil; waitingForOperand = true
            return
        }
        if let p = prevValue, let op = pendingOp {
            display = fmt(compute(p, toNum(display), op))
            prevValue = nil; pendingOp = nil; waitingForOperand = true
        }
    }

    // MARK: Trick sequence

    private func handleIslandTap() {
        if revealed || galleryOpen || montageShown { return }
        switch phase {
        case 0: numberHidden = true; phase = 1
        case 1: crashCalculator(); phase = 2
        case 2: withAnimation(.easeIn(duration: 0.2)) { numberHidden = false }; phase = 3
        default: break
        }
    }

    private func crashCalculator() {
        withAnimation(.easeOut(duration: 0.2)) { crashed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let floor = playH - btnD, wallX = playW - btnD
            bodies = calcButtons.enumerated().map { i, _ in
                let col = CGFloat(i % 2), stack = CGFloat(i / 2)
                return PhysicsBody(
                    x: min(wallX, col * btnD * 0.5 + CGFloat.random(in: 0...6)),
                    y: max(0, floor - stack * btnD * 0.42 - CGFloat.random(in: 0...6)),
                    vx: 0, vy: 0
                )
            }
        }
    }

    private func restoreCalculator() {
        withAnimation(.interpolatingSpring(stiffness: 170, damping: 16)) {
            for i in bodies.indices {
                let m = calcButtons[i]
                bodies[i].x = baseX(m.col); bodies[i].y = baseY(m.row)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeInOut(duration: 0.25)) { crashed = false; numberHidden = false }
            phase = 0
            armed = true
        }
    }

    /// Buttons roll with the gyroscope, gently, and stay bounded within the calculator's own area.
    private func updatePhysics() {
        let dt: CGFloat = 1.0 / 60.0
        let floor = playH - btnD, wallX = playW - btnD
        for i in bodies.indices {
            if draggingIndex == i { continue }
            bodies[i].vx += CGFloat(motion.tiltX) * 220 * dt
            bodies[i].vy += CGFloat(motion.tiltY) * 220 * dt + 4 * dt
            bodies[i].vx *= 0.985; bodies[i].vy *= 0.985
            bodies[i].x += bodies[i].vx * dt
            bodies[i].y += bodies[i].vy * dt
            if bodies[i].x < 0 { bodies[i].x = 0; bodies[i].vx *= -0.4 }
            if bodies[i].x > wallX { bodies[i].x = wallX; bodies[i].vx *= -0.4 }
            if bodies[i].y < 0 { bodies[i].y = 0; bodies[i].vy *= -0.4 }
            if bodies[i].y > floor { bodies[i].y = floor; bodies[i].vy *= -0.35 }
        }
    }

    // MARK: Reveal + gallery + save

    private func revealTrick() {
        saveRevealScreenshot()
        montageShown = false
        withAnimation(.easeInOut(duration: 0.4)) { pinchScale = 1.0; revealed = true }
    }

    private func openGallery() {
        withAnimation(.easeInOut(duration: 0.35)) {
            galleryOpen = true
        }
    }

    private func saveRevealScreenshot() {
        let card = VStack(spacing: 0) {
            HStack { Spacer(); Text("МОНТАЖ").font(.system(size: 54, weight: .bold)).tracking(5).foregroundColor(.white) }
                .padding(.trailing, 28).padding(.top, 40)
            Spacer()
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        .background(Color.black)

        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        guard let uiImage = renderer.uiImage else { return }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            })
        }
    }

    private func resetAll() {
        withAnimation(.easeInOut(duration: 0.2)) {
            galleryOpen = false; revealed = false; montageShown = false; armed = false
            pinchScale = 1.0; swipeOffset = 0; swipeScale = 1.0
        }
        display = "0"; prevValue = nil; pendingOp = nil; waitingForOperand = false
        phase = 0; numberHidden = false; crashed = false; bodies = []
    }
}

// MARK: - Fake gallery ("Медиатека") screen

struct GalleryView: View {
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Медиатека").font(.system(size: 30, weight: .heavy))
                            HStack(spacing: 4) {
                                Image(systemName: "icloud")
                                Text("Хранилище заполнено")
                            }
                            .font(.system(size: 13))
                            .foregroundColor(Color(white: 0.55))
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal")
                                .frame(width: 36, height: 36)
                                .background(Color(white: 0.11))
                                .clipShape(Circle())
                            Text("Выбрать")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Color(white: 0.78))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, geo.safeAreaInsets.top + 4)
                    .padding(.bottom, 10)

                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 4), spacing: 1.5) {
                            ForEach(0..<28) { i in
                                if i == 0 {
                                    ZStack {
                                        Color.black
                                        Text("МОНТАЖ")
                                            .font(.system(size: 11, weight: .heavy))
                                            .foregroundColor(.white)
                                    }
                                    .aspectRatio(1, contentMode: .fill)
                                    .overlay(Rectangle().stroke(Color(white: 0.2), lineWidth: 1))
                                    .onTapGesture { onClose() }
                                } else {
                                    Color(white: 0.17)
                                        .aspectRatio(1, contentMode: .fill)
                                        .onTapGesture { onClose() }
                                }
                            }
                        }
                        .padding(.bottom, 100)
                    }
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .frame(width: 46, height: 46)
                            .background(Color(white: 0.11))
                            .clipShape(Circle())
                            .padding(.trailing, 18)
                            .padding(.bottom, geo.safeAreaInsets.bottom + 68)
                    }
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 3) {
                            Image(systemName: "square.grid.2x2.fill")
                            Text("Медиатека").font(.system(size: 10))
                        }
                        .foregroundColor(.orange)
                        Spacer()
                        VStack(spacing: 3) {
                            Image(systemName: "rectangle.stack")
                            Text("Коллекции").font(.system(size: 10))
                        }
                        .foregroundColor(Color(white: 0.55))
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 10)
                    .background(Color(white: 0.08).opacity(0.95).ignoresSafeArea())
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
