import MapKit
import PhotosUI
import SwiftUI

struct ScanView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(FoodScanController.self) private var scanner
    @State private var photo: PhotosPickerItem?
    @State private var listedOnly = false
    @State private var cameraUnavailable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scan an item.").rescueFont(34, .bold).tracking(-1.2)
                        Text("Know what you have. Make the most of it.")
                            .rescueFont(14).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 4)
                    Button {
                        router.sheet = .sensor
                    } label: {
                        Image(systemName: "sensor.tag.radiowaves.forward")
                            .font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.save)
                            .frame(width: 48, height: 48).background(Theme.soft, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Connect storage sensor")
                }.padding(.top, 16)

                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 30).fill(
                        LinearGradient(
                            colors: [Theme.deep, Theme.sage], startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                    Circle().stroke(.white.opacity(0.1), lineWidth: 1).frame(
                        width: 270, height: 270
                    ).offset(x: 140, y: -50)
                    Circle().fill(.white.opacity(0.06)).frame(width: 180).offset(x: 200, y: -80)
                    HStack {
                        Spacer()
                        ZStack {
                            FoodPhoto(name: "avo").frame(width: 112, height: 136)
                                .clipShape(RoundedRectangle(cornerRadius: 22)).rotationEffect(
                                    .degrees(12)
                                ).offset(x: 24, y: -22)
                            FoodPhoto(name: "straw").frame(width: 112, height: 136)
                                .clipShape(RoundedRectangle(cornerRadius: 22)).overlay(
                                    RoundedRectangle(cornerRadius: 22).stroke(
                                        .white.opacity(0.6), lineWidth: 2)
                                )
                                .rotationEffect(.degrees(-9)).offset(x: -32, y: 16)
                        }.frame(width: 180, height: 190)
                    }.padding(.trailing, 14).padding(.bottom, 92).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "viewfinder").font(.system(size: 38, weight: .light))
                            .padding(.bottom, 26)
                        Text("Your food,\nin focus.").rescueFont(25, .bold).tracking(
                            -0.5
                        )
                        .frame(width: 140, alignment: .leading)
                        Text("Scan. Save. Share.").rescueFont(13).foregroundStyle(
                            .white.opacity(0.8))
                        Button {
                            Haptic.tap()
                            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                                scanner.draft = InventoryFood(
                                    name: "Tomato", variety: "Roma",
                                    photoBase64: UIImage(named: "straw")?.jpegData(
                                        compressionQuality: 0.05)?.base64EncodedString() ?? "",
                                    identification: "Manual review")
                                router.sheet = .scanReview
                            } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                router.sheet = .scanCamera
                            } else {
                                cameraUnavailable = true
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "camera.fill").font(.system(size: 16))
                                Text("Scan food").rescueFont(16, .semibold)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(
                                    .system(size: 15, weight: .semibold))
                            }.foregroundStyle(Theme.deep).padding(18).background(
                                Theme.paper, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).accessibilityIdentifier("scan-food")
                    }.foregroundStyle(Theme.paper).padding(24)
                }.frame(height: 342).clipped().clipShape(RoundedRectangle(cornerRadius: 30))
                    .shadow(color: Theme.deep.opacity(0.15), radius: 16, y: 8)

                PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Choose a photo instead").rescueFont(14, .semibold)
                    }.foregroundStyle(Theme.sage).frame(maxWidth: .infinity).padding(.vertical, 3)
                }.accessibilityIdentifier("scan-choose-photo")

                Button {
                    router.sheet = .sensor
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "wave.3.right").font(.system(size: 21)).foregroundStyle(
                            Theme.sage
                        )
                        .frame(width: 44, height: 44).background(
                            Theme.soft, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Storage sensor").rescueFont(15, .semibold)
                            Text(
                                scanner.sensor.connected == nil
                                    ? "Connect to monitor your food"
                                    : "Bluetooth connected · setup pending"
                            )
                            .rescueFont(12).foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 0)
                        Circle().fill(scanner.sensor.connected == nil ? Theme.muted : Theme.save)
                            .frame(width: 7, height: 7)
                        Image(systemName: "chevron.right").font(
                            .system(size: 12, weight: .semibold)
                        ).foregroundStyle(Theme.muted)
                    }.padding(16).card(radius: 22).foregroundStyle(Theme.ink)
                }.buttonStyle(.plain).accessibilityIdentifier("scan-sensor")

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Your food").rescueFont(23, .bold).tracking(-0.5)
                        Spacer()
                        Text("\(store.inventory.count) items").rescueFont(13).foregroundStyle(
                            Theme.secondary)
                    }
                    HStack(spacing: 6) {
                        inventoryFilter("My collection", selected: !listedOnly) {
                            listedOnly = false
                        }
                        inventoryFilter("For sale", selected: listedOnly) { listedOnly = true }
                    }.padding(5).background(Theme.bone, in: Capsule())
                    if store.inventoryLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(24)
                    } else if visibleItems.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: listedOnly ? "tag" : "leaf").font(
                                .system(size: 28, weight: .light)
                            ).foregroundStyle(Theme.sage)
                            Text(listedOnly ? "Nothing for sale yet" : "Make room for good food")
                                .rescueFont(18, .semibold)
                            Text(
                                listedOnly
                                    ? "Choose an item from your collection to list it."
                                    : "Your scanned items will appear here. They stay private until you choose to sell."
                            )
                            .rescueFont(14).foregroundStyle(Theme.secondary).multilineTextAlignment(
                                .center)
                        }.frame(maxWidth: .infinity).padding(26).card(radius: 24)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                            spacing: 18
                        ) {
                            ForEach(visibleItems) { item in
                                Button {
                                    router.sheet = .scanItem(item.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 9) {
                                        InventoryPhoto(item: item).frame(height: 146).clipShape(
                                            RoundedRectangle(cornerRadius: 20)
                                        )
                                        .overlay(alignment: .topLeading) {
                                            Text(item.isListed ? "For sale" : "Private").rescueFont(
                                                10, .semibold
                                            ).foregroundStyle(
                                                item.isListed ? Theme.paper : Theme.deep
                                            )
                                            .padding(.horizontal, 9).padding(.vertical, 6)
                                            .background(
                                                item.isListed ? Theme.save : Theme.paper,
                                                in: Capsule()
                                            ).padding(10)
                                        }
                                        Text(item.title).rescueFont(16, .semibold).lineLimit(2)
                                        Text(
                                            item.deviceID.isEmpty
                                                ? "Not monitored" : "Sensor linked"
                                        ).rescueFont(12).foregroundStyle(Theme.secondary)
                                    }.foregroundStyle(Theme.ink)
                                }.buttonStyle(.plain).accessibilityIdentifier(
                                    "inventory-\(item.id)")
                            }
                        }
                    }
                }
            }.padding(.horizontal, 20).padding(.bottom, 28)
        }.background(Theme.ivory).toolbar(.hidden, for: .navigationBar)
            .task(id: store.accountID) { await store.loadInventory() }
            .refreshable { await store.loadInventory() }
            .onChange(of: photo) { _, selected in
                guard let selected else { return }
                Task {
                    do {
                        guard let data = try await selected.loadTransferable(type: Data.self),
                            let image = UIImage(data: data)
                        else {
                            scanner.error = "That photo couldn't be opened. Try another."
                            return
                        }
                        router.sheet = .scanReview
                        await scanner.identify(image)
                        photo = nil
                    } catch { scanner.error = "That photo couldn't be opened. Try another." }
                }
            }.alert("Camera unavailable", isPresented: $cameraUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Choose a photo from your library, or use the camera on your iPhone.")
            }
            .alert(
                "Couldn't scan photo",
                isPresented: Binding(
                    get: { scanner.error != nil }, set: { if !$0 { scanner.error = nil } })
            ) {
                Button("OK", role: .cancel) { scanner.error = nil }
            } message: {
                Text(scanner.error ?? "")
            }
    }
    private var visibleItems: [InventoryFood] {
        store.inventory.filter { listedOnly ? $0.isListed : !$0.isListed }
    }
    private func inventoryFilter(_ title: String, selected: Bool, action: @escaping () -> Void)
        -> some View
    {
        Button {
            withAnimation(Theme.spring) { action() }
        } label: {
            Text(title).rescueFont(13, .semibold).foregroundStyle(
                selected ? Theme.deep : Theme.secondary
            )
            .frame(maxWidth: .infinity).padding(.vertical, 11).background(
                selected ? Theme.paper : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct InventoryPhoto: View {
    let item: InventoryFood
    var body: some View {
        if let data = Data(base64Encoded: item.photoBase64), let image = UIImage(data: data) {
            GeometryReader { geo in
                Image(uiImage: image).resizable().scaledToFill().frame(
                    width: geo.size.width, height: geo.size.height
                ).clipped()
            }
        } else {
            ZStack {
                Theme.soft
                Image(systemName: "leaf").font(.system(size: 30)).foregroundStyle(Theme.sage)
            }
        }
    }
}

struct ScanCameraHost: View {
    @Environment(AppRouter.self) private var router
    @Environment(FoodScanController.self) private var scanner
    var body: some View {
        FoodCameraCapture { image in
            guard let image else {
                router.sheet = nil
                return
            }
            router.sheet = .scanReview
            Task { await scanner.identify(image) }
        }.ignoresSafeArea()
    }
}

struct ScanReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(FoodScanController.self) private var scanner
    @State private var saving = false
    @State private var saveError = false
    var body: some View {
        @Bindable var scanner = scanner
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InventoryPhoto(item: scanner.draft).frame(height: 240).clipShape(
                    RoundedRectangle(cornerRadius: 26))
                if scanner.analyzing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Taking a closer look…").rescueFont(17, .semibold)
                    }.padding(20)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(
                            scanner.draft.name.isEmpty
                                ? "What are we looking at?"
                                : "Looks like \(scanner.draft.name.lowercased())."
                        ).rescueFont(27, .bold).tracking(-0.6)
                        Text(
                            scanner.draft.identification == "Apple Vision"
                                ? "On-device suggestion · confirm the food and variety below."
                                : "Add the food name. Variety and condition need your review."
                        )
                        .rescueFont(14).foregroundStyle(Theme.secondary)
                    }
                    VStack(spacing: 16) {
                        scanField(
                            "Food", text: $scanner.draft.name, placeholder: "e.g. Tomato",
                            id: "scan-name")
                        scanField(
                            "Variety", text: $scanner.draft.variety,
                            placeholder: "e.g. Roma · optional", id: "scan-variety")
                        scanField(
                            "Quantity", text: $scanner.draft.quantity,
                            placeholder: "e.g. 3 tomatoes", id: "scan-quantity")
                        Picker("Condition", selection: $scanner.draft.condition) {
                            ForEach(["Not assessed", "Unripe", "Ripe", "Use soon"], id: \.self) {
                                Text($0).tag($0)
                            }
                        }.rescueFont(15)
                        Picker("Stored in", selection: $scanner.draft.storage) {
                            ForEach(["Counter", "Fridge", "Pantry"], id: \.self) {
                                Text($0).tag($0)
                            }
                        }.rescueFont(15)
                    }.padding(20).card(radius: 24)
                    Label("Saved privately. Nothing is listed for sale yet.", systemImage: "lock")
                        .rescueFont(13).foregroundStyle(Theme.secondary)
                }
            }.padding(20)
        }.background(Theme.ivory).navigationTitle("Review your scan").navigationBarTitleDisplayMode(
            .inline
        )
        .safeAreaInset(edge: .bottom) {
            BottomAction {
                PrimaryButton(
                    title: saving ? "Saving…" : "Save to my food", symbol: "arrow.down",
                    color: Theme.deep,
                    disabled: saving || scanner.analyzing
                        || scanner.draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty,
                    id: "save-scan"
                ) {
                    saving = true
                    Task {
                        if await store.saveInventoryFood(scanner.draft) {
                            Haptic.success()
                            router.sheet = .scanItem(scanner.draft.id)
                        } else {
                            saveError = true
                        }
                        saving = false
                    }
                }
            }
        }.alert("Couldn't save item", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.notice ?? "Check your connection and try again.")
        }
    }
    private func scanField(_ label: String, text: Binding<String>, placeholder: String, id: String)
        -> some View
    {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).rescueFont(12, .semibold).foregroundStyle(Theme.secondary)
            TextField(placeholder, text: text).rescueFont(17).accessibilityIdentifier(id)
                .padding(12).background(Theme.ivory, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct InventoryDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(FoodScanController.self) private var scanner
    let id: String
    @State private var removePrompt = false
    private var food: InventoryFood? { store.inventory.first { $0.id == id } }
    var body: some View {
        ScrollView {
            if let item = food {
                VStack(alignment: .leading, spacing: 22) {
                    InventoryPhoto(item: item).frame(height: 240).clipShape(
                        RoundedRectangle(cornerRadius: 26))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.title).rescueFont(30, .bold).tracking(-0.8)
                        Text("\(item.quantity) · \(item.storage) · \(item.condition)").rescueFont(
                            14
                        ).foregroundStyle(Theme.secondary)
                        Label(
                            item.isListed ? "Listed on the marketplace" : "Private collection",
                            systemImage: item.isListed ? "tag" : "lock"
                        )
                        .rescueFont(13, .semibold).foregroundStyle(Theme.save)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Storage conditions").rescueFont(19, .semibold)
                            Spacer()
                            Text(item.deviceID.isEmpty ? "Not monitored" : "Sensor linked")
                                .rescueFont(11).foregroundStyle(Theme.secondary)
                        }
                        let summary = StorageSummary.recent(store.storageReadings, item: item)
                        HStack(spacing: 10) {
                            sensorMetric(
                                "Temperature",
                                value: summary.map { String(format: "%.1f°C", $0.temperature) }
                                    ?? "—", icon: "thermometer.medium")
                            sensorMetric(
                                "Humidity",
                                value: summary.map { String(format: "%.0f%%", $0.humidity) } ?? "—",
                                icon: "humidity")
                            sensorMetric(
                                "Light",
                                value: summary.map { String(format: "%.0f lx", $0.light) } ?? "—",
                                icon: "sun.max")
                        }
                        Text(
                            summary == nil
                                ? "Connect a sensor and link this item to record its storage conditions."
                                : "Recent 3-day average · \(summary!.count) samples. Historical readings aren't live monitoring."
                        )
                        .rescueFont(13).foregroundStyle(Theme.secondary)
                        Button {
                            router.sheet = .sensor
                        } label: {
                            Label("Connect a storage sensor", systemImage: "wave.3.right")
                                .rescueFont(14, .semibold).foregroundStyle(Theme.save)
                        }
                        if let connected = scanner.sensor.connected, !item.isListed,
                            item.deviceID != connected.identifier.uuidString
                        {
                            Button("Link to \(connected.name ?? "sensor")") {
                                var updated = item
                                updated.deviceID = connected.identifier.uuidString
                                Task { _ = await store.saveInventoryFood(updated) }
                            }.rescueFont(14, .semibold).foregroundStyle(Theme.save)
                        }
                    }.padding(18).card(radius: 24)
                    if let guide = FoodStorageGuide.forFood(item) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Storage reference", systemImage: "leaf").rescueFont(
                                18, .semibold)
                            Text("\(guide.temperature) · \(guide.humidity) RH").rescueFont(
                                20, .semibold
                            ).foregroundStyle(Theme.save)
                            Text(guide.note).rescueFont(13).foregroundStyle(Theme.secondary)
                            Link(
                                "UC Davis produce guide ↗", destination: URL(string: guide.source)!
                            ).rescueFont(12, .semibold).foregroundStyle(Theme.sage)
                        }.padding(18).background(Theme.soft, in: RoundedRectangle(cornerRadius: 24))
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Freshness outlook").rescueFont(19, .semibold)
                        Text("No expiry prediction yet").rescueFont(15, .semibold).foregroundStyle(
                            Theme.secondary)
                        Text(
                            "A calibrated model needs the food’s condition and sensor history. A photo alone doesn't verify freshness or food safety."
                        )
                        .rescueFont(13).foregroundStyle(Theme.secondary)
                    }.padding(18).card(radius: 24)
                    HStack {
                        Text(
                            "Added \(Date(timeIntervalSince1970: item.scannedAt / 1000).formatted(date: .abbreviated, time: .omitted))"
                        ).rescueFont(12).foregroundStyle(Theme.muted)
                        Spacer()
                        Button("Remove", role: .destructive) { removePrompt = true }.rescueFont(13)
                    }
                }.padding(20)
            }
        }.background(Theme.ivory).navigationTitle("Your item").navigationBarTitleDisplayMode(
            .inline
        )
        .safeAreaInset(edge: .bottom) {
            if let item = food {
                BottomAction {
                    if item.isListed {
                        PrimaryButton(
                            title: "View listing", symbol: "arrow.up.right", color: Theme.deep
                        ) { router.sheet = .listing(item.listingID) }
                        Button("Take off the marketplace") {
                            Task { await store.unlistInventoryFood(item.id) }
                        }.rescueFont(13).foregroundStyle(Theme.secondary)
                    } else {
                        NavigationLink {
                            ScanSellEditor(item: item)
                        } label: {
                            Label("Sell this item", systemImage: "tag.fill").rescueFont(
                                17, .semibold
                            )
                            .frame(maxWidth: .infinity).padding(18).foregroundStyle(Theme.paper)
                            .background(Theme.deep, in: Capsule())
                        }.buttonStyle(.plain).accessibilityIdentifier("sell-scanned-item")
                    }
                }
            }
        }.confirmationDialog(
            "Remove this item?", isPresented: $removePrompt, titleVisibility: .visible
        ) {
            Button("Remove item", role: .destructive) {
                Task {
                    await store.removeInventoryFood(id)
                    if food == nil { router.sheet = nil }
                }
            }
        }.task { await store.loadInventory() }
    }
    private func sensorMetric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Theme.sage)
            Text(value).rescueFont(17, .semibold)
            Text(title).rescueFont(10).foregroundStyle(Theme.secondary).lineLimit(1)
                .minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(
            Theme.ivory, in: RoundedRectangle(cornerRadius: 15))
    }
}

