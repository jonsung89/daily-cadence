import SwiftUI

// MARK: - Catalog model

/// One section of the emoji picker's full browseable catalog.
/// Category-name + emoji-list pairs. Designed so any feature that
/// needs an emoji input can supply its own catalog (e.g., a future
/// reactions feature might pass a different shape) — but most
/// callers will just use `EmojiCatalog.default`.
struct EmojiCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let emojis: [String]
}

/// Pre-built catalogs reusable across features. The default catalog
/// is ~100 hand-picked emojis across six "everyday journaling /
/// special day / reaction" categories — covers the realistic
/// vocabulary without dragging in 3500 random food / office /
/// transit emojis. Swap in a larger catalog later (CLDR-derived,
/// for example) if a future feature needs the full set; the
/// `EmojiPickerSheet` view doesn't care about size.
enum EmojiCatalog {
    /// DailyCadence default — the catalog `EmojiPickerSheet` falls
    /// back to when a caller doesn't supply one. Curated for
    /// special-day marks, mood tagging, future reactions.
    static let `default`: [EmojiCategory] = [
        EmojiCategory(
            id: "celebrations",
            title: "Celebrations",
            emojis: ["🎂", "🎉", "🎊", "🎈", "🎁", "🍾", "🥂", "🥳", "💐", "🌹", "🎀", "✨", "🎆", "🎇", "🪅", "🍰", "🧁", "🎓"]
        ),
        EmojiCategory(
            id: "hearts",
            title: "Hearts",
            emojis: ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟"]
        ),
        EmojiCategory(
            id: "faces",
            title: "Faces & people",
            emojis: ["😀", "😊", "🥹", "🥰", "😍", "🤩", "😎", "🤗", "🤔", "😴", "🤯", "🥺", "😭", "😢", "😤", "🙏", "👶", "💍"]
        ),
        EmojiCategory(
            id: "food",
            title: "Food & drink",
            emojis: ["🍕", "🍔", "🌮", "🍣", "🍝", "🍩", "🍪", "🍫", "🍿", "🍦", "☕", "🍵", "🍺", "🍷", "🍹", "🥑", "🍎", "🍓"]
        ),
        EmojiCategory(
            id: "places",
            title: "Travel & places",
            emojis: ["✈️", "🚗", "🚂", "🚢", "🏠", "🏡", "🏖️", "⛰️", "🏔️", "🗽", "🗼", "🏰", "🌅", "🌆", "🌃", "🏝️", "🌋", "🌈"]
        ),
        EmojiCategory(
            id: "symbols",
            title: "Symbols",
            emojis: ["⭐", "🌟", "💫", "🔥", "💎", "💯", "❗", "❓", "🎯", "📅", "🗓️", "⏰", "📌", "📍", "🏆", "🥇", "🌙", "☀️"]
        ),
    ]

