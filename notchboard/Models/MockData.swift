//
//  MockData.swift
//  notchboard
//
//  First-launch seed data (vision.md §6). Two catalogues live here:
//
//  - `workspace()` is the sample a new user starts from. It ships with **no members and no
//    claims**. Notchboard works alone, and inventing colleagues meant a solo user opened the
//    app to three rows claimed by people who don't exist — permanently, since you can't
//    release someone else's claim and the auto-release sweep skips foreign claims.
//  - `demoWorkspace()` keeps the fictional team, for showing the collaboration concept off.
//    It is never seeded automatically; load it deliberately.
//
//  Element ids are fixed UUID literals rather than the short `u1`/`p1`/`c1` strings they used
//  to be. Keychain account keys are "<elementID>.<fieldKey>" with no collection component, so
//  two catalogues seeded from here would otherwise share secrets and clobber each other.
//  Fixed (not freshly generated) so the sample stays comparable across calls.
//

import Foundation

enum MockData {
    /// The fictional team, used only by `demoWorkspace()`.
    static let demoMembers: [String: NBMember] = [
        "tom": NBMember(id: "tom", name: "Tom Verhoeven"),
        "sara": NBMember(id: "sara", name: "Sara Kim"),
        "mia": NBMember(id: "mia", name: "Mia Novak"),
    ]

    private static let usersFields = [
        NBField(key: "username", label: "username", type: .text),
        NBField(key: "password", label: "password", type: .secret),
    ]
    private static let productsFields = [
        NBField(key: "sku", label: "sku", type: .text),
        NBField(key: "price", label: "price", type: .number),
        NBField(key: "stock", label: "in_stock", type: .bool),
        NBField(key: "tier", label: "tier", type: .picker),
    ]
    private static let promosFields = [
        NBField(key: "discount_pct", label: "discount_%", type: .number),
        NBField(key: "expires", label: "expires", type: .date),
        NBField(key: "single_use", label: "single_use", type: .bool),
    ]
    private static let endpointsFields = [
        NBField(key: "base_url", label: "base_url", type: .url),
        NBField(key: "token", label: "token", type: .secret),
    ]

    /// An empty catalogue with one group to type into — the "start empty" onboarding path.
    static func emptyWorkspace(name: String = "my-catalogue") -> NBWorkspace {
        let users = NBGroup(
            id: "users", label: "users", singular: "user", secondaryKey: "username",
            fields: usersFields, elements: []
        )
        return NBWorkspace(name: name, groupOrder: ["users"], groups: ["users": users], members: [:])
    }

