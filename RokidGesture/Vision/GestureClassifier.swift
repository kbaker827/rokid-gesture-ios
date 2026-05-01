import Foundation
import CoreGraphics
import Vision

/// Pure static classifier — takes HandPoints, returns GestureType.
/// Geometry is done entirely in Vision normalized space (0,0=bottom-left, y-up).
struct GestureClassifier {

    // MARK: - Public classify

    func classify(_ pts: HandPoints) -> GestureType {
        guard let wrist = pts[.wrist] else { return .none }

        let indexExt  = extended(tip: .indexTip,  mcp: .indexMCP,  pts: pts, wrist: wrist)
        let middleExt = extended(tip: .middleTip, mcp: .middleMCP, pts: pts, wrist: wrist)
        let ringExt   = extended(tip: .ringTip,   mcp: .ringMCP,   pts: pts, wrist: wrist)
        let littleExt = extended(tip: .littleTip, mcp: .littleMCP, pts: pts, wrist: wrist)
        let thumbOut  = thumbExtended(pts: pts, wrist: wrist)

        // Open palm — all four fingers extended
        if indexExt && middleExt && ringExt && littleExt { return .openPalm }

        // Peace / V sign — index + middle, ring + little curled
        if indexExt && middleExt && !ringExt && !littleExt { return .peaceSign }

        // Point — index only
        if indexExt && !middleExt && !ringExt && !littleExt { return .pointOne }

        // Thumb gestures — no fingers extended but thumb is out
        if !indexExt && !middleExt && !ringExt && !littleExt && thumbOut {
            guard let tip = pts[.thumbTip], let mp = pts[.thumbMP] else { return .thumbsUp }
            // In Vision space y increases upward, so tip above mp = thumbs up
            return tip.y > mp.y ? .thumbsUp : .thumbsDown
        }

        // Fist — nothing extended
        if !indexExt && !middleExt && !ringExt && !littleExt && !thumbOut { return .fist }

        return .none
    }

    // MARK: - Private geometry

    /// A finger is extended when its tip is significantly farther from the wrist than its MCP.
    private func extended(tip: JointName, mcp: JointName,
                          pts: HandPoints, wrist: CGPoint) -> Bool {
        guard let tipPt = pts[tip], let mcpPt = pts[mcp] else { return false }
        let tipD = dist(tipPt, wrist)
        let mcpD = dist(mcpPt, wrist)
        return mcpD > 0.001 && (tipD / mcpD) > 1.35
    }

    /// Thumb is extended (abducted) when its tip is farther from the wrist than the CMC.
    private func thumbExtended(pts: HandPoints, wrist: CGPoint) -> Bool {
        guard let tip = pts[.thumbTip], let cmc = pts[.thumbCMC] else { return false }
        return dist(cmc, wrist) > 0.001 && dist(tip, wrist) / dist(cmc, wrist) > 1.15
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x; let dy = a.y - b.y
        return sqrt(dx*dx + dy*dy)
    }
}

// MARK: - Bone paths for skeleton overlay

extension GestureClassifier {
    /// Chains of joints to connect with lines when drawing the hand skeleton.
    static let bonePaths: [[JointName]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
        [.indexMCP, .middleMCP, .ringMCP, .littleMCP],   // palm arc
    ]

    /// Tip joints highlighted in a contrasting colour
    static let tipJoints: [JointName] = [
        .thumbTip, .indexTip, .middleTip, .ringTip, .littleTip
    ]
}
