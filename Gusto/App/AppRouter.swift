import Observation
import SwiftUI

enum AppTab: String, CaseIterable { case discover, map, scan, messages, you }
enum ProfilePanel: String {
    case impact, referrals, alerts, listings, purchases, saved, payment, verification, settings
}
enum AppSheet {
    case listing(String)
    case cart, filters, location
    case collection(String, [String])
    case chat(String)
    case run
    case scanCamera, scanReview, sensor
    case scanItem(String)
    case profile(ProfilePanel)
}
@MainActor @Observable final class AppRouter {
    var tab: AppTab = .discover
    var sheet: AppSheet?
    var previousSheet: AppSheet?
    func chat(_ seller: String) {
        previousSheet = sheet
        sheet = .chat(seller)
    }
    func backFromChat() {
        sheet = previousSheet
        previousSheet = nil
    }
}
