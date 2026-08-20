//
//  SecretMaskingTests.swift
//  notchboardTests
//
//  Guards the list's half of the secrets posture (vision.md §13.16). The row subtitle used
//  to render `values[secondaryKey]` raw, and `secondaryKey` is always the group's first
//  field, so a group whose schema led with a secret printed it in cleartext on every row —
//  permanently, with no reveal toggle in sight. The seeded groups all happen to lead with a
//  non-secret field, which is why the leak stayed invisible.
//
//  The search tests pin the other half of the decision: a secret-typed value is not part of
//  the haystack, so no row can match on something the list refuses to display.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Secret masking in the element list")
struct SecretMaskingTests {

    /// A group whose FIRST field is secret-typed — the shape the seed data never produces
    /// and every user-defined group is free to.
    private static func secretFirstGroup(
        id: String = "tokens",
        secretKey: String = "api_token",
        elements: [NBElement]
    ) -> NBGroup {
        NBGroup(
            id: id, label: id, singular: "token",
            secondaryKey: secretKey,
            fields: [
                NBField(key: secretKey, label: "api token", type: .secret),
                NBField(key: "owner", label: "owner", type: .text)
            ],
            elements: elements
        )
    }

    private static func element(
        id: String = "e1", name: String = "ci runner",
        note: String = "", values: [String: String]
    ) -> NBElement {
        NBElement(
            id: id, name: name, environments: [.dev], isFavorite: false, claimedBy: nil,
            note: note, lastUsed: "", values: values
        )
    }

    /// A view model showing exactly `group`, with nothing else in the way.
    private static func viewModel(showing group: NBGroup) -> NotchboardViewModel {
        let vm = NotchboardViewModel()
        var workspace = vm.workspace
        workspace.groups[group.id] = group
        if !workspace.groupOrder.contains(group.id) {
            workspace.groupOrder.insert(group.id, at: 0)
        }
        vm.workspace = workspace
        vm.activeGroupID = group.id
        return vm
    }

    // MARK: - The row subtitle

    @Test("A group whose first field is secret masks the value in the row subtitle")
    func secretSecondaryFieldIsMasked() {
        let secret = "sk-live-9f3c2a7e"
        let element = Self.element(values: ["api_token": secret, "owner": "ci"])
        let group = Self.secretFirstGroup(elements: [element])
        let vm = Self.viewModel(showing: group)

        let subtitle = vm.secondaryText(for: group.elements[0], in: group)
        #expect(!subtitle.contains(secret), "the row printed the secret in cleartext: \(subtitle)")
        #expect(subtitle == NBGroup.secretMask)
    }

    @Test("The mask never varies with the secret it hides")
    func maskDoesNotLeakLength() {
        let group = Self.secretFirstGroup(elements: [
            Self.element(id: "short", values: ["api_token": "x"]),
            Self.element(id: "long", values: ["api_token": String(repeating: "y", count: 64)])
        ])
        let vm = Self.viewModel(showing: group)

        let short = vm.secondaryText(for: group.elements[0], in: group)
        let long = vm.secondaryText(for: group.elements[1], in: group)
        #expect(short == long, "a length-tracking mask hands out the secret's length")
    }

    @Test("A non-secret secondary field still renders its value")
    func nonSecretSecondaryFieldIsPlain() {
        let element = Self.element(values: ["api_token": "sk-1", "owner": "ci"])
        var group = Self.secretFirstGroup(elements: [element])
        group.secondaryKey = "owner"
        let vm = Self.viewModel(showing: group)

        #expect(vm.secondaryText(for: group.elements[0], in: group) == "ci")
    }

    @Test("An unset secret renders as nothing, not as a mask over a value that isn't there")
    func emptySecretRendersEmpty() {
        let group = Self.secretFirstGroup(elements: [
            Self.element(id: "blank", values: ["api_token": "", "owner": "ci"]),
            Self.element(id: "missing", values: ["owner": "ci"])
        ])
        let vm = Self.viewModel(showing: group)

        #expect(vm.secondaryText(for: group.elements[0], in: group).isEmpty)
        #expect(vm.secondaryText(for: group.elements[1], in: group).isEmpty)
    }

    /// `secondaryText`'s two group-id special cases (known debt, CLAUDE.md) name their fields
    /// directly instead of going through `secondaryKey`, so they are a second route past the
    /// mask. A user is free to call a group "promos" and mark its discount secret.
    @Test("The special-cased promos and products formats mask secret-typed fields too")
    func specialCasedFormatsAreMaskedToo() {
        let promoSecret = "40"
        let promos = NBGroup(
            id: "promos", label: "promos", singular: "promo", secondaryKey: "discount_pct",
            fields: [
                NBField(key: "discount_pct", label: "discount", type: .secret),
                NBField(key: "expires", label: "expires", type: .text)
            ],
            elements: [
                Self.element(name: "launch", values: ["discount_pct": promoSecret, "expires": "2026-12-01"])
            ]
        )

        let vmPromos = Self.viewModel(showing: promos)
        let promoSubtitle = vmPromos.secondaryText(for: promos.elements[0], in: promos)
        #expect(promoSubtitle.contains(NBGroup.secretMask), "promos bypassed the mask: \(promoSubtitle)")
        #expect(!promoSubtitle.contains("\(promoSecret)% off"), "promos printed the secret: \(promoSubtitle)")

        let sku = "SKU-CONFIDENTIAL-1"
        let products = NBGroup(
            id: "products", label: "products", singular: "product", secondaryKey: "sku",
            fields: [
                NBField(key: "sku", label: "sku", type: .secret),
                NBField(key: "price", label: "price", type: .text)
            ],
            elements: [Self.element(name: "widget", values: ["sku": sku, "price": "9.99"])]
        )
        let vmProducts = Self.viewModel(showing: products)
        let productSubtitle = vmProducts.secondaryText(for: products.elements[0], in: products)
        #expect(!productSubtitle.contains(sku), "products printed the secret: \(productSubtitle)")
        #expect(productSubtitle.contains(NBGroup.secretMask))
    }

    // MARK: - Search

    @Test("Search does not match secret-typed values")
    func searchIgnoresSecretValues() {
        let secret = "sk-live-9f3c2a7e"
        let element = Self.element(values: ["api_token": secret, "owner": "ci"])
        let group = Self.secretFirstGroup(elements: [element])
        let vm = Self.viewModel(showing: group)

        vm.searchText = secret
        #expect(vm.filteredElements.isEmpty, "a row matched on a value the list refuses to show")

        // A fragment is the same problem in slower motion — that is the oracle.
        vm.searchText = String(secret.prefix(6))
        #expect(vm.filteredElements.isEmpty)
    }

    @Test("Search still matches names, notes and non-secret values")
    func searchStillMatchesEverythingElse() {
        let element = Self.element(
            name: "ci runner", note: "shared with QA",
            values: ["api_token": "sk-1", "owner": "platform"]
        )
        let group = Self.secretFirstGroup(elements: [element])
        let vm = Self.viewModel(showing: group)

        for query in ["ci runner", "shared with QA", "platform"] {
            vm.searchText = query
            #expect(vm.filteredElements.count == 1, "“\(query)” should still find the row")
        }
    }
}
