import SwiftUI

@main struct RescueApp: App {
    init() { Theme.configureTabBar() }
    @State private var store = AppStore(
        service: DemoService(
            delayNanoseconds: ProcessInfo.processInfo.arguments.contains("--uitesting")
                ? 50_000_000 : 700_000_000),
        fixtureMode: ProcessInfo.processInfo.arguments.contains("--fixture")
            || (ProcessInfo.processInfo.arguments.contains("--uitesting")
                && !ProcessInfo.processInfo.arguments.contains("--backend"))
    )
    @State private var router = AppRouter()
    @State private var location = LocationController()
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).environment(router).environment(location).preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @Environment(LocationController.self) private var location
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showFinale = false
    @State private var welcomePreviewDismissed = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack { DiscoverView() }.tabItem {
                Label("Discover", systemImage: "safari").environment(\.symbolVariants, .none)
            }
            .tag(AppTab.discover)
            NavigationStack { MarketplaceMapView() }.tabItem {
                Label("Map", systemImage: "map").environment(\.symbolVariants, .none)
            }
            .tag(AppTab.map)
            NavigationStack { SellView() }.tabItem {
                Label {
                    Text("Sell")
                } icon: {
                    Image(uiImage: NavigationArtwork.sell).renderingMode(.original)
                }
            }.tag(AppTab.sell)
            NavigationStack { MessagesView() }.tabItem {
                Label("Messages", systemImage: "bubble.left.and.bubble.right").environment(
                    \.symbolVariants, .none)
            }.tag(AppTab.messages)
            NavigationStack { ProfileView() }.tabItem {
                Label {
                    Text("You")
                } icon: {
                    Image(
                        uiImage: router.tab == .you
                            ? NavigationArtwork.selectedProfile : NavigationArtwork.profile
                    )
                    .renderingMode(.original)
                }
            }.tag(
                AppTab.you)
        }.task {
            let args = ProcessInfo.processInfo.arguments
            if !args.contains("--fixture")
                && (!args.contains("--uitesting") || args.contains("--backend"))
            {
                store.enterBackendMode()
                do {
                    if SessionController.shared.isLocalBackend && SessionController.shared.current == nil {
                        try await SessionController.shared.loadDemoAccounts()
                    }
                    #if DEBUG
                        if let index = args.firstIndex(of: "--account"),
                            args.indices.contains(index + 1)
                        {
                            try SessionController.shared.select(args[index + 1])
                        }
                    #endif
                    if SessionController.shared.isLocalBackend {
                        await store.connect(try SessionController.shared.repository())
                    }
                } catch {
                    NSLog("Rescue session setup failed: %@", error.localizedDescription)
                    store.notice = error.localizedDescription
                }
            }
        }.task(id: SessionController.shared.current?.userId) {
            guard store.isBackend, !SessionController.shared.isLocalBackend else { return }
            guard SessionController.shared.current != nil else { store.disconnectBackend(); return }
            do {
                _ = try await SessionController.shared.currentSession()
                await store.connect(try SessionController.shared.repository())
            } catch { store.notice = error.localizedDescription }
        }.overlay {
            if store.isBackend && !SessionController.shared.isLocalBackend
                && SessionController.shared.current == nil
            {
                WelcomeView(
                    signingIn: SessionController.shared.signingIn,
                    error: SessionController.shared.authError
                ) {
                    Task { await SessionController.shared.signIn() }
                }
            }
        }.overlay {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--welcome-preview") && !welcomePreviewDismissed {
                    WelcomeView { welcomePreviewDismissed = true }
                }
            #endif
        }.task(id: "\(scenePhase)-\(store.isBackend)-\(store.accountID)") {
            if scenePhase == .active { await store.pollBackend() }
        }.tint(Theme.ink).background(Theme.ivory.ignoresSafeArea())
            .toolbarBackground(Theme.paper, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if store.runActive {
                    Button {
                        router.sheet = .run
                    } label: {
                        LivePickupCard()
                    }.buttonStyle(.plain).accessibilityIdentifier("active-run").padding(
                        .horizontal, 12
                    ).padding(.vertical, 6).background(Theme.ivory)
                }
            }
            .overlay(alignment: .top) {
                if let notice = store.notice {
                    Text(notice).rescueFont(14, .medium).foregroundStyle(Theme.paper).padding(14)
                        .frame(maxWidth: .infinity).background(
                            Theme.ink.opacity(0.96), in: RoundedRectangle(cornerRadius: 20)
                        ).padding(.horizontal, 16)
                        .allowsHitTesting(false).transition(
                            .move(edge: .top).combined(with: .opacity)
                        )
                        .task(id: notice) {
                            try? await Task.sleep(nanoseconds: 2_600_000_000)
                            if !Task.isCancelled && store.notice == notice {
                                withAnimation(Theme.spring) { store.notice = nil }
                            }
                        }
                }
            }
            .animation(reduceMotion ? nil : Theme.spring, value: store.notice)
            .sheet(
                isPresented: Binding(
                    get: { router.sheet != nil }, set: { if !$0 { router.sheet = nil } })
            ) {
                SheetHost().environment(store).environment(router).sheetStyle().presentationDetents(
                    sheetDetents)
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    hasOnboarded = true
                    showOnboarding = false
                }
            }
            .fullScreenCover(isPresented: $showFinale) {
                FinaleView {
                    store.finishRun()
                    router.tab = .you
                    showFinale = false
                }
            }
            .onAppear {
                showOnboarding =
                    !hasOnboarded && !ProcessInfo.processInfo.arguments.contains("--uitesting")
            }
            .onChange(of: store.online) { _, online in
                if online && !ProcessInfo.processInfo.arguments.contains("--uitesting") {
                    location.requestInitially()
                }
            }
            .onChange(of: location.selection, initial: true) { _, selection in
                if let selection, !ProcessInfo.processInfo.arguments.contains("--uitesting") {
                    store.updateBrowseLocation(latitude: selection.latitude, longitude: selection.longitude)
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
                if phase == .active { location.resume() } else { location.pause() }
            }
            .onChange(of: store.phase) { previous, phase in
                if store.isBackend && previous == .idle && phase == .enroute {
                    router.tab = .map
                    router.sheet = nil
                }
                if phase == .finished {
                    router.sheet = nil
                    Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        showFinale = true
                    }
                }
            }
    }
    private var sheetDetents: Set<PresentationDetent> {
        switch router.sheet {
        case .listing: [.fraction(0.68), .large]
        case .cart: [.fraction(0.9), .large]
        case .run: [.large]
        case .filters: [.fraction(0.84), .large]
        default: [.large]
        }
    }
}

