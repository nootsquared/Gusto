import SwiftUI
import UIKit

enum Theme {
    static let ivory = Color("Ivory"), paper = Color("Paper"), bone = Color("Bone")
    static let ink = Color("Ink"), secondary = Color("Ink2"), muted = Color("Ink3"),
        line = Color("Line")
    static let sage = Color("Sage"), deep = Color("SageDeep"), soft = Color("SageSoft"),
        save = Color("Save")
    static let apricot = Color("Apricot"), apricotSoft = Color("ApricotSoft")
    static let coral = Color("Coral"), coralSoft = Color("CoralSoft")
    static let butter = Color("Butter"), butterSoft = Color("ButterSoft")
    static var spring: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.3, dampingFraction: 0.82)
    }

    static func configureTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "Paper")
        appearance.shadowColor = UIColor(named: "Line")
        for layout in [
            appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ] {
            layout.normal.iconColor = UIColor(named: "Ink2")
            layout.selected.iconColor = UIColor(named: "Save")
            layout.normal.titleTextAttributes = [
                .foregroundColor: UIColor(named: "Ink2") ?? .secondaryLabel,
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            ]
            layout.selected.titleTextAttributes = [
                .foregroundColor: UIColor(named: "Save") ?? .label,
                .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            ]
            layout.normal.badgeBackgroundColor = UIColor(named: "Apricot")
            layout.selected.badgeBackgroundColor = UIColor(named: "Apricot")
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

private struct GustoFont: ViewModifier {
    @ScaledMetric(relativeTo: .body) var size: CGFloat = 17
    let weight: Font.Weight
    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
    }
    func body(content: Content) -> some View {
        let readableWeight: Font.Weight =
            size >= 20 && weight == .semibold
            ? .bold : size <= 15 && weight == .regular ? .medium : weight
        content.font(.system(size: max(size, 12), weight: readableWeight))
    }
}

extension View {
    func gustoFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        modifier(GustoFont(size: size, weight: weight))
    }
    func card(radius: CGFloat = 20, color: Color = Theme.paper) -> some View {
        background(color, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.line, lineWidth: 1))
    }
    func sheetStyle() -> some View {
        presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
            .presentationBackground(Theme.ivory)
    }
}

enum Haptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// Render custom artwork into tab images so native TabView preserves its styling.
enum NavigationArtwork {
    enum Icon { case discover, map, scan, messages, profile }

    static func accountIcon(_ image: UIImage?, name: String, selected: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { renderer in
            let bounds = CGRect(x: 3, y: 2, width: 26, height: 26)
            let context = renderer.cgContext
            context.saveGState()
            UIBezierPath(ovalIn: bounds).addClip()
            if let image {
                let scale = max(26 / image.size.width, 26 / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
            } else {
                (UIColor(named: "Save") ?? .systemGreen).setFill()
                context.fill(bounds)
                let letter = String(name.prefix(1)).uppercased() as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: UIColor.white]
                let size = letter.size(withAttributes: attributes)
                letter.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
            }
            context.restoreGState()
            if selected {
                (UIColor(named: "Save") ?? .systemGreen).setStroke()
                let ring = UIBezierPath(ovalIn: bounds.insetBy(dx: -2, dy: -2))
                ring.lineWidth = 1.5
                ring.stroke()
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    static func tabIcon(_ icon: Icon, selected: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { renderer in
            let context = renderer.cgContext
            if selected {
                (UIColor(named: "Save") ?? .systemGreen).setFill()
                UIBezierPath(roundedRect: CGRect(x: 10, y: 29, width: 12, height: 2),
                             cornerRadius: 1).fill()
            }
            (UIColor(named: selected ? "Save" : "Ink2") ?? .darkGray).setStroke()
            context.setLineWidth(selected ? 1.9 : 1.65)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            func stroke(_ path: UIBezierPath) {
                context.addPath(path.cgPath)
                context.strokePath()
            }
            func line(_ points: [CGPoint]) {
                let path = UIBezierPath()
                if let first = points.first { path.move(to: first) }
                for point in points.dropFirst() { path.addLine(to: point) }
                stroke(path)
            }

            switch icon {
            case .discover:
                for (x, y) in [(7.0, 7.0), (18.0, 7.0), (7.0, 18.0), (18.0, 18.0)] {
                    stroke(UIBezierPath(roundedRect: CGRect(x: x, y: y, width: 7, height: 7),
                                        cornerRadius: 2.5))
                }
            case .map:
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 16, y: 26))
                path.addCurve(to: CGPoint(x: 8, y: 14),
                              controlPoint1: CGPoint(x: 12, y: 22),
                              controlPoint2: CGPoint(x: 8, y: 18))
                path.addArc(withCenter: CGPoint(x: 16, y: 14), radius: 8,
                            startAngle: .pi, endAngle: 0, clockwise: true)
                path.addCurve(to: CGPoint(x: 16, y: 26),
                              controlPoint1: CGPoint(x: 24, y: 18),
                              controlPoint2: CGPoint(x: 20, y: 22))
                stroke(path)
                stroke(UIBezierPath(ovalIn: CGRect(x: 13, y: 11, width: 6, height: 6)))
            case .scan:
                stroke(UIBezierPath(roundedRect: CGRect(x: 5, y: 10, width: 22, height: 15), cornerRadius: 4))
                stroke(UIBezierPath(ovalIn: CGRect(x: 12, y: 13, width: 8, height: 8)))
                line([CGPoint(x: 11, y: 10), CGPoint(x: 13, y: 7), CGPoint(x: 19, y: 7), CGPoint(x: 21, y: 10)])
            case .messages:
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 11, y: 23))
                path.addLine(to: CGPoint(x: 7, y: 26))
                path.addLine(to: CGPoint(x: 7, y: 12))
                path.addQuadCurve(to: CGPoint(x: 12, y: 7),
                                  controlPoint: CGPoint(x: 7, y: 7))
                path.addLine(to: CGPoint(x: 21, y: 7))
                path.addQuadCurve(to: CGPoint(x: 26, y: 12),
                                  controlPoint: CGPoint(x: 26, y: 7))
                path.addLine(to: CGPoint(x: 26, y: 18))
                path.addQuadCurve(to: CGPoint(x: 21, y: 23),
                                  controlPoint: CGPoint(x: 26, y: 23))
                path.close()
                stroke(path)
                line([CGPoint(x: 12, y: 13), CGPoint(x: 21, y: 13)])
                line([CGPoint(x: 12, y: 17), CGPoint(x: 18, y: 17)])
            case .profile:
                stroke(UIBezierPath(ovalIn: CGRect(x: 12, y: 6, width: 8, height: 8)))
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 7, y: 26))
                path.addLine(to: CGPoint(x: 7, y: 24))
                path.addCurve(to: CGPoint(x: 25, y: 24),
                              controlPoint1: CGPoint(x: 7, y: 14),
                              controlPoint2: CGPoint(x: 25, y: 14))
                path.addLine(to: CGPoint(x: 25, y: 26))
                stroke(path)
            }
        }.withRenderingMode(.alwaysOriginal)
    }
}
