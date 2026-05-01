import Foundation
import AVFoundation
import Vision

/// Manages AVCaptureSession and runs VNDetectHumanHandPoseRequest on each frame.
/// @Published properties are always updated on the main thread via Task { @MainActor }.
final class HandPoseDetector: NSObject, ObservableObject {

    // Published on main thread
    @Published var handPoints:  HandPoints? = nil
    @Published var isRunning:   Bool        = false
    @Published var cameraFront: Bool        = true

    /// Called on main thread after each Vision result
    var onHandPoints: ((HandPoints?) -> Void)?

    // AVFoundation — created once, accessed from captureQueue
    let session = AVCaptureSession()

    private let videoOutput  = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "HandPoseQ", qos: .userInteractive)
    private var currentInput: AVCaptureDeviceInput?

    // Frame-skipping (only touched on captureQueue)
    private var frameCounter = 0
    private let processEveryN = 2

    // MARK: - Permission

    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized { return true }
        return await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Setup

    func setup(front: Bool = true) {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480    // 480p — fast enough for hand pose

        if let old = currentInput { session.removeInput(old) }
        session.outputs.forEach { session.removeOutput($0) }

        let position: AVCaptureDevice.Position = front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration(); return
        }
        session.addInput(input)
        currentInput = input

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration(); return
        }
        session.addOutput(videoOutput)

        // Mirror the pixel buffer for the front camera so Vision coords match the preview display.
        if let conn = videoOutput.connection(with: .video), conn.isVideoMirroringSupported {
            conn.isVideoMirrored = front
        }

        session.commitConfiguration()

        DispatchQueue.main.async { [weak self] in
            self?.cameraFront = front
        }
    }

    // MARK: - Start / Stop

    func start() {
        guard !session.isRunning else { return }
        captureQueue.async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async { self?.isRunning = true }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        captureQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async {
                self?.isRunning  = false
                self?.handPoints = nil
            }
        }
    }

    func switchCamera() {
        let newFront = !cameraFront
        setup(front: newFront)
        if isRunning { start() }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension HandPoseDetector: AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Called on `captureQueue`. Vision runs synchronously here, then dispatches to main thread.
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Frame skipping — frameCounter only touched on captureQueue
        frameCounter += 1
        guard frameCounter % processEveryN == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Pixel buffer orientation: front camera mirrored → .leftMirrored; back portrait → .right
        let orientation: CGImagePropertyOrientation = connection.isVideoMirrored ? .leftMirrored : .right

        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        try? handler.perform([request])

        let pts = request.results?.first.flatMap(buildHandPoints)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.handPoints = pts
            self.onHandPoints?(pts)
        }
    }

    private func buildHandPoints(from obs: VNHumanHandPoseObservation) -> HandPoints? {
        guard let pts = try? obs.recognizedPoints(.all) else { return nil }
        var dict = [JointName: CGPoint]()
        for (name, pt) in pts where pt.confidence > 0.4 {
            dict[name] = pt.location
        }
        return dict.isEmpty ? nil : HandPoints(joints: dict)
    }
}
