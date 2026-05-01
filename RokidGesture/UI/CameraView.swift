import SwiftUI
import AVFoundation
import Vision

struct CameraView: View {
    @EnvironmentObject private var vm: GestureViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                // Camera preview
                CameraPreviewView(session: vm.detector.session)
                    .ignoresSafeArea()

                // Hand skeleton overlay
                if let pts = vm.detector.handPoints {
                    HandSkeletonOverlay(points: pts,
                                        gesture: vm.currentGesture,
                                        isFront: vm.detector.cameraFront)
                        .ignoresSafeArea()
                }

                // Gesture badge (bottom centre)
                VStack {
                    Spacer()
                    gestureBadge
                        .padding(.bottom, 100)
                }

                // "No hand detected" hint
                if vm.detector.handPoints == nil && vm.isDetecting {
                    VStack {
                        Image(systemName: "hand.raised.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.white.opacity(0.5))
                        Text("Hold your hand up")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .navigationTitle("Gesture Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black.opacity(0.7), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading)  { glassesStatus }
                ToolbarItem(placement: .navigationBarTrailing) { cameraControls }
            }
            .onAppear  { if !vm.isDetecting { vm.startDetection() } }
            .onDisappear { vm.stopDetection() }
        }
    }

    // MARK: - Gesture badge

    private var gestureBadge: some View {
        VStack(spacing: 6) {
            if vm.currentGesture != .none {
                Text(vm.currentGesture.emoji)
                    .font(.system(size: 48))
                    .transition(.scale.combined(with: .opacity))
            }
            if !vm.lastFiredGesture.isEmpty {
                Text(vm.lastFiredGesture)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: vm.currentGesture)
        .animation(.spring(duration: 0.3), value: vm.lastFiredGesture)
    }

    // MARK: - Toolbar

    private var glassesStatus: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(vm.glassesServer.isRunning ? .cyan : Color(white: 0.4))
                .frame(width: 7, height: 7)
            Text("\(vm.glassesServer.clientCount) glasses")
                .font(.caption)
                .foregroundStyle(.cyan.opacity(vm.glassesServer.isRunning ? 1 : 0.5))
        }
    }

    private var cameraControls: some View {
        HStack(spacing: 14) {
            // Start/stop detection
            Button {
                if vm.isDetecting { vm.stopDetection() } else { vm.startDetection() }
            } label: {
                Image(systemName: vm.isDetecting ? "stop.circle" : "play.circle")
                    .font(.title3)
                    .foregroundStyle(vm.isDetecting ? .red : .green)
            }

            // Flip camera
            Button {
                vm.detector.switchCamera()
            } label: {
                Image(systemName: "camera.rotate")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Camera preview (UIViewRepresentable)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session      = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

// MARK: - Hand skeleton overlay

struct HandSkeletonOverlay: View {
    let points:  HandPoints
    let gesture: GestureType
    let isFront: Bool

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // Bone lines
                for chain in GestureClassifier.bonePaths {
                    drawChain(chain, ctx: &ctx, size: size)
                }
                // All joints
                for (name, pt) in points.allPoints {
                    let isTip = GestureClassifier.tipJoints.contains(name)
                    let vp = viewPoint(pt, size: size)
                    let r: CGFloat = isTip ? 6 : 4
                    let colour: Color = isTip ? tipColour : .white.opacity(0.7)
                    ctx.fill(Path(ellipseIn: CGRect(x: vp.x - r, y: vp.y - r,
                                                    width: r*2, height: r*2)),
                             with: .color(colour))
                }
            }
        }
    }

    private var tipColour: Color {
        switch gesture {
        case .openPalm:   return .green
        case .fist:       return .red
        case .pointOne:   return .cyan
        case .peaceSign:  return .yellow
        case .thumbsUp:   return .green
        case .thumbsDown: return .orange
        case .none:       return .white
        }
    }

    private func drawChain(_ chain: [JointName], ctx: inout GraphicsContext, size: CGSize) {
        let vpts = chain.compactMap { points[$0].map { viewPoint($0, size: size) } }
        guard vpts.count >= 2 else { return }
        var path = Path()
        path.move(to: vpts[0])
        for pt in vpts.dropFirst() { path.addLine(to: pt) }
        ctx.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 2)
    }

    /// Convert Vision normalized point (0,0=bottom-left, y-up) to SwiftUI view coordinates.
    /// Since we set `isVideoMirrored = true` for front camera, x is already display-correct.
    private func viewPoint(_ vp: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: vp.x * size.width,
                y: (1.0 - vp.y) * size.height)
    }
}
