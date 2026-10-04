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
    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight)) }
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
