import SwiftUI

struct MessagesView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Messages").rescueFont(32, .bold).tracking(-1)
                    Text("Pickup chats & updates").rescueFont(15).foregroundStyle(Theme.secondary)
                }.padding(.top, 16)

                VStack(spacing: 0) {
                    NavigationLink {
                        GustoWelcomeMessage()
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            GustoMessageAvatar()
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text("Gusto").rescueFont(17, .semibold)
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 13)).foregroundStyle(Theme.save)
                                    Spacer()
                                    Text("WELCOME").rescueFont(10, .semibold)
                                        .tracking(1).foregroundStyle(Theme.save)
                                }
                                Text("Hi! Welcome to Gusto 👋").rescueFont(15, .medium)
                                Text("Good food nearby. Here's how to get started.")
                                    .rescueFont(13).foregroundStyle(Theme.secondary)
                                    .lineLimit(2)
                            }
                            Image(systemName: "chevron.right").font(
                                .system(size: 12, weight: .semibold)
                            )
                            .foregroundStyle(Theme.muted).padding(.top, 23)
                        }.padding(18).foregroundStyle(Theme.ink)
                    }.buttonStyle(.plain).accessibilityIdentifier("gusto-welcome")

                    ForEach(store.messageSellers) { seller in
                        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 84)
                        Button {
                            router.chat(seller.id)
                        } label: {
                            HStack(spacing: 14) {
                                Avatar(seller: seller, size: 52)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(seller.name).rescueFont(16, .semibold)
                                    if let item = store.pinnedListing(for: seller.id) {
                                        Text(item.name).rescueFont(12).foregroundStyle(Theme.save)
                                            .lineLimit(1)
                                    }
                                    Text(
                                        store.messages[seller.id]?.last?.text
                                            ?? "Start a conversation"
                                    )
                                    .rescueFont(14).foregroundStyle(Theme.secondary).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(
                                        Theme.muted)
                            }.padding(18).foregroundStyle(Theme.ink)
                        }.buttonStyle(.plain).accessibilityIdentifier("chat-\(seller.id)")
                    }
                }.card(radius: 24)

                if store.messageSellers.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 30, weight: .light)).foregroundStyle(Theme.sage)
                            .frame(width: 72, height: 72).background(Theme.soft, in: Circle())
                        VStack(spacing: 7) {
                            Text("Ready when you are").rescueFont(22, .semibold)
                            Text(
                                "Once you contact a seller, your pickup conversation will appear here."
                            )
                            .rescueFont(15).foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.center).fixedSize(
                                horizontal: false, vertical: true)
                        }
                        Button {
                            Haptic.tap()
                            withAnimation(Theme.spring) { router.tab = .discover }
                        } label: {
                            HStack(spacing: 10) {
                                Text("Find food nearby").rescueFont(14, .semibold)
                                Image(systemName: "arrow.right").font(
                                    .system(size: 13, weight: .semibold))
                            }.foregroundStyle(Theme.save).padding(.horizontal, 20).padding(
                                .vertical, 13
                            )
                            .background(Theme.soft, in: Capsule())
                        }.buttonStyle(.plain).accessibilityIdentifier("messages-browse")
                    }.frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.top, 32)
                }
            }.padding(.horizontal, 20).padding(.bottom, 32)
        }.background(Theme.ivory).toolbar(.hidden, for: .navigationBar)
    }
}

private struct GustoMessageAvatar: View {
    var body: some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: 24, weight: .medium)).foregroundStyle(Theme.paper)
            .frame(width: 52, height: 52)
            .background(
                LinearGradient(
                    colors: [Theme.save, Theme.deep], startPoint: .topLeading,
                    endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct GustoWelcomeMessage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    GustoMessageAvatar()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A little hello from Gusto").rescueFont(17, .semibold)
                        Text("Platform message").rescueFont(12).foregroundStyle(Theme.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 20) {
                    Text("Hi! Welcome to Gusto 👋").rescueFont(26, .bold).tracking(-0.6)
                    Text(
                        "Find something good nearby, save it to your cart, and pick it up from a local seller."
                    )
                    .rescueFont(16).foregroundStyle(Theme.secondary).lineSpacing(4)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    welcomeStep(
                        "1", title: "Find your favorites",
                        detail: "Choose your location and browse food around you.")
                    welcomeStep(
                        "2", title: "Save now, decide later",
                        detail: "Adding to your cart doesn't reserve anything or message sellers.")
                    welcomeStep(
                        "3", title: "Make pickup plans",
                        detail:
                            "Confirm from your cart when you're ready. Then contact sellers to arrange pickup."
                    )
                    Text("Your seller conversations will live right here. Happy finding!")
                        .rescueFont(15).foregroundStyle(Theme.sage).lineSpacing(3)
                }.padding(24).card(radius: 26)
                Label("A welcome note from Gusto", systemImage: "info.circle")
                    .rescueFont(12).foregroundStyle(Theme.muted)
            }.padding(20)
        }.background(Theme.ivory).navigationTitle("Gusto")
            .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .accessibilityIdentifier("welcome-message")
    }
    private func welcomeStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).rescueFont(12, .semibold).foregroundStyle(Theme.save)
                .frame(width: 28, height: 28).background(Theme.soft, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).rescueFont(16, .semibold)
                Text(detail).rescueFont(14).foregroundStyle(Theme.secondary).lineSpacing(3)
            }
        }
    }
}