    /// Lightweight `emoji → [keyword]` map for search. Every
    /// catalog emoji should have at least one keyword; the
    /// category title is also matched separately so users can
    /// search "celebration" and get the whole section. Keep
    /// keywords lowercase, ASCII when possible.
    static let keywords: [String: [String]] = [
        "🎂": ["cake", "birthday", "candle"],
        "🎉": ["party", "popper", "confetti", "celebration"],
        "🎊": ["confetti", "ball", "celebration"],
        "🎈": ["balloon", "party"],
        "🎁": ["gift", "present", "ribbon"],
        "🍾": ["champagne", "bottle", "drink", "celebration"],
        "🥂": ["cheers", "toast", "glasses", "drink"],
        "🥳": ["party", "celebrate", "face"],
        "💐": ["bouquet", "flowers"],
        "🌹": ["rose", "flower", "love"],
        "🎀": ["ribbon", "bow"],
        "✨": ["sparkle", "magic", "special"],
        "🎆": ["fireworks"],
        "🎇": ["sparkler", "fireworks"],
        "🪅": ["pinata"],
        "🍰": ["cake", "slice", "dessert"],
        "🧁": ["cupcake", "dessert"],
        "🎓": ["graduation", "graduate", "cap", "school"],

        "❤️": ["heart", "red", "love"],
        "🧡": ["heart", "orange"],
        "💛": ["heart", "yellow"],
        "💚": ["heart", "green"],
        "💙": ["heart", "blue"],
        "💜": ["heart", "purple"],
        "🖤": ["heart", "black"],
        "🤍": ["heart", "white"],
        "🤎": ["heart", "brown"],
        "❣️": ["heart", "exclamation"],
        "💕": ["hearts", "love"],
        "💞": ["hearts", "revolving"],
        "💓": ["heart", "beating"],
        "💗": ["heart", "growing"],
        "💖": ["heart", "sparkle", "love"],
        "💘": ["heart", "arrow", "cupid"],
        "💝": ["heart", "ribbon", "gift"],
        "💟": ["heart", "decoration"],

        "😀": ["smile", "happy", "grin"],
        "😊": ["smile", "blush", "happy"],
        "🥹": ["holding back tears"],
        "🥰": ["love", "smile", "hearts"],
        "😍": ["heart", "eyes", "love"],
        "🤩": ["star", "eyes", "wow"],
        "😎": ["sunglasses", "cool"],
        "🤗": ["hug", "happy"],
        "🤔": ["thinking", "wonder"],
        "😴": ["sleep", "zzz"],
        "🤯": ["mind", "blown", "shocked"],
        "🥺": ["pleading", "puppy"],
        "😭": ["crying", "sad", "tears"],
        "😢": ["cry", "tear", "sad"],
        "😤": ["frustrated", "huff"],
        "🙏": ["pray", "thanks", "thank you"],
        "👶": ["baby", "newborn", "infant"],
        "💍": ["ring", "engagement", "wedding"],

        "🍕": ["pizza", "food"],
        "🍔": ["burger", "food"],
        "🌮": ["taco", "food"],
        "🍣": ["sushi", "food"],
        "🍝": ["pasta", "spaghetti"],
        "🍩": ["donut", "doughnut", "dessert"],
        "🍪": ["cookie", "dessert"],
        "🍫": ["chocolate", "dessert"],
        "🍿": ["popcorn", "movie"],
        "🍦": ["ice cream", "dessert"],
        "☕": ["coffee", "drink"],
        "🍵": ["tea", "drink"],
        "🍺": ["beer", "drink"],
        "🍷": ["wine", "drink"],
        "🍹": ["cocktail", "drink", "tropical"],
        "🥑": ["avocado", "food"],
        "🍎": ["apple", "fruit"],
        "🍓": ["strawberry", "fruit"],

        "✈️": ["airplane", "travel", "flight"],
        "🚗": ["car", "drive"],
        "🚂": ["train", "locomotive"],
        "🚢": ["ship", "boat"],
        "🏠": ["home", "house"],
        "🏡": ["house", "garden", "home"],
        "🏖️": ["beach", "vacation"],
        "⛰️": ["mountain"],
        "🏔️": ["mountain", "snow"],
        "🗽": ["statue", "liberty"],
        "🗼": ["tower", "tokyo"],
        "🏰": ["castle"],
        "🌅": ["sunrise"],
        "🌆": ["city", "sunset", "cityscape"],
        "🌃": ["night", "stars", "city"],
        "🏝️": ["island"],
        "🌋": ["volcano"],
        "🌈": ["rainbow", "pride"],

        "⭐": ["star"],
        "🌟": ["star", "glowing"],
        "💫": ["star", "dizzy"],
        "🔥": ["fire", "hot", "lit"],
        "💎": ["diamond", "gem"],
        "💯": ["100", "hundred", "perfect"],
        "❗": ["exclamation", "alert", "important"],
        "❓": ["question"],
        "🎯": ["target", "bullseye"],
        "📅": ["calendar", "date"],
        "🗓️": ["calendar", "spiral"],
        "⏰": ["alarm", "clock", "time"],
        "📌": ["pin", "pushpin"],
        "📍": ["pin", "round", "location"],
        "🏆": ["trophy", "win", "award"],
        "🥇": ["medal", "first", "gold"],
        "🌙": ["moon", "crescent", "night"],
        "☀️": ["sun", "sunny", "day"],
    ]
}

// MARK: - Recent emojis (per-feature, persisted)

/// Lightweight per-feature recent-emoji tracker. Each `EmojiPickerSheet`
/// caller passes a unique `recentStorageKey` so day-marks recents don't
/// pollute (future) reaction recents and vice versa.
private struct RecentEmojiTracker {
    let storageKey: String
    var emojis: [String]
    private let limit: Int

    init(storageKey: String, limit: Int = 10) {
        self.storageKey = storageKey
        self.limit = limit
        self.emojis = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
    }

    mutating func record(_ emoji: String) {
        emojis.removeAll { $0 == emoji }
        emojis.insert(emoji, at: 0)
        if emojis.count > limit { emojis = Array(emojis.prefix(limit)) }
        UserDefaults.standard.set(emojis, forKey: storageKey)
    }
}

// MARK: - View