struct SensorConnectionView: View {
    @Environment(FoodScanController.self) private var scanner
    var body: some View {
        let sensor = scanner.sensor
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 20) {
                    ZStack {
                        Circle().stroke(Theme.sage.opacity(0.1), lineWidth: 1).frame(
                            width: 190, height: 190)
                        Circle().stroke(Theme.sage.opacity(0.18), lineWidth: 1).frame(
                            width: 140, height: 140)
                        Image(systemName: "sensor.tag.radiowaves.forward.fill").font(
                            .system(size: 36, weight: .light)
                        )
                        .foregroundStyle(Theme.paper).frame(width: 88, height: 88)
                        .background(
                            LinearGradient(
                                colors: [Theme.save, Theme.deep], startPoint: .topLeading,
                                endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
                        if sensor.searching { ProgressView().tint(Theme.save).offset(y: 96) }
                    }
                    Text("A closer eye\non your food.").rescueFont(30, .bold).tracking(-0.8)
                        .multilineTextAlignment(.center)
                    Text(
                        "Pair your storage sensor to Gusto. Temperature, humidity and light will live alongside your items."
                    )
                    .rescueFont(15).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
                HStack(spacing: 10) {
                    Circle().fill(sensor.connected == nil ? Theme.muted : Theme.save).frame(
                        width: 8, height: 8)
                    Text(sensor.status).rescueFont(14, .semibold)
                    Spacer()
                }.padding(18).card(radius: 20)
                if let connected = sensor.connected {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(connected.name ?? "Storage sensor").rescueFont(19, .semibold)
                        Text(
                            "Paired over Bluetooth. Sensor readings will appear once the firmware's data protocol is configured."
                        )
                        .rescueFont(14).foregroundStyle(Theme.secondary)
                        Button("Disconnect", role: .destructive) { sensor.disconnect() }.rescueFont(
                            14)
                    }.padding(18).card(radius: 22)
                } else {
                    PrimaryButton(
                        title: sensor.searching ? "Looking for your sensor…" : "Find a device",
                        symbol: "wave.3.right", color: Theme.deep,
                        disabled: sensor.searching || sensor.connectingID != nil, id: "find-sensor"
                    ) { sensor.search() }
                    ForEach(sensor.devices, id: \.identifier) { device in
                        Button {
                            sensor.connect(device)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sensor.tag.radiowaves.forward").foregroundStyle(
                                    Theme.sage)
                                Text(device.name ?? "Bluetooth device").rescueFont(16, .semibold)
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(Theme.save)
                            }.padding(18).card(radius: 20).foregroundStyle(Theme.ink)
                        }.buttonStyle(.plain).disabled(sensor.connectingID != nil)
                    }
                }
                Text(
                    "No sensor? You can still scan, save and sell your food. Gusto won't invent storage readings or an expiry date."
                )
                .rescueFont(13).foregroundStyle(Theme.secondary).padding(18).background(
                    Theme.soft, in: RoundedRectangle(cornerRadius: 22))
            }.padding(24)
        }.background(Theme.ivory).navigationTitle("Storage sensor").navigationBarTitleDisplayMode(
            .inline
        )
        .onDisappear { sensor.stopSearch() }
    }
}

