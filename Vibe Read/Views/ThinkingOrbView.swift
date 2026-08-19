import SwiftUI

/// A native, monochrome port of the "working" state from Thinking Orbs.
/// See THIRD_PARTY_NOTICES.md for attribution and license details.
struct ThinkingOrbView: View {
    var size: CGFloat = 20

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: true) { context, canvasSize in
                let time = reduceMotion
                    ? 0.85
                    : timeline.date.timeIntervalSinceReferenceDate
                drawParticles(in: &context, size: canvasSize, time: time)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Processing dictation")
        .allowsHitTesting(false)
    }

    private func drawParticles(
        in context: inout GraphicsContext,
        size canvasSize: CGSize,
        time: TimeInterval
    ) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let drawingSize = Double(min(canvasSize.width, canvasSize.height))
        let sphereRadius = (drawingSize / 2) * 0.82
        let radiusScale = pow(drawingSize / 300, 0.6)

        // Thinking Orbs tunes its inline working preset with three orbit
        // planes, ten ghost-path dots, and three runners on each plane.
        let frameTime = time * 3.9
        let yaw = frameTime * 0.12
        var dots: [OrbDot] = []
        dots.reserveCapacity(39)

        for orbitIndex in 0..<3 {
            let orbit = Double(orbitIndex)
            let h1 = deterministicHash(orbit, 1.7)
            let h2 = deterministicHash(orbit, 5.2)
            let h3 = deterministicHash(orbit, 8.9)
            let orbitRadius = sphereRadius * (0.45 + (0.52 * h1))
            let theta = h1 * 2 * Double.pi
            let phi = acos((2 * h2) - 1)

            let normalX = sin(phi) * cos(theta)
            let normalY = cos(phi)
            let normalZ = sin(phi) * sin(theta)
            var basisUX = -normalY
            var basisUY = normalX
            let basisUZ = 0.0
            let basisLength = max(0.000001, hypot(basisUX, basisUY))
            basisUX /= basisLength
            basisUY /= basisLength

            let basisVX = (normalY * basisUZ) - (normalZ * basisUY)
            let basisVY = (normalZ * basisUX) - (normalX * basisUZ)
            let basisVZ = (normalX * basisUY) - (normalY * basisUX)
            let direction = h3 > 0.5 ? 1.0 : -1.0
            let runnerSpeed = (0.25 + (0.55 * h3)) * direction

            for index in 0..<10 {
                let angle = (Double(index) / 10) * 2 * Double.pi
                let projected = project(
                    x: (basisUX * cos(angle) + basisVX * sin(angle)) * orbitRadius,
                    y: (basisUY * cos(angle) + basisVY * sin(angle)) * orbitRadius,
                    z: (basisUZ * cos(angle) + basisVZ * sin(angle)) * orbitRadius,
                    yaw: yaw,
                    tilt: 0.3,
                    center: center
                )
                let depth = ((projected.depth / orbitRadius) + 1) / 2
                let pathAlpha = 0.5 * (0.4 + (0.6 * depth))
                dots.append(
                    OrbDot(
                        point: projected.point,
                        depth: projected.depth,
                        radius: max(0.3, 2.16 * radiusScale),
                        opacity: 0.28 * pathAlpha
                    )
                )
            }

            for runnerIndex in 0..<3 {
                let angle = (frameTime * runnerSpeed)
                    + (Double(runnerIndex) / 3 * 2 * Double.pi)
                    + (h2 * 6)
                let projected = project(
                    x: (basisUX * cos(angle) + basisVX * sin(angle)) * orbitRadius,
                    y: (basisUY * cos(angle) + basisVY * sin(angle)) * orbitRadius,
                    z: (basisUZ * cos(angle) + basisVZ * sin(angle)) * orbitRadius,
                    yaw: yaw,
                    tilt: 0.3,
                    center: center
                )
                let depth = ((projected.depth / orbitRadius) + 1) / 2
                dots.append(
                    OrbDot(
                        point: projected.point,
                        depth: projected.depth,
                        radius: max(0.3, (2.88 + (3.84 * depth)) * radiusScale),
                        opacity: 0.70 + (0.22 * depth)
                    )
                )
            }
        }

        // Back-to-front painting carries depth through dot scale and ink only.
        for dot in dots.sorted(by: { $0.depth < $1.depth }) {
            let radius = CGFloat(dot.radius)
            let diameter = radius * 2
            let rect = CGRect(
                x: dot.point.x - radius,
                y: dot.point.y - radius,
                width: diameter,
                height: diameter
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(Color.primary.opacity(dot.opacity))
            )
        }
    }
}

private func deterministicHash(_ a: Double, _ b: Double) -> Double {
    let value = sin((a * 12.9898) + (b * 78.233)) * 43_758.5453
    return value - floor(value)
}

private func project(
    x: Double,
    y: Double,
    z: Double,
    yaw: Double,
    tilt: Double,
    center: CGPoint
) -> (point: CGPoint, depth: Double) {
    let sineTilt = sin(tilt)
    let cosineTilt = cos(tilt)
    let sineYaw = sin(yaw)
    let cosineYaw = cos(yaw)
    let rotatedX = (x * cosineYaw) + (z * sineYaw)
    let firstDepth = (-x * sineYaw) + (z * cosineYaw)
    let rotatedY = (y * cosineTilt) - (firstDepth * sineTilt)
    let finalDepth = (y * sineTilt) + (firstDepth * cosineTilt)
    return (
        CGPoint(
            x: center.x + CGFloat(rotatedX),
            y: center.y - CGFloat(rotatedY)
        ),
        finalDepth
    )
}

private struct OrbDot {
    let point: CGPoint
    let depth: Double
    let radius: Double
    let opacity: Double
}