    /// The sample catalogue: realistic test data, nobody else's claims on it.
    static func workspace() -> NBWorkspace {
        let users = NBGroup(
            id: "users", label: "users", singular: "user", secondaryKey: "username",
            fields: usersFields,
            elements: [
                NBElement(id: "6D0E1C1E-0001-4A00-9000-000000000001", name: "Ava Lindqvist", env: .dev, isFavorite: true,
                          claimedBy: nil,
                          note: "hit ⚡ login on sim to fire the debug deeplink — set your app's scheme in settings",
                          lastUsed: "today",
                          values: ["username": "ava.lindqvist@acme.dev", "password": "Corr3ct-horse!"]),
                NBElement(id: "6D0E1C1E-0001-4A00-9000-000000000002", name: "Empty State", env: .dev, isFavorite: false,
                          claimedBy: nil,
                          note: "brand new account — triggers every empty-state screen",
                          lastUsed: "2 days ago",
                          values: ["username": "qa.empty@acme.dev", "password": "Empty#2026"]),
                NBElement(id: "6D0E1C1E-0001-4A00-9000-000000000003", name: "Premium Annual", env: .dev, isFavorite: false,
                          claimedBy: nil,
                          note: "active subscription, renews 07/12",
                          lastUsed: "yesterday",
                          values: ["username": "premium.annual@acme.dev", "password": "G0ld-tier#"]),
                NBElement(id: "6D0E1C1E-0001-4A00-9000-000000000004", name: "No Payment Method", env: .stg, isFavorite: false,
                          claimedBy: nil,
                          note: "no card on file — use for checkout error path",
                          lastUsed: "today",
                          values: ["username": "qa.nopay@acme.dev", "password": "N0pay-2026"]),
                NBElement(id: "6D0E1C1E-0001-4A00-9000-000000000005", name: "Fresh Signup", env: .dev, isFavorite: false,
                          claimedBy: nil,
                          note: "onboarding incomplete, stops at step 2",
                          lastUsed: "4 days ago",
                          values: ["username": "fresh.signup@acme.dev", "password": "Fresh#001"]),
                NBElement(id: "6D0E1C1E-0001-4A00-9000-000000000006", name: "Locale DE", env: .stg, isFavorite: false,
                          claimedBy: nil,
                          note: "German locale, EUR currency, VAT edge cases",
                          lastUsed: "last week",
                          values: ["username": "qa.de@acme.dev", "password": "Str4sse!9"]),
                NBElement(id: "6D0E1C1E-0001-4A00-9000-000000000007", name: "Heavy Cart", env: .stg, isFavorite: false,
                          claimedBy: nil,
                          note: "42 items in cart — perf + scroll testing",
                          lastUsed: "3 days ago",
                          values: ["username": "qa.cart@acme.dev", "password": "C4rt-heavy"]),
                NBElement(id: "6D0E1C1E-0001-4A00-9000-000000000008", name: "PRD Smoke", env: .prd, isFavorite: false,
                          claimedBy: nil,
                          note: "READ ONLY — smoke tests only, never mutate",
                          lastUsed: "last release",
                          values: ["username": "smoke@acme.dev", "password": "••managed••"]),
            ]
        )

        let products = NBGroup(
            id: "products", label: "products", singular: "product", secondaryKey: "sku",
            fields: productsFields,
            elements: [
                NBElement(id: "6D0E1C1E-0002-4A00-9000-000000000001", name: "Flat White Beans 1kg", env: .dev, isFavorite: true,
                          claimedBy: nil, note: "hero product, always in stock", lastUsed: "today",
                          values: ["sku": "BW-1041", "price": "18.50", "stock": "true", "tier": "core"]),
                NBElement(id: "6D0E1C1E-0002-4A00-9000-000000000002", name: "Decaf Blend 250g", env: .dev, isFavorite: false,
                          claimedBy: nil, note: "", lastUsed: "—",
                          values: ["sku": "BW-2010", "price": "7.90", "stock": "true", "tier": "core"]),
                NBElement(id: "6D0E1C1E-0002-4A00-9000-000000000003", name: "Grinder Pro X", env: .dev, isFavorite: false,
                          claimedBy: nil, note: "out of stock — tests the back-in-stock flow", lastUsed: "yesterday",
                          values: ["sku": "HW-0007", "price": "249.00", "stock": "false", "tier": "premium"]),
                NBElement(id: "6D0E1C1E-0002-4A00-9000-000000000004", name: "Gift Card 25", env: .stg, isFavorite: false,
                          claimedBy: nil, note: "digital delivery, no shipping step", lastUsed: "—",
                          values: ["sku": "GC-0025", "price": "25.00", "stock": "true", "tier": "core"]),
                NBElement(id: "6D0E1C1E-0002-4A00-9000-000000000005", name: "Subscription Sampler", env: .stg, isFavorite: false,
                          claimedBy: nil, note: "recurring — triggers subscription upsell", lastUsed: "last week",
                          values: ["sku": "SB-0110", "price": "39.00", "stock": "true", "tier": "premium"]),
            ]
        )

        let promos = NBGroup(
            id: "promos", label: "promos", singular: "promo", secondaryKey: "discount_pct",
            fields: promosFields,
            elements: [
                NBElement(id: "6D0E1C1E-0003-4A00-9000-000000000001", name: "WELCOME10", env: .dev, isFavorite: true,
                          claimedBy: nil, note: "new accounts only", lastUsed: "today",
                          values: ["discount_pct": "10", "expires": "2026-12-31", "single_use": "true"]),
                NBElement(id: "6D0E1C1E-0003-4A00-9000-000000000002", name: "FREESHIP", env: .dev, isFavorite: false,
                          claimedBy: nil, note: "", lastUsed: "—",
                          values: ["discount_pct": "0", "expires": "2026-09-01", "single_use": "false"]),
                NBElement(id: "6D0E1C1E-0003-4A00-9000-000000000003", name: "VIP25", env: .stg, isFavorite: false,
                          claimedBy: nil, note: "premium tier only", lastUsed: "today",
                          values: ["discount_pct": "25", "expires": "2026-08-15", "single_use": "true"]),
                NBElement(id: "6D0E1C1E-0003-4A00-9000-000000000004", name: "BLACKFRI", env: .stg, isFavorite: false,
                          claimedBy: nil, note: "stacks with FREESHIP — known bug NB-112", lastUsed: "2 days ago",
                          values: ["discount_pct": "40", "expires": "2026-11-27", "single_use": "false"]),
            ]
        )

        // Second real use case beyond logins, and the only group exercising the `url` field
        // type — the API roots you'd otherwise paste from a note into Proxyman.
        let endpoints = NBGroup(
            id: "endpoints", label: "endpoints", singular: "endpoint", secondaryKey: "base_url",
            fields: endpointsFields,
            elements: [
                NBElement(id: "6D0E1C1E-0004-4A00-9000-000000000001", name: "API dev", env: .dev, isFavorite: false,
                          claimedBy: nil, note: "resets nightly at 02:00 UTC", lastUsed: "today",
                          values: ["base_url": "https://api.dev.acme.dev", "token": "dev-5f2a91c4"]),
                NBElement(id: "6D0E1C1E-0004-4A00-9000-000000000002", name: "API staging", env: .stg, isFavorite: false,
                          claimedBy: nil, note: "mirrors prod schema, seeded data", lastUsed: "yesterday",
                          values: ["base_url": "https://api.stg.acme.dev", "token": "stg-77b30ee1"]),
                NBElement(id: "6D0E1C1E-0004-4A00-9000-000000000003", name: "API prod", env: .prd, isFavorite: false,
                          claimedBy: nil, note: "READ ONLY — never point a debug build here", lastUsed: "—",
                          values: ["base_url": "https://api.acme.dev", "token": ""]),
            ]
        )

        return NBWorkspace(
            name: "acme-mobile",
            groupOrder: ["users", "products", "promos", "endpoints"],
            groups: ["users": users, "products": products, "promos": promos, "endpoints": endpoints],
            members: [:]
        )
    }

    /// The sample catalogue plus the fictional team holding a few claims — for demoing what
    /// collaboration looks like. Not used on first launch.
    static func demoWorkspace() -> NBWorkspace {
        var workspace = workspace()
        workspace.members = demoMembers

        func claim(_ elementID: String, in groupID: String, by who: String, minutesAgo: Int) {
            guard var group = workspace.groups[groupID],
                  let index = group.elements.firstIndex(where: { $0.id == elementID }) else { return }
            group.elements[index].claimedBy = NBClaim(who: who, minutesAgo: minutesAgo)
            workspace.groups[groupID] = group
        }

        claim("6D0E1C1E-0001-4A00-9000-000000000001", in: "users", by: "tom", minutesAgo: 14)
        claim("6D0E1C1E-0001-4A00-9000-000000000004", in: "users", by: "sara", minutesAgo: 41)
        claim("6D0E1C1E-0003-4A00-9000-000000000003", in: "promos", by: "mia", minutesAgo: 6)
        return workspace
    }
}