struct ScanSellEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let item: InventoryFood
    @State private var price = ""
    @State private var allergens = ""
    @State private var address = ""
    @State private var places: [MKMapItem] = []
    @State private var place: MKMapItem?
    @State private var start = Date().addingTimeInterval(3600)
    @State private var end = Date().addingTimeInterval(10800)
    @State private var confirmations: Set<String> = []
    @State private var publishing = false
    @State private var finding = false
    @State private var error: String?
    private let safety = [
        "Stored safely", "Condition is accurate", "No signs of spoilage", "Allergens are declared",
    ]
    private var cents: Int { Int(((Double(price) ?? 0) * 100).rounded()) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    InventoryPhoto(item: item).frame(width: 80, height: 92).clipShape(
                        RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).rescueFont(22, .bold)
                        Text("\(item.quantity) · \(item.condition)").rescueFont(13).foregroundStyle(
                            Theme.secondary)
                        Text("From your collection").rescueFont(12, .semibold).foregroundStyle(
                            Theme.save)
                    }
                }
                Text(
                    "Your photo and item details are ready. Set your price and pickup window, then review before listing."
                )
                .rescueFont(14).foregroundStyle(Theme.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Listing details").rescueFont(19, .semibold)
                    HStack {
                        Text("Price")
                        Spacer()
                        Text("$").foregroundStyle(Theme.secondary)
                        TextField("0.00", text: $price).keyboardType(.decimalPad).frame(width: 90)
                            .accessibilityIdentifier("scan-sell-price")
                    }
                    Divider()
                    TextField("Allergens · enter 'none known' if applicable", text: $allergens)
                        .rescueFont(14).accessibilityIdentifier("scan-sell-allergens")
                    Text("Identification isn't verification. Check the item and its label.")
                        .rescueFont(12).foregroundStyle(Theme.secondary)
                }.padding(18).card(radius: 24)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Pickup location").rescueFont(19, .semibold)
                    TextField("Enter an address", text: $address).rescueFont(15)
                        .accessibilityIdentifier("scan-pickup-address")
                        .onChange(of: address) { _, _ in
                            place = nil
                            places = []
                        }
                    Button(finding ? "Finding address…" : "Find address") {
                        finding = true
                        Task {
                            let request = MKLocalSearch.Request()
                            request.naturalLanguageQuery = address
                            do {
                                places = Array(
                                    try await MKLocalSearch(request: request).start().mapItems
                                        .prefix(5))
                            } catch {
                                self.error =
                                    "Couldn't find that address. Try a full street address."
                            }
                            finding = false
                        }
                    }.rescueFont(14, .semibold).foregroundStyle(Theme.save).disabled(
                        finding || address.isEmpty)
                    ForEach(Array(places.enumerated()), id: \.offset) { index, candidate in
                        Button {
                            place = candidate
                            places = []
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(candidate.name ?? "Address").rescueFont(14, .semibold)
                                Text(candidate.placemark.title ?? "").rescueFont(12)
                                    .foregroundStyle(Theme.secondary)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("pickup-place-\(index)")
                    }
                    if let place {
                        Label(
                            place.placemark.title ?? address, systemImage: "checkmark.circle.fill"
                        ).rescueFont(13).foregroundStyle(Theme.save)
                    }
                    Text(
                        "Buyers get an approximate area. Your address is shared after pickup confirmation."
                    ).rescueFont(12).foregroundStyle(Theme.secondary)
                }.padding(18).card(radius: 24)
                VStack(alignment: .leading, spacing: 14) {
                    Text("When can they pick up?").rescueFont(19, .semibold)
                    DatePicker(
                        "From", selection: $start, in: Date()...Date().addingTimeInterval(259200))
                    DatePicker(
                        "Until", selection: $end, in: Date()...Date().addingTimeInterval(259200))
                }.padding(18).card(radius: 24)
                VStack(alignment: .leading, spacing: 14) {
                    Text("One last check").rescueFont(19, .semibold)
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
                                })
                        ).rescueFont(14).tint(Theme.save)
                    }
                }.padding(18).card(radius: 24)
            }.padding(20)
        }.background(Theme.ivory)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.sheet = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close").accessibilityIdentifier("close-sheet")
                }
            }.navigationTitle("Sell your item").navigationBarTitleDisplayMode(
                .inline
            )
            .safeAreaInset(edge: .bottom) {
                BottomAction {
                    PrimaryButton(
                        title: publishing ? "Listing…" : "List on Gusto", symbol: "arrow.up.right",
                        color: Theme.deep,
                        disabled: publishing || store.backendBusy || cents <= 0
                            || allergens.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || place == nil || end <= start || confirmations.count != 4,
                        id: "publish-scanned-item"
                    ) {
                        guard let place else { return }
                        publishing = true
                        Task {
                            if await store.sellInventoryFood(
                                item, price: cents, allergens: allergens,
                                pickupAddress: place.placemark.title ?? address,
                                latitude: place.placemark.coordinate.latitude,
                                longitude: place.placemark.coordinate.longitude,
                                start: start, end: end, attestations: confirmations.count == 4)
                            {
                                Haptic.success()
                                router.sheet = nil
                            } else {
                                error = store.notice ?? "Couldn't publish. Try again."
                            }
                            publishing = false
                        }
                    }
                }
            }.alert(
                "Check your listing",
                isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
            ) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
    }
}