/// Reusable bottom-sheet emoji picker. Shape mirrors iOS-native
/// reaction trays (Messenger, Discord, iMessage): search bar → quick
/// picks ("Commonly used") → recent (per-feature) → categorized full
/// catalog. Selection commits and dismisses; an optional Remove
/// surfaces when something's already selected.
///
/// Each calling feature passes its own `commonlyUsed` curation and
/// `recentStorageKey` so the quick-pick row + recents reflect that
/// feature's vocabulary. The browseable `catalog` defaults to
/// `EmojiCatalog.default` (~100 emojis), but any caller can override
/// it (e.g., a future feature that needs the full Unicode set).
struct EmojiPickerSheet: View {
    /// Sheet header — small caption above the title (e.g.,
    /// "Mark this day").
    let subtitle: String?
    /// Sheet header — bold title (e.g., the day name, or
    /// "React").
    let title: String
    /// Curated quick-pick row. Different per feature: special-day
    /// marks vs. message reactions vs. mood tagging would each
    /// pass a different list.
    let commonlyUsed: [String]
    /// `UserDefaults` key for this feature's recent-emoji list.
    /// Per-feature so recents stay relevant ("recent reactions"
    /// shouldn't surface a birthday cake the user marked yesterday).
    let recentStorageKey: String
    /// Browseable catalog. Sectioned, scrollable. Defaults to
    /// `EmojiCatalog.default`; a feature with broader needs can
    /// pass its own.
    let catalog: [EmojiCategory]
    /// Currently-selected emoji, if any. Highlighted across all
    /// surfaces (commonly used, recent, catalog) so the user can
    /// see their existing pick at a glance.
    let currentSelection: String?
    /// Fires when the user picks any emoji. Caller dismisses the
    /// sheet. The sheet records the pick into its recent list
    /// before calling out — caller doesn't need to plumb that.
    let onSelect: (String) -> Void
    /// Fires when the user taps Remove. `nil` hides the Remove
    /// button entirely (use for features where "no selection"
    /// isn't a state the user can request).
    let onRemove: (() -> Void)?

    @State private var searchQuery: String = ""
    @State private var recentTracker: RecentEmojiTracker