struct ChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    let sellerID: String
    @State private var draft = ""
    private let quickReplies = [
        "Still available?", "Fresh photo?", "I'm here", "+10 min", "Reschedule",
    ]
    var body: some View {
        let seller = store.seller(sellerID)
        VStack(spacing: 0) {
            if let item = store.pinnedListing(for: sellerID) {
                HStack(spacing: 12) {
                    FoodPhoto(name: item.image).frame(width: 44, height: 44).clipShape(
                        RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).rescueFont(14, .semibold)
                        Text("\(seller.area) · Responds \(seller.responds)").rescueFont(12)
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Text(Money.text(item.price)).rescueFont(16, .semibold)
                }.padding(10).card(radius: 16).padding(.horizontal, 20).padding(.bottom, 8)
                    .accessibilityIdentifier("pinned-product")
            }
            ForEach(store.pickupRequests.filter { $0.buyerId == sellerID }) { request in
                VStack(alignment: .leading, spacing: 10) {
                    Text(request.status == "waiting" ? "Pickup request" : "Pickup confirmed")
                        .rescueFont(16, .semibold)
                    Text(request.items.map(\.name).joined(separator: ", ")).rescueFont(13)
                    Text(Date(timeIntervalSince1970: request.proposed / 1000), style: .time)
                        .rescueFont(14, .semibold).foregroundStyle(Theme.save)
                    if request.status == "waiting" {
                        Button("Confirm pickup") { Task { await store.confirmSellerPickup(request.id) } }
                            .buttonStyle(.borderedProminent).tint(Theme.save).disabled(store.backendBusy)
                            .accessibilityIdentifier("confirm-pickup-\(request.id)")
                    } else if request.phase == "waiting" {
                        Button("Confirm handoff") { Task { await store.completeSellerHandoff(request.id) } }
                            .buttonStyle(.borderedProminent).tint(Theme.save).disabled(store.backendBusy)
                            .accessibilityIdentifier("confirm-handoff-\(request.id)")
                    } else {
                        Text("The buyer will let you know when they arrive.").rescueFont(12).foregroundStyle(Theme.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).card(radius: 20)
                    .padding(.horizontal, 20).padding(.bottom, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        Text(
                            "Today"
                        ).rescueFont(12).foregroundStyle(
                            Theme.muted
                        ).padding(.vertical, 8)
                        if (store.messages[sellerID] ?? []).isEmpty {
                            VStack(spacing: 8) {
                                Text("Say hello to \(seller.firstName)").rescueFont(20, .semibold)
                                Text("Ask about the food or arrange your pickup here.")
                                    .rescueFont(14).foregroundStyle(Theme.secondary)
                                    .multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity).padding(.vertical, 36)
                        }
                        ForEach(
                            store.messages[sellerID] ?? []
                        ) { message in
                            HStack {
                                if message.outgoing { Spacer(minLength: 60) }
                                Text(message.text + (message.delivery.map { " · \($0)" } ?? ""))
                                    .rescueFont(16).foregroundStyle(
                                        message.outgoing ? Theme.paper : Theme.ink
                                    ).padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(
                                        message.outgoing ? Theme.deep : Theme.paper,
                                        in: UnevenRoundedRectangle(
                                            topLeadingRadius: 20,
                                            bottomLeadingRadius: message.outgoing ? 20 : 6,
                                            bottomTrailingRadius: message.outgoing ? 6 : 20,
                                            topTrailingRadius: 20))
                                if !message.outgoing { Spacer(minLength: 60) }
                            }.id(message.id)
                        }
                        if store.typingSellers.contains(sellerID) {
                            HStack {
                                ProgressView().padding(10).card()
                                Spacer()
                            }
                        }
                        Color.clear.frame(height: 1).id("chat-end")
                    }.padding(.horizontal, 16).padding(.bottom, 12)
                }.onChange(of: store.messages[sellerID]?.count) { _, _ in
                    withAnimation(Theme.spring) { proxy.scrollTo("chat-end", anchor: .bottom) }
                }
            }
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickReplies, id: \.self) { text in Chip(title: text) { send(text) }
                        }
                    }.padding(.horizontal, 16)
                }
                HStack(spacing: 8) {
                    Button {
                        send("Reference photo attached (demo).")
                    } label: {
                        Image(systemName: "camera").frame(width: 44, height: 44).background(
                            Theme.bone, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Attach demo photo")
                    TextField("Message", text: $draft, axis: .vertical).lineLimit(1...4).rescueFont(
                        16
                    ).padding(12).card(radius: 22).accessibilityIdentifier("message-input")
                    Button {
                        let text = draft
                        draft = ""
                        send(text)
                    } label: {
                        Image(systemName: "arrow.up").frame(width: 44, height: 44).foregroundStyle(
                            Theme.paper
                        ).background(Theme.ink, in: Circle())
                    }.buttonStyle(.plain).disabled(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ).accessibilityLabel("Send message").accessibilityIdentifier("send-message")
                }.padding(.horizontal, 16)
            }.padding(.vertical, 8).background(Theme.ivory)
        }.task {
            store.activeChat = sellerID
            await store.loadMessages(sellerID)
        }.onDisappear { if store.activeChat == sellerID { store.activeChat = nil } }
            .navigationTitle(seller.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        router.backFromChat()
                    } label: {
                        Image(systemName: "chevron.left")
                    }.accessibilityLabel("Back")
                }
            }
    }
    private func send(_ text: String) {
        Haptic.tap()
        Task { await store.send(text, to: sellerID) }
    }
}
