import SwiftUI

struct MessagesView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    var body: some View {
        List {
            Text("Coordinate your pickups here").rescueFont(15).foregroundStyle(Theme.secondary)
                .listRowSeparator(.hidden)
            ForEach(store.messageSellers) { seller in
                Button {
                    router.chat(seller.id)
                } label: {
                    HStack(spacing: 12) {
                        Avatar(seller: seller, size: 52)
                            .overlay(alignment: .bottomTrailing) {
                                if let item = store.pinnedListing(for: seller.id) {
                                    FoodPhoto(name: item.image).frame(width: 24, height: 24)
                                        .clipShape(RoundedRectangle(cornerRadius: 7)).overlay(
                                            RoundedRectangle(cornerRadius: 7).stroke(
                                                Theme.ivory, lineWidth: 2)
                                        ).offset(x: 3, y: 3)
                                }
                            }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(seller.name).rescueFont(16, .semibold)
                                Spacer()
                                Text("Today").rescueFont(12).foregroundStyle(Theme.muted)
                            }
                            Text(store.pinnedListing(for: seller.id)?.name ?? "Pickup coordination")
                                .rescueFont(13).foregroundStyle(Theme.muted)
                            Text(
                                store.messages[seller.id]?.last?.text
                                    ?? (store.isBackend
                                        ? "Start a conversation" : "Hi! Confirmed for your pickup.")
                            ).rescueFont(15).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                    }.padding(.vertical, 6).foregroundStyle(Theme.ink)
                }.listRowBackground(Theme.ivory).accessibilityIdentifier("chat-\(seller.id)")
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(Theme.ivory)
            .navigationTitle("Messages")
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        Text(
                            store.isBackend
                                ? "Persistent local demo conversation" : "Today · mock conversation"
                        ).rescueFont(12).foregroundStyle(
                            Theme.muted
                        ).padding(.vertical, 8)
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
                                        message.outgoing ? Theme.ink : Theme.paper,
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
