import SwiftUI

/// Friends / Local / Global boards from `GET /v1/boards/:scope?metric=`.
/// My rank is pinned at the bottom; Local asks for opt-in on `409 local_opt_in_required`.
struct LeaderboardsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthService.self) private var auth

    @State private var scope: BoardScope = .friends
    @State private var metric: BoardMetric = .steps
    @State private var board: BoardResponse?
    @State private var isLoading = false
    @State private var error: String?
    @State private var needsLocalOptIn = false
    @State private var showFriends = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Board", selection: $scope) {
                    ForEach(BoardScope.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Metric", selection: $metric) {
                    ForEach(BoardMetric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                content
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .parchmentBackground()
            .navigationTitle("Leaderboards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFriends = true } label: { Image(systemName: "person.2.fill") }
                        .accessibilityLabel("Friends")
                        .disabled(!auth.isSignedIn)
                }
            }
            .sheet(isPresented: $showFriends, onDismiss: { Task { await load() } }) { FriendsView() }
            .task(id: "\(scope.rawValue)-\(metric.rawValue)-\(auth.isSignedIn)") { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !auth.isSignedIn {
            SignedOutPrompt()
        } else if needsLocalOptIn {
            localOptInPrompt
        } else if let board {
            boardList(board)
        } else if isLoading {
            Spacer()
            ProgressView("Consulting the scribes…").tint(ParchmentTheme.crimson)
            Spacer()
        } else if let error {
            Spacer()
            Text(error).font(ParchmentTheme.body(.footnote)).foregroundStyle(ParchmentTheme.crimson)
            RetroButton("Retry") { Task { await load() } }
            Spacer()
        } else {
            Spacer()
        }
    }

    private func boardList(_ board: BoardResponse) -> some View {
        VStack(spacing: 0) {
            HStack {
                if let region = board.region, scope == .local {
                    Label(region, systemImage: "mappin.and.ellipse")
                }
                Spacer()
                if let week = board.week, metric == .steps { Text("Week \(week)") }
            }
            .font(ParchmentTheme.body(.caption, weight: .semibold))
            .foregroundStyle(ParchmentTheme.inkSoft)
            .padding(.bottom, 6)

            List {
                if board.entries.isEmpty {
                    Text(scope == .friends ? "No friends ranked yet. Invite a companion!" : "No one has ranked yet this week.")
                        .font(ParchmentTheme.body(.footnote))
                        .foregroundStyle(ParchmentTheme.inkSoft)
                        .listRowBackground(Color.clear)
                }
                ForEach(board.entries) { entry in
                    BoardRow(rank: entry.rank, name: entry.displayName, value: format(entry.value),
                             detail: entry.heroLevel.map { "Lv.\($0)" }, isMe: entry.isMe)
                        .listRowBackground(entry.isMe ? ParchmentTheme.goldLight.opacity(0.55) : ParchmentTheme.parchmentLight.opacity(0.5))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await load() }

            // Pinned "me" row.
            Group {
                if let me = board.me {
                    BoardRow(rank: me.rank, name: auth.player?.displayName ?? "You", value: format(me.value), detail: "You", isMe: true)
                } else {
                    Text(metric == .steps ? "Walk this week to get ranked." : "Not ranked yet.")
                        .font(ParchmentTheme.body(.footnote))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .parchmentPanel(padding: 10)
            .padding(.vertical, 8)
        }
    }

    private var localOptInPrompt: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "map.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(ParchmentTheme.goldGradient)
            Text("Join your local board?").font(ParchmentTheme.display(22))
            Text("Compete with walkers in your city. Your region comes from your network connection (city level) — never your exact location. You can leave anytime in Settings.")
                .font(ParchmentTheme.body(.subheadline))
                .multilineTextAlignment(.center)
                .foregroundStyle(ParchmentTheme.inkSoft)
            RetroButton("Join Local Board", systemImage: "checkmark.seal.fill") {
                Task {
                    do {
                        try await auth.update(PatchMeRequest(localOptIn: true))
                        needsLocalOptIn = false
                        await load()
                    } catch {
                        self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            }
            Button("Not now") { scope = .global }
                .font(ParchmentTheme.body(.footnote))
            Spacer()
        }
        .padding()
    }

    private func load() async {
        guard auth.isSignedIn else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            board = try await model.api.board(scope: scope, metric: metric)
            needsLocalOptIn = false
        } catch let apiError as APIError where scope == .local && apiError.isLocalOptInRequired {
            board = nil
            needsLocalOptIn = true
        } catch {
            board = nil
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func format(_ value: Int) -> String {
        switch metric {
        case .steps: value.grouped
        case .level: "Lv.\(value)"
        case .zone: "Ch. \(Roman.numeral(value))"
        }
    }
}

private struct BoardRow: View {
    let rank: Int
    let name: String
    let value: String
    let detail: String?
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: rank)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(ParchmentTheme.body(.subheadline, weight: isMe ? .heavy : .semibold))
                    .foregroundStyle(ParchmentTheme.ink)
                if let detail {
                    Text(detail).font(ParchmentTheme.body(.caption2)).foregroundStyle(ParchmentTheme.inkSoft)
                }
            }
            Spacer()
            Text(value).font(ParchmentTheme.numeric(16)).foregroundStyle(ParchmentTheme.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RankBadge: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(ParchmentTheme.numeric(rank < 100 ? 15 : 11))
            .foregroundStyle(rank <= 3 ? ParchmentTheme.ink : ParchmentTheme.parchmentLight)
            .frame(width: 34, height: 34)
            .background(Circle().fill(fill))
            .overlay(Circle().stroke(ParchmentTheme.goldDeep, lineWidth: 1.5))
    }

    private var fill: AnyShapeStyle {
        switch rank {
        case 1: AnyShapeStyle(ParchmentTheme.goldGradient)
        case 2: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xEEEEEE), Color(hex: 0x9EA3A8)], startPoint: .top, endPoint: .bottom))
        case 3: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xE0A060), Color(hex: 0x8C5A2B)], startPoint: .top, endPoint: .bottom))
        default: AnyShapeStyle(ParchmentTheme.sepia)
        }
    }
}

/// Shown on online-only screens when there's no session.
struct SignedOutPrompt: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 50))
                .foregroundStyle(ParchmentTheme.inkSoft)
            Text("Sign in to see the boards").font(ParchmentTheme.display(20))
            Text("Your hero plays fine offline. Leaderboards and friends need an account.")
                .font(ParchmentTheme.body(.subheadline))
                .multilineTextAlignment(.center)
                .foregroundStyle(ParchmentTheme.inkSoft)
            RetroButton("Sign In") { auth.playsOffline = false }
            Spacer()
        }
        .padding()
    }
}
