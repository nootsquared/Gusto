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
            layout.selected.iconColor = UIColor(named: "Ink")
            layout.normal.titleTextAttributes = [
                .foregroundColor: UIColor(named: "Ink2") ?? .secondaryLabel,
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            ]
            layout.selected.titleTextAttributes = [
                .foregroundColor: UIColor(named: "Ink") ?? .label,
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            ]
            layout.normal.badgeBackgroundColor = UIColor(named: "Apricot")
            layout.selected.badgeBackgroundColor = UIColor(named: "Apricot")
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

private struct RescueFont: ViewModifier {
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
    func rescueFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        modifier(RescueFont(size: size, weight: weight))
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

// TabView extracts tab images; render the crop/background into the image itself.
enum NavigationArtwork {
    static let profile = profileImage(selected: false)
    static let selectedProfile = profileImage(selected: true)
    static let sell: UIImage = {
        let size = CGSize(width: 30, height: 30)
        return UIGraphicsImageRenderer(size: size).image { context in
            let circle = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            (UIColor(named: "SageSoft") ?? .systemGray6).setFill()
            context.cgContext.fillEllipse(in: circle)
            (UIColor(named: "SageDeep") ?? .darkGray).setStroke()
            context.cgContext.setLineWidth(1.8)
            context.cgContext.strokeEllipse(in: circle)
            let plus = UIImage(
                systemName: "plus",
                withConfiguration:
                    UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))?
                .withTintColor(
                    UIColor(named: "SageDeep") ?? .darkGray, renderingMode: .alwaysOriginal)
            if let plus {
                plus.draw(
                    in: CGRect(
                        x: (30 - plus.size.width) / 2,
                        y: (30 - plus.size.height) / 2,
                        width: plus.size.width, height: plus.size.height))
            }
        }.withRenderingMode(.alwaysOriginal)
    }()

    private static func profileImage(selected: Bool) -> UIImage {
        let size = CGSize(width: 30, height: 30)
        return UIGraphicsImageRenderer(size: size).image { context in
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            context.cgContext.saveGState()
            context.cgContext.addEllipse(in: bounds)
            context.cgContext.clip()
            if let photo = UIImage(named: "profile") {
                let scale = max(bounds.width / photo.size.width, bounds.height / photo.size.height)
                let width = photo.size.width * scale
                let height = photo.size.height * scale
                photo.draw(
                    in: CGRect(
                        x: bounds.midX - width / 2, y: bounds.midY - height / 2,
                        width: width, height: height))
            }
            context.cgContext.restoreGState()
            (UIColor(named: selected ? "SageDeep" : "Line") ?? .gray).setStroke()
            context.cgContext.setLineWidth(selected ? 2 : 1)
            context.cgContext.strokeEllipse(in: bounds)
        }.withRenderingMode(.alwaysOriginal)
    }
}
