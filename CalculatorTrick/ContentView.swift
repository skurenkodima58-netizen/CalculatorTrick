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

// Real iOS Calculator layout: backspace/AC/%/÷ on top row,
// +/- / 0 / , / = on bottom row (0 is not wide — matches current iOS layout).
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
    var rotation: Double
    var angularVelocity: Double
}

private func fmt(_ n: Double) -> String {
    if n.isNaN { return "Ошибка" }
    if n == n.rounded() && abs(n) < 1e10 {
        return String(Int(n))
    }
    var s = String(format: "%.6f", n)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}
/// Display uses a comma as the decimal separator (RU locale), matching the real system Calculator.
private func displayString(_ raw: String) -> String { raw.replacingOccurrences(of: ".", with: ",") }
private func toNum(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var motion = MotionManager()

    // calculator state
    @State private var display = "0"
    @State private var prevValue: Double? = nil
    @State private var pendingOp: String? = nil
    @State private var waitingForOperand = false

    // trick state
    @State private var crashed = false
    @State private var numberHidden = false
    @State private var armed = false
    @State private var montageShown = false
    @State private var revealed = false
    @State private var pinchScale: CGFloat = 1.0

    // physics
    @State private var bodies: [PhysicsBody] = []
    @State private var draggingIndex: Int? = nil
    @State private var activeIndices: Set<Int> = []
    @State private var restoring = false

    private let currentYear = Calendar.current.component(.year, from: Date())
    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    // Layout metrics — computed against the real device's own screen size
    // so this fills the whole phone edge-to-edge, no mock bezel.
    private let D: CGFloat = 90
    private let GAP: CGFloat = 15
    private func baseX(_ col: Int, playW: CGFloat) -> CGFloat {
        let pad = (playW - (4 * D + 3 * GAP)) / 2
        return pad + CGFloat(col) * (D + GAP)
    }
    private func baseY(_ row: Int) -> CGFloat { CGFloat(row) * (D + GAP) }

    var body: some View {
        GeometryReader { geo in
            let playW = geo.size.width - 18
            let playH = geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - 150

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
                            .font(.system(size: montageShown ? 58 : 92, weight: montageShown ? .bold : .light))
                            .foregroundColor(.white)
                            .tracking(montageShown ? 5 : -1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                    }
                    .padding(.horizontal, 28)
                    .frame(minHeight: 118, alignment: .bottom)
                    .opacity(numberHidden ? 0 : 1)

                    ZStack(alignment: .topLeading) {
                        if crashed {
                            ForEach(Array(calcButtons.enumerated()), id: \.element.id) { index, model in
                                crumbledButton(index: index, model: model, playW: playW, playH: playH)
                            }
                        } else if !revealed {
                            ForEach(calcButtons) { model in
                                normalButton(model, playW: playW)
                            }
                        }
                    }
                    .frame(width: playW, height: crashed ? playH : 5 * (D + GAP), alignment: .topLeading)
                    .padding(.horizontal, 9)

                    Spacer(minLength: 0)
                }
                .padding(.top, geo.safeAreaInsets.top)
                .padding(.bottom, geo.safeAreaInsets.bottom)
                .scaleEffect(pinchScale)

                // Photos single-image chrome — fades in over the EXACT same frame.
                // Nothing about the underlying picture changes; only this overlay appears.
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

                // hidden trigger zone — the status bar / Dynamic Island area
                Color.clear
                    .frame(height: geo.safeAreaInsets.top + 20)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { handleSpeakerTap() }
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(
                montageShown ?
                MagnificationGesture()
                    .onChanged { value in pinchScale = min(max(value, 0.85), 1.25) }
                    .onEnded { value in
                        if value < 0.94 || value > 1.08 {
                            revealTrick()
                        } else {
                            withAnimation(.spring()) { pinchScale = 1.0 }
                        }
                    }
                : nil
            )
        }
        .background(Color.black)
        .statusBar(hidden: revealed)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .onReceive(timer) { _ in if crashed && !restoring { updatePhysics() } }
        .onChange(of: motion.shakeDetected) { shaken in
            if shaken && crashed { restoreCalculator() }
        }
    }

    // MARK: Buttons

    private func colorFor(_ model: CalcButtonModel) -> Color {
        switch model.kind {
        case .op: return .orange
        case .fn: return Color(white: 0.65)
        case .digit: return Color(white: 0.2)
        }
    }

    private func normalButton(_ model: CalcButtonModel, playW: CGFloat) -> some View {
        Text(model.label)
            .font(.system(size: model.kind == .fn ? 30 : 34))
            .frame(width: D, height: D)
            .background(colorFor(model))
            .foregroundColor(model.kind == .fn ? .black : .white)
            .clipShape(Circle())
            .position(x: baseX(model.col, playW: playW) + D / 2, y: baseY(model.row) + D / 2)
            .onTapGesture { handleTap(model) }
    }

    private func crumbledButton(index: Int, model: CalcButtonModel, playW: CGFloat, playH: CGFloat) -> some View {
        guard index < bodies.count else { return AnyView(EmptyView()) }
        let body = bodies[index]
        return AnyView(
            Text(model.label)
                .font(.system(size: model.kind == .fn ? 26 : 30))
                .frame(width: D, height: D)
                .background(colorFor(model))
                .foregroundColor(model.kind == .fn ? .black : .white)
                .clipShape(Circle())
                .shadow(radius: 4, y: 3)
                .rotationEffect(.degrees(body.rotation))
                .position(x: body.x + D / 2, y: body.y + D / 2)
                .animation(.easeOut(duration: 0.2), value: activeIndices.contains(index))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard index < bodies.count else { return }
                            draggingIndex = index
                            let nx = min(max(0, value.location.x - D / 2), playW - D)
                            let ny = min(max(0, value.location.y - D / 2), playH - D)
                            bodies[index].vx = (nx - bodies[index].x) * 6
                            bodies[index].vy = (ny - bodies[index].y) * 6
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
        switch model.action {
        case "ac": clearAll()
        case "back":
            if montageShown { montageShown = false; armed = false }
            display = display.count > 1 ? String(display.dropLast()) : "0"
        case "sign": display = fmt(-1 * toNum(display))
        case "pct": display = fmt(toNum(display) / 100)
        case "comma": if !display.contains(",") { display += "," }
        case "eq": handleEquals()
        case "op": chooseOp(model.label)
        default: inputDigit(model.label)
        }
    }

    private func inputDigit(_ d: String) {
        if montageShown {
            montageShown = false
            armed = false
            display = d
            waitingForOperand = false
            return
        }
        if waitingForOperand {
            display = d
            waitingForOperand = false
        } else {
            display = display == "0" ? d : display + d
        }
    }

    private func clearAll() {
        display = "0"; prevValue = nil; pendingOp = nil; waitingForOperand = false
        montageShown = false; armed = false
    }

    private func chooseOp(_ nextOp: String) {
        if montageShown { montageShown = false; armed = false; display = "0" }
        let cur = toNum(display)
        if let p = prevValue, let op = pendingOp, !waitingForOperand {
            let r = compute(p, cur, op)
            display = fmt(r)
            prevValue = r
        } else {
            prevValue = cur
        }
        pendingOp = nextOp
        waitingForOperand = true
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
            let cur = toNum(display)
            let result = cur / Double(currentYear)
            display = fmt(result)
            prevValue = nil; pendingOp = nil; waitingForOperand = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation { montageShown = true }
            }
            return
        }
        if let p = prevValue, let op = pendingOp {
            let cur = toNum(display)
            let r = compute(p, cur, op)
            display = fmt(r)
            prevValue = nil; pendingOp = nil; waitingForOperand = true
        }
    }

    // MARK: Trick sequence

    /// The hidden trigger: tapping the status-bar / Dynamic Island area at the top.
    /// First tap while intact → number vanishes + buttons crumble.
    /// Second tap while crashed and the number is hidden → number comes back,
    /// buttons stay scattered and playable until the phone is shaken.
    private func handleSpeakerTap() {
        if revealed { return }
        if !crashed && !armed && !montageShown {
            crashCalculator()
        } else if crashed && numberHidden {
            withAnimation(.easeIn(duration: 0.2)) { numberHidden = false }
        }
    }

    private func crashCalculator() {
        bodies = calcButtons.map { model in
            PhysicsBody(x: 0, y: baseY(model.row), vx: 0, vy: 0, rotation: 0, angularVelocity: 0)
        }
        activeIndices = []
        restoring = false
        numberHidden = true
        withAnimation(.easeOut(duration: 0.25)) { crashed = true }

        for i in calcButtons.indices {
            let delay = 0.04 * Double(i) + Double.random(in: 0...0.035)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard i < bodies.count else { return }
                withAnimation(.easeIn(duration: 0.12)) {
                    bodies[i].vx = CGFloat.random(in: -85...85)
                    bodies[i].vy = CGFloat.random(in: -45...15)
                    bodies[i].angularVelocity = Double.random(in: -170...170)
                    activeIndices.insert(i)
                }
            }
        }
    }

    private func restoreCalculator() {
        guard crashed, !restoring, !revealed else { return }
        restoring = true
        withAnimation(.interpolatingSpring(stiffness: 170, damping: 16)) {
            for i in bodies.indices {
                let model = calcButtons[i]
                bodies[i].y = baseY(model.row)
                bodies[i].rotation = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeInOut(duration: 0.25)) { crashed = false; numberHidden = false }
            restoring = false
            armed = true
        }
    }

    private func updatePhysics() {
        let dt: CGFloat = 1.0 / 60.0
        let gravity: CGFloat = 950

        for i in bodies.indices {
            if draggingIndex == i { continue }
            if !activeIndices.contains(i) { continue }
            bodies[i].vy += gravity * dt
            bodies[i].vx += CGFloat(motion.tiltX) * 260 * dt
            bodies[i].vy += CGFloat(motion.tiltY) * 260 * dt
            bodies[i].x += bodies[i].vx * dt
            bodies[i].y += bodies[i].vy * dt
            bodies[i].rotation += bodies[i].angularVelocity * Double(dt)
        }
    }

    // MARK: Reveal + save to Photos

    /// Nothing about the on-screen picture changes here — only the thin
    /// Photos chrome fades in over the same frame in `body`, plus a real
    /// screenshot of this exact moment is saved silently to the library.
    private func revealTrick() {
        saveRevealScreenshot()
        withAnimation(.easeInOut(duration: 0.4)) { pinchScale = 1.0; revealed = true }
    }

    private func saveRevealScreenshot() {
        let card = VStack(spacing: 0) {
            HStack { Spacer(); Text("МОНТАЖ").font(.system(size: 58, weight: .bold)).tracking(5).foregroundColor(.white) }
                .padding(.trailing, 28).padding(.top, 40)
            Spacer()
        }
        .frame(width: 440, height: 956)
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
        revealed = false; montageShown = false; armed = false; pinchScale = 1.0
        display = "0"; prevValue = nil; pendingOp = nil; waitingForOperand = false
        crashed = false; numberHidden = false; restoring = false; bodies = []; activeIndices = []
    }
}

#Preview {
    ContentView()
}
