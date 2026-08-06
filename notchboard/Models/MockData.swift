//
//  MockData.swift
//  notchboard
//
//  Seed data transcribed from the prototype (fictional "Brewly" coffee app), used purely
//  to drive the UI/UX layer for now — no backend/sync yet.
//

import Foundation

enum MockData {
    static let members: [String: NBMember] = [
        "tom": NBMember(id: "tom", name: "Tom Verhoeven"),
        "sara": NBMember(id: "sara", name: "Sara Kim"),
        "mia": NBMember(id: "mia", name: "Mia Novak"),
    ]

    static func workspace() -> NBWorkspace {
        let usersFields = [
            NBField(key: "username", label: "username", type: .text),
            NBField(key: "password", label: "password", type: .secret),
        ]
        let productsFields = [
            NBField(key: "sku", label: "sku", type: .text),
            NBField(key: "price", label: "price", type: .number),
            NBField(key: "stock", label: "in_stock", type: .bool),
            NBField(key: "tier", label: "tier", type: .picker),
        ]
        let promosFields = [
            NBField(key: "discount_pct", label: "discount_%", type: .number),
            NBField(key: "expires", label: "expires", type: .date),
            NBField(key: "single_use", label: "single_use", type: .bool),
        ]

        let users = NBGroup(
            id: "users", label: "users", singular: "user", secondaryKey: "username",
            fields: usersFields,
            elements: [
                NBElement(id: "u1", name: "Ava Lindqvist", env: .dev, isFavorite: true,
                          claimedBy: NBClaim(who: "tom", minutesAgo: 14),
                          note: "3 months of order history · card on file · notifications ON",
                          lastUsed: "today, by tom",
                          values: ["username": "ava.lindqvist@acme.dev", "password": "Corr3ct-horse!"]),
                NBElement(id: "u2", name: "Empty State", env: .dev, isFavorite: false,
                          claimedBy: nil,
                          note: "brand new account — triggers every empty-state screen",
                          lastUsed: "2 days ago, by mia",
                          values: ["username": "qa.empty@acme.dev", "password": "Empty#2026"]),
                NBElement(id: "u3", name: "Premium Annual", env: .dev, isFavorite: true,
                          claimedBy: nil,
                          note: "active subscription, renews 07/12",
                          lastUsed: "yesterday, by you",
                          values: ["username": "premium.annual@acme.dev", "password": "G0ld-tier#"]),
                NBElement(id: "u4", name: "No Payment Method", env: .stg, isFavorite: false,
                          claimedBy: NBClaim(who: "sara", minutesAgo: 41),
                          note: "no card on file — use for checkout error path",
                          lastUsed: "today, by sara",
                          values: ["username": "qa.nopay@acme.dev", "password": "N0pay-2026"]),
                NBElement(id: "u5", name: "Fresh Signup", env: .dev, isFavorite: false,
                          claimedBy: nil,
                          note: "onboarding incomplete, stops at step 2",
                          lastUsed: "4 days ago, by tom",
                          values: ["username": "fresh.signup@acme.dev", "password": "Fresh#001"]),
                NBElement(id: "u6", name: "Locale DE", env: .stg, isFavorite: false,
                          claimedBy: nil,
                          note: "German locale, EUR currency, VAT edge cases",
                          lastUsed: "last week, by mia",
                          values: ["username": "qa.de@acme.dev", "password": "Str4sse!9"]),
                NBElement(id: "u7", name: "Heavy Cart", env: .stg, isFavorite: false,
                          claimedBy: nil,
                          note: "42 items in cart — perf + scroll testing",
                          lastUsed: "3 days ago, by you",
                          values: ["username": "qa.cart@acme.dev", "password": "C4rt-heavy"]),
                NBElement(id: "u8", name: "PRD Smoke", env: .prd, isFavorite: false,
                          claimedBy: nil,
                          note: "READ ONLY — smoke tests only, never mutate",
                          lastUsed: "last release, by sara",
                          values: ["username": "smoke@acme.dev", "password": "••managed••"]),
            ]
        )

        let products = NBGroup(
            id: "products", label: "products", singular: "product", secondaryKey: "sku",
            fields: productsFields,
            elements: [
                NBElement(id: "p1", name: "Flat White Beans 1kg", env: .dev, isFavorite: false,
                          claimedBy: nil, note: "hero product, always in stock", lastUsed: "today, by tom",
                          values: ["sku": "BW-1041", "price": "18.50", "stock": "true", "tier": "core"]),
                NBElement(id: "p2", name: "Decaf Blend 250g", env: .dev, isFavorite: false,
                          claimedBy: nil, note: "", lastUsed: "—",
                          values: ["sku": "BW-2010", "price": "7.90", "stock": "true", "tier": "core"]),
                NBElement(id: "p3", name: "Grinder Pro X", env: .dev, isFavorite: true,
                          claimedBy: nil, note: "out of stock — tests the notify-me flow", lastUsed: "yesterday, by mia",
                          values: ["sku": "HW-0007", "price": "249.00", "stock": "false", "tier": "premium"]),
                NBElement(id: "p4", name: "Gift Card 25", env: .stg, isFavorite: false,
                          claimedBy: nil, note: "digital delivery, no shipping step", lastUsed: "—",
                          values: ["sku": "GC-0025", "price": "25.00", "stock": "true", "tier": "core"]),
                NBElement(id: "p5", name: "Subscription Sampler", env: .stg, isFavorite: false,
                          claimedBy: nil, note: "recurring — triggers subscription upsell", lastUsed: "last week, by you",
                          values: ["sku": "SB-0110", "price": "39.00", "stock": "true", "tier": "premium"]),
            ]
        )

        let promos = NBGroup(
            id: "promos", label: "promos", singular: "promo", secondaryKey: "discount_pct",
            fields: promosFields,
            elements: [
                NBElement(id: "c1", name: "WELCOME10", env: .dev, isFavorite: true,
                          claimedBy: nil, note: "new accounts only", lastUsed: "today, by sara",
                          values: ["discount_pct": "10", "expires": "2026-12-31", "single_use": "true"]),
                NBElement(id: "c2", name: "FREESHIP", env: .dev, isFavorite: false,
                          claimedBy: nil, note: "", lastUsed: "—",
                          values: ["discount_pct": "0", "expires": "2026-09-01", "single_use": "false"]),
                NBElement(id: "c3", name: "VIP25", env: .stg, isFavorite: false,
                          claimedBy: NBClaim(who: "mia", minutesAgo: 6), note: "premium tier only", lastUsed: "today, by mia",
                          values: ["discount_pct": "25", "expires": "2026-08-15", "single_use": "true"]),
                NBElement(id: "c4", name: "BLACKFRI", env: .stg, isFavorite: false,
                          claimedBy: nil, note: "stacks with FREESHIP — known bug NB-112", lastUsed: "2 days ago, by tom",
                          values: ["discount_pct": "40", "expires": "2026-11-27", "single_use": "false"]),
            ]
        )

        return NBWorkspace(
            name: "acme-mobile",
            groupOrder: ["users", "products", "promos"],
            groups: ["users": users, "products": products, "promos": promos],
            members: members
        )
    }
}
