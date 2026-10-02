import SwiftUI

/// Invite codes (share via ShareLink), accept a friend's code, list and remove friends.
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var invite: InviteResponse?
    @State private var code = ""
    @State private var friends: [FriendSummary] = []
    @State private var message: String?
    @State private var isError = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let invite {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(invite.code)
                                .font(ParchmentTheme.numeric(34))
                                .tracking(6)
                                .foregroundStyle(ParchmentTheme.ink)
                                .textSelection(.enabled)
                            if let url = URL(string: invite.url) {
                                ShareLink(item: url,
                                          subject: Text("Join me in Stepquest"),
                                          message: Text("Walk with me in Stepquest! My invite code is \(invite.code).")) {
                                    Label("Share Invite", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.retro)
                            }
                            if let expires = invite.expiresAt {
                                Text("Expires \(expires)").font(ParchmentTheme.body(.caption2)).foregroundStyle(ParchmentTheme.inkSoft)
                            }
                        }
                    } else {
                        RetroButton("Create Invite Code", systemImage: "envelope.badge") { Task { await createInvite() } }
                            .disabled(working)
                    }
                } header: { header("Invite a Companion") }
                .listRowBackground(ParchmentTheme.parchmentLight.opacity(0.6))

                Section {
                    HStack {
                        TextField("Friend's code", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(ParchmentTheme.numeric(18))
                        Button("Accept") { Task { await accept() } }
                            .buttonStyle(.retro)
                            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    }
                    if let message {
                        Text(message)
                            .font(ParchmentTheme.body(.footnote))
                            .foregroundStyle(isError ? ParchmentTheme.crimson : ParchmentTheme.forestGreen)
                    }
                } header: { header("Enter a Code") }
                .listRowBackground(ParchmentTheme.parchmentLight.opacity(0.6))

                Section {
                    if friends.isEmpty {
                        Text("No companions yet.").font(ParchmentTheme.body(.footnote)).foregroundStyle(ParchmentTheme.inkSoft)
                    }
                    ForEach(friends) { friend in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(friend.displayName).font(ParchmentTheme.body(.subheadline, weight: .bold))
                                Text("Lv.\(friend.heroLevel) · Chapter \(Roman.numeral(max(1, friend.zone)))")
                                    .font(ParchmentTheme.body(.caption2))
                                    .foregroundStyle(ParchmentTheme.inkSoft)
                            }
                            Spacer()
                            Text(friend.weekSteps.grouped).font(ParchmentTheme.numeric(15))
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { Task { await remove(friend) } }
                        }
                    }
                } header: { header("Companions (\(friends.count))") }
                .listRowBackground(ParchmentTheme.parchmentLight.opacity(0.6))
            }
            .scrollContentBackground(.hidden)
            .parchmentBackground()
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task { await loadFriends() }
            .refreshable { await loadFriends() }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased()).font(ParchmentTheme.display(12)).tracking(1.5).foregroundStyle(ParchmentTheme.goldDeep)
    }

    private func createInvite() async {
        working = true
        defer { working = false }
        do { invite = try await model.api.createInvite() } catch { show(error) }
    }

    private func accept() async {
        working = true
        defer { working = false }
        let trimmed = code.trimmingCharacters(in: .whitespaces).uppercased()
        do {
            let friend = try await model.api.acceptInvite(code: trimmed)
            isError = false
            message = "\(friend.displayName) is now your friend!"
            code = ""
            await loadFriends()
        } catch {
            show(error)
        }
    }

    private func loadFriends() async {
        do { friends = try await model.api.friends() } catch { show(error) }
    }

    private func remove(_ friend: FriendSummary) async {
        do {
            try await model.api.removeFriend(playerId: friend.id)
            friends.removeAll { $0.id == friend.id }
        } catch { show(error) }
    }

    private func show(_ error: Error) {
        isError = true
        message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