struct SheetHost: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        NavigationStack {
            Group {
                switch router.sheet {
                case .listing(let id): ListingDetailView(id: id)
                case .cart: CartView()
                case .filters: FiltersView()
                case .location: LocationPickerView()
                case .collection(let title, let ids): CollectionView(title: title, ids: ids)
                case .chat(let seller): ChatView(sellerID: seller)
                case .run: PickupFlowView()
                case .profile(let panel): ProfilePanelView(panel: panel)
                case nil: Color.clear
                }
            }.background(Theme.ivory).foregroundStyle(Theme.ink)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            router.sheet = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close").accessibilityIdentifier("close-sheet")
                    }
                }.toolbarBackground(Theme.ivory, for: .navigationBar).toolbarBackground(
                    .visible, for: .navigationBar)
        }.tint(Theme.ink)
    }
}

struct OnboardingView: View {
    let onDone: () -> Void
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                        spacing: 12
                    ) {
                        ForEach(MockCatalog.listings.prefix(9)) { item in
                            FoodPhoto(name: item.image).frame(height: 145).clipShape(
                                RoundedRectangle(cornerRadius: 22)
                            )
                            .overlay(alignment: .bottomLeading) {
                                Text(Money.text(item.price)).rescueFont(12, .bold).padding(6)
                                    .background(Theme.paper, in: Capsule()).padding(8)
                            }
                        }
                    }.rotationEffect(.degrees(-8)).padding(.horizontal, -15)
                    LinearGradient(
                        colors: [.clear, Theme.ivory], startPoint: .top, endPoint: .bottom
                    ).frame(height: 110)
                }.frame(height: geometry.size.height * 0.43).clipped()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gusto").rescueFont(15, .semibold).foregroundStyle(Theme.sage)
                    Text("Good food near you, for less, before it goes to waste.").rescueFont(
                        36, .bold
                    ).minimumScaleFactor(0.7)
                    Text(
                        "Neighbors list groceries they won't finish. You pick them up for up to 70% off."
                    ).rescueFont(16).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 12)
                    PrimaryButton(title: "Find food nearby", id: "begin-demo", action: onDone)
                    Text("Use your location or choose a neighborhood").rescueFont(12)
                        .foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                }.padding(28)
            }.frame(maxHeight: .infinity).background(Theme.ivory).foregroundStyle(Theme.ink)
        }
    }
}
