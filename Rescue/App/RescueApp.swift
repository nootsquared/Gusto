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
    @State private var scanner = FoodScanController()
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).environment(router).environment(location).environment(
                scanner
            ).preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @Environment(FoodScanController.self) private var scanner
    @Environment(LocationController.self) private var location
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var showFinale = false
    @State private var welcomePreviewDismissed = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = false
    @State private var accountPhoto: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack { DiscoverView() }.tabItem {
                Label {
                    Text("Discover")
                } icon: {
                    Image(
                        uiImage: NavigationArtwork.tabIcon(
                            .discover, selected: router.tab == .discover)
                    )
                    .renderingMode(.original)
                }
            }
            .tag(AppTab.discover)
            NavigationStack { MarketplaceMapView() }.tabItem {
                Label {
                    Text("Map")
                } icon: {
                    Image(uiImage: NavigationArtwork.tabIcon(.map, selected: router.tab == .map))
                        .renderingMode(.original)
                }
            }
            .tag(AppTab.map)
            NavigationStack { ScanView() }.tabItem {
                Label {
                    Text("Scan")
                } icon: {
                    Image(uiImage: NavigationArtwork.tabIcon(.scan, selected: router.tab == .scan))
                        .renderingMode(.original)
                }
            }.tag(AppTab.scan)
            NavigationStack { MessagesView() }.tabItem {
                Label {
                    Text("Messages")
                } icon: {
                    Image(
                        uiImage: NavigationArtwork.tabIcon(
                            .messages, selected: router.tab == .messages)
                    )
                    .renderingMode(.original)
                }
            }.tag(AppTab.messages)
            NavigationStack { ProfileView() }.tabItem {
                Label {
                    Text("You")
                } icon: {
                    Image(
                        uiImage: NavigationArtwork.accountIcon(accountPhoto, name: store.profileName, selected: router.tab == .you)
                    )
                    .renderingMode(.original)
                }
            }.tag(
                AppTab.you)
        }.task(id: store.profileAvatar) {
            accountPhoto = nil
            if let avatar = store.profileAvatar, !avatar.isEmpty {
                let image = try? await ImagePipeline.shared.image(avatar)
                if !Task.isCancelled { accountPhoto = image }
            } else if !store.isBackend { accountPhoto = UIImage(named: "profile") }
        }.task {
            let args = ProcessInfo.processInfo.arguments
            #if DEBUG
                if args.contains("--map-preview") { router.tab = .map }
                if args.contains("--messages-preview") { router.tab = .messages }
                if args.contains("--scan-preview") { router.tab = .scan }
            #endif
            if !args.contains("--fixture")
                && (!args.contains("--uitesting") || args.contains("--backend"))
            {
                store.enterBackendMode()
                do {
                    if SessionController.shared.isLocalBackend
                        && SessionController.shared.current == nil
                    {
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
        }.task(id: "\(SessionController.shared.current?.userId ?? "")-\(SessionController.shared.profileRevision)") {
            guard store.isBackend, !SessionController.shared.isLocalBackend else { return }
            guard SessionController.shared.current != nil else {
                store.disconnectBackend()
                return
            }
            do {
                _ = try await SessionController.shared.currentSession()
                await store.connect(try SessionController.shared.repository())
                try? await SessionController.shared.syncProfile()
                await store.refreshBackend(force: true)
            } catch {
                // Only an explicit Sign out clears the saved account and its data.
                if !Task.isCancelled && !SessionController.shared.needsSignIn {
                    store.notice = error.localizedDescription
                }
            }
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
                if ProcessInfo.processInfo.arguments.contains("--welcome-preview")
                    && !welcomePreviewDismissed
                {
                    WelcomeView { welcomePreviewDismissed = true }
                }
            #endif
        }.onChange(of: store.accountID, initial: true) { _, _ in
            scanner.reset()
            scanner.bindStorageHistory(store)
        }
            .task(id: "\(scenePhase)-\(store.isBackend)-\(store.accountID)") {
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
                if SessionController.shared.needsSignIn {
                    HStack {
                        Text("Reconnect your account").rescueFont(14, .semibold)
                        Spacer()
                        Button("Sign in again") { Task { await SessionController.shared.signIn() } }
                            .rescueFont(14, .semibold).foregroundStyle(Theme.save)
                    }.padding(16).card(radius: 20).padding(.horizontal, 16)
                } else if let notice = store.notice {
                    HStack(spacing: 10) {
                        Image(systemName: notice == "Added to cart" ? "checkmark.circle.fill" : "info.circle")
                            .foregroundStyle(Theme.save)
                        Text(notice).rescueFont(14, .medium)
                        Spacer(minLength: 8)
                        Button { withAnimation(Theme.spring) { store.notice = nil } } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                                .frame(width: 32, height: 32)
                        }.buttonStyle(.plain).accessibilityLabel("Dismiss notification")
                    }.foregroundStyle(Theme.ink).padding(12)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))
                        .shadow(color: Theme.deep.opacity(0.1), radius: 16, y: 6)
                        .padding(.horizontal, 16)
                        .gesture(DragGesture(minimumDistance: 15).onEnded { value in
                            if abs(value.translation.width) > 35 || value.translation.height < -20 {
                                withAnimation(Theme.spring) { store.notice = nil }
                            }
                        }).transition(
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
                    store.updateBrowseLocation(
                        latitude: selection.latitude, longitude: selection.longitude)
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
    private var showsCloseButton: Bool {
        if case .location? = router.sheet { return false }
        return true
    }
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
                case .scanCamera: ScanCameraHost()
                case .scanReview: ScanReviewView()
                case .scanItem(let id): InventoryDetailView(id: id)
                case .sensor: SensorConnectionView()
                case .profile(let panel): ProfilePanelView(panel: panel)
                case nil: Color.clear
                }
            }.background(Theme.ivory).foregroundStyle(Theme.ink)
                .toolbar {
                    if showsCloseButton {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                router.sheet = nil
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel("Close").accessibilityIdentifier("close-sheet")
                        }
                    }
                }.toolbarBackground(Theme.ivory, for: .navigationBar).toolbarBackground(
                    .visible, for: .navigationBar)
        }.tint(Theme.ink).toolbar(.visible, for: .navigationBar)
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
