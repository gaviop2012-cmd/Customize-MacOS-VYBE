import SwiftUI
import AppKit

// MARK: - Assistant State

enum OrbState: String {
    case idle
    case listening
    case thinking
    case speaking
    case executing
    case error
}

// MARK: - AI Orb View (JARVIS-style)

struct AIOrb: View {
    @EnvironmentObject private var assistant: VYBEAssistant
    @State private var animationPhase: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.5
    @State private var rotationAngle: Double = 0
    @State private var particlePhase: CGFloat = 0
    @State private var showTranscript = true
    @State private var manualInput = ""

    private var orbState: OrbState {
        if assistant.hasError { return .error }
        if assistant.isExecutingAction { return .executing }
        if assistant.isSpeaking { return .speaking }
        if assistant.isThinking { return .thinking }
        if assistant.isListening { return .listening }
        return .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar

            // Main orb area
            ZStack {
                // Background
                backgroundGradient

                VStack(spacing: 16) {
                    Spacer()

                    // The Orb
                    orbView
                        .frame(width: 160, height: 160)

                    // State label
                    stateLabel

                    Spacer()

                    // Transcript area
                    if showTranscript {
                        transcriptArea
                    }

                    // Controls
                    controlBar
                }
                .padding(20)
            }
        }
        .background(Color(red: 0.02, green: 0.03, blue: 0.07))
        .frame(minWidth: 340, minHeight: 420)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                animationPhase = 1
            }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                pulseScale = 1.08
                glowOpacity = 0.7
            }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                particlePhase = 1
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(orbStateColor)
                .frame(width: 8, height: 8)
                .shadow(color: orbStateColor.opacity(0.6), radius: 4)
            Text("VYBE AI")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .tracking(2)
            Spacer()
            Button {
                showTranscript.toggle()
            } label: {
                Image(systemName: showTranscript ? "text.bubble.fill" : "text.bubble")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Toggle transcript")

            Button {
                assistant.showSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("AI Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.04, green: 0.05, blue: 0.10).opacity(0.95))
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            // Deep space gradient
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.02, blue: 0.06),
                    Color(red: 0.03, green: 0.05, blue: 0.12),
                    Color(red: 0.02, green: 0.03, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Ambient particles
            Canvas { context, size in
                let time = animationPhase * .pi * 2
                for i in 0..<20 {
                    let fi = CGFloat(i)
                    let x = size.width * (0.1 + 0.8 * sin(fi * 0.7 + time * 0.3).magnitude)
                    let y = size.height * (0.1 + 0.8 * cos(fi * 0.5 + time * 0.2).magnitude)
                    let r = 1.0 + sin(fi * 0.3 + time) * 0.5
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(.cyan.opacity(0.15 + sin(fi + time) * 0.1))
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Orb View

    private var orbView: some View {
        ZStack {
            // Outer glow rings
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(
                        orbGradient(for: ring),
                        lineWidth: ring == 0 ? 1.5 : 1
                    )
                    .scaleEffect(pulseScale + CGFloat(ring) * 0.12)
                    .opacity(glowOpacity * (ring == 0 ? 1.0 : 0.4 - Double(ring) * 0.1))
                    .rotationEffect(.degrees(rotationAngle * (ring % 2 == 0 ? 1 : -1) * 0.5))
            }

            // Energy field
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 * 0.75
                let time = animationPhase * .pi * 2

                // Animated blob shape
                var path = Path()
                let points = 60
                for i in 0..<points {
                    let angle = CGFloat(i) / CGFloat(points) * .pi * 2
                    let wobble = sin(angle * 3 + time * 2) * 0.08 +
                                 cos(angle * 5 - time * 1.5) * 0.05 +
                                 sin(angle * 7 + time * 3) * 0.03
                    let r = radius * (1.0 + wobble * stateIntensity)
                    let x = center.x + cos(angle) * r
                    let y = center.y + sin(angle) * r
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                path.closeSubpath()

                // Fill with radial gradient
                context.fill(path, with: .radialGradient(
                    Gradient(colors: orbColors),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                ))

                // Inner glow
                context.fill(path, with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.3), .clear]),
                    center: CGPoint(x: center.x - radius * 0.2, y: center.y - radius * 0.2),
                    startRadius: 0,
                    endRadius: radius * 0.6
                ))
            }
            .scaleEffect(pulseScale)

            // Waveform overlay for listening/speaking
            if orbState == .listening || orbState == .speaking {
                waveformOverlay
            }

            // Thinking spinner
            if orbState == .thinking || orbState == .executing {
                thinkingOverlay
            }

            // Center icon
            orbCenterIcon
        }
        .shadow(color: orbShadowColor, radius: 30, y: 0)
    }

    private var stateIntensity: CGFloat {
        switch orbState {
        case .idle: return 0.5
        case .listening: return 1.2
        case .thinking: return 0.8
        case .speaking: return 1.0
        case .executing: return 0.9
        case .error: return 0.3
        }
    }

    private var orbColors: [Color] {
        switch orbState {
        case .idle:
            return [Color(red: 0.0, green: 0.6, blue: 0.9).opacity(0.7),
                    Color(red: 0.1, green: 0.3, blue: 0.8).opacity(0.5),
                    Color(red: 0.05, green: 0.15, blue: 0.4).opacity(0.3)]
        case .listening:
            return [Color(red: 0.0, green: 0.8, blue: 1.0).opacity(0.9),
                    Color(red: 0.0, green: 0.5, blue: 0.9).opacity(0.7),
                    Color(red: 0.0, green: 0.2, blue: 0.5).opacity(0.4)]
        case .thinking:
            return [Color(red: 0.4, green: 0.2, blue: 0.9).opacity(0.8),
                    Color(red: 0.2, green: 0.1, blue: 0.7).opacity(0.6),
                    Color(red: 0.1, green: 0.05, blue: 0.3).opacity(0.3)]
        case .speaking:
            return [Color(red: 0.0, green: 0.7, blue: 0.7).opacity(0.8),
                    Color(red: 0.0, green: 0.4, blue: 0.6).opacity(0.6),
                    Color(red: 0.0, green: 0.2, blue: 0.4).opacity(0.3)]
        case .executing:
            return [Color(red: 0.0, green: 0.8, blue: 0.5).opacity(0.8),
                    Color(red: 0.0, green: 0.5, blue: 0.4).opacity(0.6),
                    Color(red: 0.0, green: 0.2, blue: 0.2).opacity(0.3)]
        case .error:
            return [Color(red: 0.9, green: 0.2, blue: 0.2).opacity(0.7),
                    Color(red: 0.6, green: 0.1, blue: 0.15).opacity(0.5),
                    Color(red: 0.3, green: 0.05, blue: 0.08).opacity(0.3)]
        }
    }

    private var orbShadowColor: Color {
        switch orbState {
        case .idle: return .cyan.opacity(0.3)
        case .listening: return .cyan.opacity(0.5)
        case .thinking: return .purple.opacity(0.4)
        case .speaking: return .teal.opacity(0.4)
        case .executing: return .green.opacity(0.3)
        case .error: return .red.opacity(0.4)
        }
    }

    private var orbStateColor: Color {
        switch orbState {
        case .idle: return .cyan
        case .listening: return .green
        case .thinking: return .purple
        case .speaking: return .teal
        case .executing: return .green
        case .error: return .red
        }
    }

    private func orbGradient(for ring: Int) -> AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                orbStateColor.opacity(0.6),
                .clear,
                orbStateColor.opacity(0.3),
                .clear,
                orbStateColor.opacity(0.6)
            ]),
            center: .center,
            startAngle: .degrees(rotationAngle + Double(ring * 60)),
            endAngle: .degrees(rotationAngle + Double(ring * 60) + 360)
        )
    }

    // MARK: - Waveform Overlay

    private var waveformOverlay: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let time = particlePhase * .pi * 2
            let bars = 12

            for i in 0..<bars {
                let angle = CGFloat(i) / CGFloat(bars) * .pi * 2
                let height = 8 + sin(CGFloat(i) * 1.2 + time * 3) * 12
                let r1 = min(size.width, size.height) * 0.28
                let r2 = r1 + height

                let x1 = center.x + cos(angle) * r1
                let y1 = center.y + sin(angle) * r1
                let x2 = center.x + cos(angle) * r2
                let y2 = center.y + sin(angle) * r2

                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x2, y: y2))

                context.stroke(path, with: .color(.cyan.opacity(0.6)), lineWidth: 2.5)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Thinking Overlay

    private var thinkingOverlay: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let time = animationPhase * .pi * 2
            let dots = 8

            for i in 0..<dots {
                let angle = CGFloat(i) / CGFloat(dots) * .pi * 2 + time * 2
                let r = min(size.width, size.height) * 0.32
                let x = center.x + cos(angle) * r
                let y = center.y + sin(angle) * r
                let dotSize: CGFloat = 3 + sin(CGFloat(i) + time * 3) * 1.5

                context.fill(
                    Path(ellipseIn: CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)),
                    with: .color(.purple.opacity(0.7))
                )
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Center Icon

    private var orbCenterIcon: some View {
        Group {
            switch orbState {
            case .idle:
                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
            case .listening:
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.cyan)
                    .shadow(color: .cyan.opacity(0.5), radius: 8)
            case .thinking:
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                    .tint(.white)
            case .speaking:
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.teal)
            case .executing:
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - State Label

    private var stateLabel: some View {
        VStack(spacing: 4) {
            Text(stateText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(orbStateColor.opacity(0.8))

            Text(assistant.status)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
    }

    private var stateText: String {
        switch orbState {
        case .idle: return "READY"
        case .listening: return "LISTENING"
        case .thinking: return "PROCESSING"
        case .speaking: return "SPEAKING"
        case .executing: return "EXECUTING"
        case .error: return "ERROR"
        }
    }

    // MARK: - Transcript Area

    private var transcriptArea: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(assistant.messages.suffix(10)) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: 150)
                .onChange(of: assistant.messages.count) { _ in
                    if let last = assistant.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))

            // Live transcript during listening
            if assistant.isListening && !assistant.transcript.isEmpty {
                Text(assistant.transcript)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.8))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
    }

    private func messageBubble(_ message: AssistantMessage) -> some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }
            Text(message.text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .textSelection(.enabled)
                .padding(8)
                .background(
                    message.role == .user
                        ? Color.cyan.opacity(0.15)
                        : Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .frame(maxWidth: 260, alignment: message.role == .user ? .trailing : .leading)
            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: 10) {
            // Text input
            HStack(spacing: 8) {
                TextField("Ask VYBE AI…", text: $manualInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .lineLimit(1...3)
                    .onSubmit { submitManual() }

                Button {
                    submitManual()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
                .disabled(manualInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Action buttons
            HStack(spacing: 16) {
                // Microphone button
                Button {
                    if assistant.isListening {
                        assistant.finishRecognitionAndAsk()
                    } else {
                        assistant.startListening()
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: assistant.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 16))
                        Text(assistant.isListening ? "STOP" : "LISTEN")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(assistant.isListening ? .red : .cyan)
                    .frame(width: 56, height: 44)
                    .background(
                        (assistant.isListening ? Color.red : Color.cyan).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
                .disabled(assistant.isThinking)

                // Stop speaking
                if assistant.isSpeaking {
                    Button {
                        assistant.stopSpeaking()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "speaker.slash.fill")
                                .font(.system(size: 16))
                            Text("MUTE")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(.orange)
                        .frame(width: 56, height: 44)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Shortcut hint
                Text("⌥ SPACE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(6)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func submitManual() {
        let text = manualInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        manualInput = ""
        Task { await assistant.sendTyped(text) }
    }
}

// MARK: - Orb Window Manager

@MainActor
final class VYBEAssistantWindow {
    static let shared = VYBEAssistantWindow()
    private var window: NSWindow?
    private init() {}

    func toggleAndListen() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let orbView = AIOrb().environmentObject(VYBEAssistant.shared)
            let host = NSHostingView(rootView: orbView)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
                styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "VYBE AI"
            panel.minSize = NSSize(width: 320, height: 400)
            panel.isReleasedWhenClosed = false
            panel.center()
            panel.contentView = host
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.backgroundColor = NSColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1.0)
            window = panel
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }

        if VYBEAssistant.shared.isListening {
            VYBEAssistant.shared.finishRecognitionAndAsk()
        } else {
            VYBEAssistant.shared.startListening()
        }
    }

    func showWithoutListening() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        toggleAndListen()
        VYBEAssistant.shared.stopListening()
    }
}
