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

/// Small calculator glyph matching the real Calculator app's top-right toggle icon.
struct MiniCalculatorIcon: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.14)
                    .stroke(Color.white, lineWidth: w * 0.09)
                RoundedRectangle(cornerRadius: w * 0.06)
                    .fill(Color.white)
                    .frame(width: w * 0.58, height: h * 0.2)
                    .offset(y: -h * 0.22)
                VStack(spacing: h * 0.1) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: w * 0.1) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle().fill(Color.white).frame(width: w * 0.12, height: w * 0.12)
                            }
                        }
                    }
                }
                .offset(y: h * 0.16)
            }
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var motion = MotionManager()

    @State private var display = "0"       // what's shown on screen (full expression, e.g. "23+63")
    @State private var currentTerm = "0"    // the number currently being typed
    @State private var committedPrefix = "" // everything already typed before currentTerm, e.g. "23+"
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
                        MiniCalculatorIcon().frame(width: 22, height: 22)
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
                        } else {
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
        if revealed { return }
        if montageShown {
            if model.action == "digit" {
                montageShown = false; armed = false
                currentTerm = model.label; committedPrefix = ""; display = currentTerm
                waitingForOperand = false
                return
            }
            if model.action == "ac" { montageShown = false; armed = false; clearAll(); return }
        }
        switch model.action {
        case "ac": clearAll()
        case "back":
            currentTerm = currentTerm.count > 1 ? String(currentTerm.dropLast()) : "0"
            display = committedPrefix + displayString(currentTerm)
        case "sign":
            currentTerm = fmt(-1 * toNum(currentTerm))
            display = committedPrefix + displayString(currentTerm)
        case "pct":
            currentTerm = fmt(toNum(currentTerm) / 100)
            display = committedPrefix + displayString(currentTerm)
        case "comma":
            if !currentTerm.contains(",") { currentTerm += "," }
            display = committedPrefix + currentTerm
        case "eq": handleEquals()
        case "op": chooseOp(model.label)
        default: inputDigit(model.label)
        }
    }

    private func inputDigit(_ d: String) {
        if waitingForOperand { currentTerm = d; waitingForOperand = false }
        else { currentTerm = currentTerm == "0" ? d : currentTerm + d }
        display = committedPrefix + displayString(currentTerm)
    }

    private func clearAll() {
        display = "0"; currentTerm = "0"; committedPrefix = ""
        prevValue = nil; pendingOp = nil; waitingForOperand = false
    }
    private func chooseOp(_ nextOp: String) {
        let cur = toNum(currentTerm)
        if let p = prevValue, let op = pendingOp, !waitingForOperand {
            let r = compute(p, cur, op)
            prevValue = r
            committedPrefix = displayString(fmt(r)) + nextOp
        } else {
            prevValue = cur
            committedPrefix = displayString(currentTerm) + nextOp
        }
        pendingOp = nextOp
        waitingForOperand = true
        display = committedPrefix
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
            committedPrefix = ""
            return
        }
        if let p = prevValue, let op = pendingOp {
            let r = compute(p, toNum(currentTerm), op)
            currentTerm = fmt(r)
            display = displayString(currentTerm)
            committedPrefix = ""
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
            let n = calcButtons.count
            let laneW = n > 1 ? wallX / CGFloat(n - 1) : 0
            let lanes = Array(0..<n).shuffled()
            bodies = calcButtons.enumerated().map { i, _ in
                let lane = CGFloat(lanes[i])
                let x = min(wallX, max(0, lane * laneW + CGFloat.random(in: -12...12)))
                let y = max(0, floor - CGFloat.random(in: 0...(btnD * 1.3)))
                return PhysicsBody(x: x, y: y, vx: 0, vy: 0)
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
        display = "0"; currentTerm = "0"; committedPrefix = ""; prevValue = nil; pendingOp = nil; waitingForOperand = false
        phase = 0; numberHidden = false; crashed = false; bodies = []
    }
}

// MARK: - Fake gallery ("Медиатека") screen

private let photoPalettes: [[Color]] = [
    [Color(red: 0.56, green: 0.77, blue: 1.0), Color(red: 0.23, green: 0.48, blue: 0.84)],
    [Color(red: 1.0, green: 0.82, blue: 0.58), Color(red: 0.82, green: 0.57, blue: 0.24)],
    [Color(red: 0.66, green: 1.0, blue: 0.47), Color(red: 0.47, green: 1.0, blue: 0.84)],
    [Color(red: 0.96, green: 0.83, blue: 0.4), Color(red: 0.99, green: 0.56, blue: 0.52)],
    [Color(red: 0.52, green: 0.98, blue: 0.69), Color(red: 0.56, green: 0.83, blue: 0.96)],
    [Color(red: 0.99, green: 0.8, blue: 0.56), Color(red: 0.84, green: 0.49, blue: 0.92)],
    [Color(red: 0.63, green: 0.77, blue: 0.99), Color(red: 0.76, green: 0.91, blue: 0.98)],
    [Color(red: 0.98, green: 0.76, blue: 0.92), Color(red: 0.65, green: 0.76, blue: 0.93)],
    [Color(red: 0.98, green: 0.96, blue: 0.53), Color(red: 0.59, green: 0.9, blue: 0.63)],
    [Color(red: 1.0, green: 0.93, blue: 0.82), Color(red: 0.99, green: 0.71, blue: 0.62)],
    [Color(red: 0.54, green: 0.97, blue: 0.99), Color(red: 0.4, green: 0.65, blue: 1.0)],
]

/// A tiny scaled-down rendering of the calculator screen (with the МОНТАЖ text and
/// button grid), used as the gallery thumbnail so it reads as a real screenshot.
struct CalcThumbnail: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Color.black
                Text("МОНТАЖ")
                    .font(.system(size: geo.size.width * 0.09, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.top, geo.size.height * 0.16)
                    .padding(.trailing, geo.size.width * 0.08)

                ForEach(calcButtons) { m in
                    let d = geo.size.width * 0.19
                    let gap = geo.size.width * 0.035
                    let x = geo.size.width * 0.06 + CGFloat(m.col) * (d + gap) + d / 2
                    let y = geo.size.height * 0.42 + CGFloat(m.row) * (d + gap) + d / 2
                    Circle()
                        .fill(m.kind == .op ? Color.orange : (m.kind == .fn ? Color(white: 0.11) : Color(white: 0.22)))
                        .frame(width: d, height: d)
                        .position(x: x, y: y)
                }
            }
        }
        .clipped()
    }
}

struct GalleryView: View {
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Медиатека").font(.system(size: 30, weight: .heavy)).foregroundColor(.black)
                            HStack(spacing: 4) {
                                Image(systemName: "icloud")
                                Text("Хранилище заполнено · Увеличить >")
                            }
                            .font(.system(size: 13))
                            .foregroundColor(Color(white: 0.43))
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.black)
                                .frame(width: 36, height: 36)
                                .background(Color(white: 0.95))
                                .clipShape(Circle())
                            Text("Выбрать")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(red: 0, green: 0.48, blue: 1))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Color(white: 0.95))
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
                                    CalcThumbnail()
                                        .aspectRatio(1, contentMode: .fill)
                                        .onTapGesture { onClose() }
                                } else {
                                    let pair = photoPalettes[i % photoPalettes.count]
                                    LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing)
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
                            .foregroundColor(.black)
                            .frame(width: 46, height: 46)
                            .background(Color(white: 0.95))
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
                    .background(
                        Color(white: 0.97).opacity(0.95)
                            .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color(white: 0.8)), alignment: .top)
                            .ignoresSafeArea()
                    )
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
