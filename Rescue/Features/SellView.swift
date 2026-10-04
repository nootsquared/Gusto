import SwiftUI

private enum SellPhase { case camera, scanning, editing, published }
private enum PriceChoice: String, CaseIterable {
    case fast = "Sell Fast"
    case recommended = "Recommended"
    case custom = "Custom"
}

struct SellView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var phase: SellPhase = .camera
    @State private var name = "Maple Granola"
    @State private var freshness: Freshness = .fresh
    @State private var priceChoice: PriceChoice = .recommended
    @State private var customPrice = 300.0
    @State private var pickup = "Tonight 6–9"
    @State private var confirmations: Set<String> = []
    private let safety = [
        "Stored as labeled", "Date is accurate", "Condition as shown", "Allergens: oats, almonds",
    ]
    private var price: Int {
        priceChoice == .fast ? 200 : priceChoice == .recommended ? 300 : Int(customPrice)
    }
    var body: some View {
        Group {
            switch phase {
            case .camera, .scanning:
                ZStack {
                    FoodPhoto(name: "gran").ignoresSafeArea().overlay(.black.opacity(0.3))
                    VStack(spacing: 24) {
                        Text(phase == .camera ? "Take a photo" : "Reading label…").rescueFont(
                            17, .semibold
                        ).padding(12).background(.black.opacity(0.4), in: Capsule())
                        Spacer()
                        RoundedRectangle(cornerRadius: 22).stroke(
                            .white, style: StrokeStyle(lineWidth: 2, dash: [36, 70])
                        ).frame(height: 270).padding(.horizontal, 36)
                        Spacer()
                        Text(
                            phase == .camera
                                ? "Include the date label if there is one"
                                : "Demo scan · you confirm every detail"
                        ).rescueFont(14).multilineTextAlignment(.center)
                        if phase == .scanning {
                            ProgressView().tint(.white).frame(height: 78)
                        } else {
                            Button {
                                phase = .scanning
                                Haptic.tap()
                            } label: {
                                Circle().fill(.white).frame(width: 62, height: 62).padding(6)
                                    .overlay(Circle().stroke(.white, lineWidth: 4))
                            }.buttonStyle(.plain).accessibilityLabel("Take demo photo")
                                .accessibilityIdentifier("take-photo")
                        }
                        Text("Mock camera · no camera permission required").rescueFont(12)
                            .foregroundStyle(.white.opacity(0.7))
                    }.padding(.vertical, 24).foregroundStyle(.white)
                }.task(id: phase) {
                    if phase == .scanning {
                        do {
                            try await store.service.pause()
                            if !Task.isCancelled { phase = .editing }
                        } catch { phase = .camera }
                    }
                }
            case .editing:
                Form {
                    Section {
                        FoodPhoto(name: "gran").frame(height: 180).clipShape(
                            RoundedRectangle(cornerRadius: 18))
                        Text("Autofilled · tap to edit").font(.caption).foregroundStyle(
                            Theme.apricot)
                    }
                    Section("Item") {
                        TextField("Name", text: $name).accessibilityIdentifier("sell-name")
                        Text("Breakfast · sealed · 12 oz · best by Nov 18")
                    }
                    Section("Freshness") {
                        Picker("Condition", selection: $freshness) {
                            ForEach(Freshness.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    Section("Price") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Money.text(price)).rescueFont(44, .bold)
                            Text("You give someone \(Int((1 - Double(price) / 899) * 100))% off")
                                .rescueFont(15)
                            Text("Demo estimate · retail $8.99").rescueFont(13).foregroundStyle(
                                Theme.paper.opacity(0.6))
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                            .foregroundStyle(Theme.paper).background(
                                Theme.deep, in: RoundedRectangle(cornerRadius: 20))
                        Picker("Price", selection: $priceChoice) {
                            ForEach(PriceChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        if priceChoice == .custom {
                            Slider(value: $customPrice, in: 50...800, step: 25)
                        }
                    }
                    Section("Pickup") {
                        Picker("Pickup window", selection: $pickup) {
                            ForEach(
                                ["Now–8 PM", "Tonight 6–9", "Tomorrow AM", "Tomorrow PM"],
                                id: \.self
                            ) { Text($0).tag($0) }
                        }
                        Text("Buyers see an approximate area until pickup.").font(.footnote)
                    }
                    Section("Safety") {
                        ForEach(safety, id: \.self) { value in
                            Toggle(
                                value,
                                isOn: Binding(
                                    get: { confirmations.contains(value) },
                                    set: {
                                        if $0 {
                                            confirmations.insert(value)
                                        } else {
                                            confirmations.remove(value)
                                        }
                                    }))
                        }
                        Button("Confirm all") { confirmations = Set(safety) }
                            .accessibilityIdentifier("confirm-safety")
                    }
                }.scrollContentBackground(.hidden).background(Theme.ivory).tint(Theme.sage)
                    .safeAreaInset(edge: .bottom) {
                        BottomAction {
                            PrimaryButton(
                                title: "List for \(Money.text(price))",
                                disabled: confirmations.count != 4
                                    || name.trimmingCharacters(in: .whitespaces).isEmpty,
                                id: "publish-listing"
                            ) {
                                if store.publish(
                                    name: name, price: price, freshness: freshness, pickup: pickup,
                                    confirmations: confirmations.count)
                                {
                                    phase = .published
                                    Haptic.success()
                                }
                            }
                        }
                    }
            case .published:
                VStack(spacing: 18) {
                    FoodPhoto(name: "gran").frame(width: 250, height: 200).clipShape(
                        RoundedRectangle(cornerRadius: 24)
                    ).padding(.top, 20)
                    Text(name).rescueFont(22, .semibold)
                    Text(Money.text(price)).rescueFont(26, .semibold).foregroundStyle(Theme.save)
                    Image(systemName: "checkmark.circle.fill").rescueFont(44).foregroundStyle(
                        Theme.sage)
                    Text("You're live").rescueFont(30, .bold).accessibilityIdentifier("published")
                    Text("Listed in your local demo catalog").rescueFont(15).foregroundStyle(
                        Theme.secondary)
                    Text("No listing was sent to a server.").rescueFont(13).foregroundStyle(
                        Theme.muted)
                    Spacer()
                    PrimaryButton(title: "List another") {
                        phase = .camera
                        confirmations = []
                    }
                    Button("Done") { router.tab = .discover }.padding()
                }.padding(24).background(Theme.ivory)
            }
        }.navigationTitle("Sell").navigationBarTitleDisplayMode(.inline).foregroundStyle(Theme.ink)
    }
}
