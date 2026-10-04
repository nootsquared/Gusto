import SwiftUI

/// The entry screen uses bundled artwork so it is complete before a network session exists.
struct WelcomeView: View {
    var signingIn = false
    var error: String?
    let signIn: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 47

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "leaf.fill").font(.system(size: 20))
                        Spacer()
                        Text("Gusto").font(.system(size: 30, weight: .semibold))
                            .tracking(-1.3)
                    }.foregroundStyle(Theme.deep).padding(.top, 16)

                    artwork
                        .frame(height: min(geometry.size.height * 0.39, 320))
                        .padding(.top, 20)

                    Text("Good food.\nBetter prices.")
                        .font(.system(size: min(headlineSize, 70), weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.deep).tracking(-1.5).lineSpacing(-1)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 32)
                        .accessibilityLabel("Welcome to Gusto. Good food. Better prices.")
                    Text("Buy and share food in your neighborhood.")
                        .font(.system(size: 16)).foregroundStyle(Theme.secondary)
                        .lineSpacing(4).padding(.top, 14)

                    Button {
                        Haptic.tap()
                        signIn()
                    } label: {
                        HStack(spacing: 12) {
                            if signingIn {
                                ProgressView().tint(Theme.paper)
                            } else {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 19, weight: .medium))
                            }
                            Text(signingIn ? "Opening Google…" : "Get started")
                                .font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Image(systemName: "arrow.right").font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Theme.butter.opacity(0.7))
                        }.foregroundStyle(Theme.paper).padding(.horizontal, 24)
                            .frame(height: 64)
                            .background(
                                LinearGradient(colors: [Theme.deep, Theme.sage],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 22))
                            .overlay(RoundedRectangle(cornerRadius: 22)
                                .stroke(.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: Theme.deep.opacity(0.2), radius: 16, y: 8)
                    }.buttonStyle(WelcomePressStyle()).disabled(signingIn)
                        .accessibilityLabel("Sign in with Google")
                        .accessibilityIdentifier("google-sign-in")
                        .padding(.top, 28)
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.system(size: 10))
                        Text("Continue securely with Google")
                            .font(.system(size: 12, weight: .medium))
                    }.foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
                        .padding(.top, 15)
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 12)
                    }

                }.padding(.horizontal, 28).padding(.bottom, 28)
                    .frame(minHeight: geometry.size.height, alignment: .top)
            }.background(Theme.ivory.ignoresSafeArea())
        }.background(Theme.ivory.ignoresSafeArea())
    }

    private var artwork: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                Circle().fill(Theme.soft).frame(width: width * 0.88)
                    .offset(x: 15, y: 4)
                Circle().stroke(Theme.sage.opacity(0.2), lineWidth: 1)
                    .frame(width: width * 0.97).offset(x: 15, y: 4)
                photo("straw", width: width * 0.49, height: width * 0.61)
                    .rotationEffect(.degrees(-14)).offset(x: -width * 0.23, y: 5)
                photo("avo", width: width * 0.50, height: width * 0.63)
                    .rotationEffect(.degrees(12)).offset(x: width * 0.20, y: -4)
                VStack(spacing: 4) {
                    Image(systemName: "leaf").font(.system(size: 22))
                    Text("perfectly\ngood.").font(.system(size: 18, weight: .medium, design: .serif))
                        .multilineTextAlignment(.center)
                }.foregroundStyle(Theme.deep).frame(width: 100, height: 100)
                    .background(Theme.butter, in: Circle())
                    .overlay(Circle().stroke(Theme.deep.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2, 3])).padding(6))
                    .rotationEffect(.degrees(-10)).offset(x: width * 0.25, y: width * 0.30)
                Image(systemName: "sparkle").font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.apricot).offset(x: -width * 0.34, y: -width * 0.34)

            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityHidden(true)
    }

    private func photo(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        FoodPhoto(name: name).frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 70))
            .padding(6).background(Theme.paper, in: RoundedRectangle(cornerRadius: 76))
            .shadow(color: Theme.deep.opacity(0.14), radius: 18, x: 0, y: 12)
    }
}

private struct WelcomePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
