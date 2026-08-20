import SwiftUI

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var opacity: Double
    let color: Color
    var rotation: Double
    var scale: CGFloat
    let shape: Int
}

struct ConfettiView: View {
    @Binding var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [ConfettiPiece] = []
    @State private var celebrationID = UUID()

    private let colors: [Color] = [
        Color(red: 0.96, green: 0.92, blue: 0.80),
        Color(red: 0.35, green: 0.33, blue: 0.29),
        Color(red: 1.00, green: 0.77, blue: 0.38),
        Color(red: 0.98, green: 0.43, blue: 0.58),
        Color(red: 0.26, green: 0.78, blue: 0.68),
        Color(red: 0.33, green: 0.66, blue: 0.95)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(pieces) { piece in
                    Group {
                        switch piece.shape {
                        case 0:
                            Circle().fill(piece.color)
                        case 1:
                            Capsule().fill(piece.color)
                        default:
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(piece.color)
                        }
                    }
                        .frame(width: 10 * piece.scale, height: 7 * piece.scale)
                        .rotationEffect(.degrees(piece.rotation))
                        .opacity(piece.opacity)
                        .position(x: piece.x, y: piece.y)
                }
            }
            .onChange(of: isActive) { active in
                guard active else { return }
                celebrate(in: geometry.size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func celebrate(in size: CGSize) {
        let token = UUID()
        celebrationID = token
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let count = reduceMotion ? 36 : 110

        pieces = (0..<count).map { _ in
            ConfettiPiece(
                x: center.x,
                y: center.y,
                opacity: 1,
                color: colors.randomElement() ?? colors[0],
                rotation: .random(in: 0...360),
                scale: .random(in: 0.75...1.65),
                shape: .random(in: 0...2)
            )
        }

        for index in pieces.indices {
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = reduceMotion ? CGFloat.random(in: 45...100) : CGFloat.random(in: 280...720)
            let targetX = center.x + cos(angle) * distance
            let targetY = center.y + sin(angle) * distance
            let duration = reduceMotion ? 0.35 : Double.random(in: 1.35...2.35)
            let delay = reduceMotion ? 0 : Double.random(in: 0...0.08)

            withAnimation(.easeOut(duration: duration).delay(delay)) {
                pieces[index].x = targetX
                pieces[index].y = targetY
                pieces[index].rotation += reduceMotion ? 0 : Double.random(in: 540...1080)
                pieces[index].scale *= reduceMotion ? 0.9 : CGFloat.random(in: 0.35...0.75)
                pieces[index].opacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.45 : 2.7)) {
            guard celebrationID == token else { return }
            pieces.removeAll()
            isActive = false
        }
    }
}
