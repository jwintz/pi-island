//
//  PiLogo.swift
//  PiIsland
//
//  Pi logo as a SwiftUI Shape
//

import SwiftUI

/// Pi logo shape - a stylized "Pi" mark
struct PiLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Scale to fit the rect (original viewBox is 800x800)
        let scale = min(rect.width, rect.height) / 800
        let offsetX = (rect.width - 800 * scale) / 2
        let offsetY = (rect.height - 800 * scale) / 2
        
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: offsetX + x * scale, y: offsetY + y * scale)
        }
        
        // P shape outer boundary (clockwise)
        path.move(to: point(165.29, 165.29))
        path.addLine(to: point(517.36, 165.29))
        path.addLine(to: point(517.36, 400))
        path.addLine(to: point(400, 400))
        path.addLine(to: point(400, 517.36))
        path.addLine(to: point(282.65, 517.36))
        path.addLine(to: point(282.65, 634.72))
        path.addLine(to: point(165.29, 634.72))
        path.closeSubpath()
        
        // P shape inner hole (counter-clockwise for even-odd fill)
        path.move(to: point(282.65, 282.65))
        path.addLine(to: point(282.65, 400))
        path.addLine(to: point(400, 400))
        path.addLine(to: point(400, 282.65))
        path.closeSubpath()
        
        // i dot
        path.move(to: point(517.36, 400))
        path.addLine(to: point(634.72, 400))
        path.addLine(to: point(634.72, 634.72))
        path.addLine(to: point(517.36, 634.72))
        path.closeSubpath()
        
        return path
    }
}

/// Pi logo view with optional animation
struct PiLogo: View {
    let size: CGFloat
    var isAnimating: Bool = false
    var color: Color = .white
    
    var body: some View {
        PiLogoShape()
            .fill(color.opacity(isAnimating ? 1.0 : 0.6), style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
            .scaleEffect(isAnimating ? 1.1 : 1.0)
            .animation(
                isAnimating 
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) 
                    : .default, 
                value: isAnimating
            )
    }
}

#Preview {
    VStack(spacing: 20) {
        PiLogo(size: 64, isAnimating: false)
        PiLogo(size: 64, isAnimating: true)
        PiLogo(size: 32)
        PiLogo(size: 16)
    }
    .padding()
    .background(Color.black)
}