    init(
        subtitle: String? = nil,
        title: String,
        commonlyUsed: [String],
        recentStorageKey: String,
        catalog: [EmojiCategory] = EmojiCatalog.default,
        currentSelection: String? = nil,
        onSelect: @escaping (String) -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.subtitle = subtitle
        self.title = title
        self.commonlyUsed = commonlyUsed
        self.recentStorageKey = recentStorageKey
        self.catalog = catalog
        self.currentSelection = currentSelection
        self.onSelect = onSelect
        self.onRemove = onRemove
        self._recentTracker = State(initialValue: RecentEmojiTracker(storageKey: recentStorageKey))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            searchField
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if isSearching {
                        searchResultsSection
                    } else {
                        commonlyUsedSection
                        if !recentTracker.emojis.isEmpty {
                            recentSection
                        }
                        ForEach(catalog) { category in
                            catalogSection(category)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, onRemove != nil && currentSelection != nil ? 80 : 16)
            }

            if onRemove != nil, currentSelection != nil {
                removeFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.DS.bg1)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .center, spacing: 4) {
            if let subtitle {
                Text(subtitle)
                    .font(.DS.caption)
                    .foregroundStyle(Color.DS.fg2)
            }
            Text(title)
                .font(.DS.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.DS.ink)
        }
        .frame(maxWidth: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.DS.fg2)
            TextField("Search emojis", text: $searchQuery)
                .font(.DS.body)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.DS.fg2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.DS.bg2)
        )
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        let results = filteredEmojis()
        if results.isEmpty {
            VStack(spacing: 6) {
                Text("No matches")
                    .font(.DS.body)
                    .foregroundStyle(Color.DS.fg2)
                Text("Try a different word.")
                    .font(.DS.caption)
                    .foregroundStyle(Color.DS.fg2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)
        } else {
            emojiGrid(results)
        }
    }

    private var commonlyUsedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Commonly used")
            emojiGrid(commonlyUsed)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Recent")
            emojiGrid(recentTracker.emojis)
        }
    }

    private func catalogSection(_ category: EmojiCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(category.title)
            emojiGrid(category.emojis)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.DS.caption)
            .foregroundStyle(Color.DS.fg2)
            .padding(.horizontal, 4)
    }

    /// 6-column emoji grid — slightly tighter than the curated picker
    /// so denser sections (categories) don't run too tall. Cells are
    /// transparent with a sage-deep ring + sage-soft halo + scale-up
    /// on the currently-selected emoji (matches the rest of the
    /// design system — selection is a ring, not a fill).
    private func emojiGrid(_ emojis: [String]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6),
            spacing: 8
        ) {
            ForEach(emojis, id: \.self) { emoji in
                emojiTile(emoji)
            }
        }
    }

    private func emojiTile(_ emoji: String) -> some View {
        let isCurrent = emoji == currentSelection
        return Button {
            recentTracker.record(emoji)
            onSelect(emoji)
        } label: {
            Text(emoji)
                .font(.system(size: 28))
                .frame(maxWidth: .infinity, minHeight: 44)
                .scaleEffect(isCurrent ? 1.08 : 1.0)
                .background(
                    Circle()
                        .fill(isCurrent ? Color.DS.sageSoft.opacity(0.5) : Color.clear)
                        .padding(2)
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            isCurrent ? Color.DS.sageDeep : Color.clear,
                            lineWidth: 1.5
                        )
                        .padding(2)
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isCurrent)
        .accessibilityLabel("Pick \(emoji)")
    }

    private var removeFooter: some View {
        VStack(spacing: 0) {
            Divider().background(Color.DS.border1)
            Button {
                onRemove?()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                    Text("Remove")
                        .font(.DS.body)
                }
                .foregroundStyle(Color.DS.fg2)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.DS.bg2)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.DS.bg1)
    }

    // MARK: - Search

    /// Whether the search field has a non-trivial query (≥1 non-
    /// whitespace character). When true, the body swaps from the
    /// sectioned layout to a flat results grid.
    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Filters the union of `commonlyUsed` + recent + catalog by the
    /// search query. Matching emojis surface in a flat de-duplicated
    /// list. Match strategies (in order):
    ///   1. The query is an emoji character itself — match exactly.
    ///   2. Substring against any keyword in `EmojiCatalog.keywords`.
    ///   3. Substring against the emoji's containing category title.
    ///   4. Substring against `commonlyUsed` membership label.
    private func filteredEmojis() -> [String] {
        let query = searchQuery
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !query.isEmpty else { return [] }

        var seen = Set<String>()
        var ordered: [String] = []

        let allEmojis: [String] = {
            var combined: [String] = []
            combined.append(contentsOf: commonlyUsed)
            combined.append(contentsOf: recentTracker.emojis)
            for cat in catalog { combined.append(contentsOf: cat.emojis) }
            return combined
        }()

        // Build a quick reverse-lookup of emoji → category title for
        // category-name matching, so "celebration" surfaces all of
        // Celebrations.
        let categoryByEmoji: [String: String] = {
            var map: [String: String] = [:]
            for cat in catalog {
                for emoji in cat.emojis {
                    map[emoji] = cat.title.lowercased()
                }
            }
            return map
        }()

        for emoji in allEmojis where !seen.contains(emoji) {
            let isExactEmoji = emoji == searchQuery
            let keywordHit = (EmojiCatalog.keywords[emoji] ?? [])
                .contains(where: { $0.contains(query) })
            let categoryHit = (categoryByEmoji[emoji] ?? "").contains(query)
            if isExactEmoji || keywordHit || categoryHit {
                seen.insert(emoji)
                ordered.append(emoji)
            }
        }
        return ordered
    }
}

#Preview("Day mark, light") {
    Text("Long press a day")
        .sheet(isPresented: .constant(true)) {
            EmojiPickerSheet(
                subtitle: "Mark this day",
                title: "Wednesday, April 29",
                commonlyUsed: ["🎂", "🎉", "❤️", "💍", "⭐", "✨", "🎁", "🎈", "🍾", "🥂", "👶", "🎓", "🌈", "✈️", "🏠", "❗", "📅", "🏆", "💐", "🌙"],
                recentStorageKey: "preview.daymarks.recent",
                currentSelection: nil,
                onSelect: { _ in },
                onRemove: nil
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
}

#Preview("Marked, dark") {
    Text("Long press a day")
        .sheet(isPresented: .constant(true)) {
            EmojiPickerSheet(
                subtitle: "Mark this day",
                title: "Wednesday, April 29",
                commonlyUsed: ["🎂", "🎉", "❤️", "💍", "⭐", "✨", "🎁", "🎈", "🍾", "🥂", "👶", "🎓", "🌈", "✈️", "🏠", "❗", "📅", "🏆", "💐", "🌙"],
                recentStorageKey: "preview.daymarks.recent",
                currentSelection: "🎂",
                onSelect: { _ in },
                onRemove: { }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
}
