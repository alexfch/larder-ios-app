# Larder
### Product Requirements Document — Home Food Warehouse & Pantry Inventory Application

| | |
|---|---|
| **Document status** | Draft — Updated from interactive prototype |
| **Version** | 2.0 (supersedes 1.0 "HomeStock" draft) |
| **Prepared for** | Development Team |
| **Product owner** | Home Food Warehouse Program |
| **Date** | August 25, 2026 |
| **Platforms** | iOS, Android (React Native) + Cloud Backend |

*Grounded in a review of existing pantry/warehouse inventory apps (Sortly, KitchenPal, Pantry Check, Pantry Inventory Tracker, Portions Master) and validated against the "Larder" interactive prototype (v1 and v2).*

---

## 1. Document Control

| Field | Detail |
|---|---|
| Product name | Larder (renamed from working title "HomeStock" to match the prototype) |
| Document type | Product Requirements Document (PRD) |
| Version | 2.0 — Draft for engineering review |
| Author | Product Management |
| Date | August 25, 2026 |
| Status | Updated to reflect the interactive "Larder" prototype (v1 and v2 explorations) |
| Distribution | Engineering, Design, QA, Release Management |

### Revision History

| Version | Date | Author | Summary |
|---|---|---|---|
| 0.1 | 2026-08-10 | Product | Initial research and competitive scan |
| 1.0 | 2026-08-24 | Product | First development-ready draft, based on competitor research only |
| 2.0 | 2026-08-25 | Product | Rewritten against the "Larder" interactive prototype: batch/lot-based stock model, check-out-first navigation, new inventory count/stock-take epic, and a rescoped v1.0 (single user, single location) with household sharing, multi-location, and low-stock alerts moved to Phase 2 on the strength of a working v1 prototype exploration. |

---

## 2. What Changed Since the v1.0 Draft

This revision replaces assumptions drawn from competitor research with decisions grounded in a working interactive prototype the team built and iterated on twice (an initial exploration, referred to below as **v1**, and a deliberately simplified follow-up, **v2**). Where the prototype validated a different approach than the original PRD assumed, this document now follows the prototype. The table below is a change log for anyone who reviewed the 1.0 draft.

| Area | v1.0 draft assumed | Prototype shows | Resolution in this PRD |
|---|---|---|---|
| Expiration tracking | One expiration date per inventory item. | Every check-in creates a dated batch ("lot"). An item can hold several batches at once, each with its own date; check-out draws from the earliest batch first, or a batch the user picks. | Data model and all check-in/out requirements rewritten around batches (Section 9). |
| Navigation model | Generic dashboard with a persistent search bar. | Three bottom tabs — CHECK OUT (opens by default), CHECK IN, STOCK — each opening directly into the relevant action, not a neutral home screen. | Core flows and IA rewritten around the three-tab structure (Section 7). |
| Multi-location storage | Must-have for v1.0: user-defined locations (Pantry, Fridge, Freezer, Garage). | v2 deliberately drops locations ("pantry only"). v1 had them, with a working chip-filter UI. | Locations moved to Phase 2 — de-risked, since a working version already exists in the v1 prototype (Section 8.9). |
| Low-stock alerts | Must-have for v1.0: per-item minimum threshold with alerts. | v2 deliberately drops thresholds ("no thresholds"). v1 had a per-item minimum with a LOW tag and filter. | Moved to Phase 2 alongside locations, on the same prototype evidence (Section 8.10). |
| Household / multi-user sharing | Must-have for v1.0: multiple accounts, one shared inventory, real-time sync. | v2 has no sign-in at all. v1 had PIN sign-in per family member with Admin/Member roles and every movement signed with a name. | v1.0 rescoped to a single operator on a single device. Multi-user sharing with attribution moves to Phase 2, using the v1 sign-in pattern as the starting design (Section 8.8). |
| Transaction history | An immutable audit log. | History is correctable by design: swiping a row left reveals EDIT and REMOVE, and removing a movement automatically rolls the stock balance back. | FR rewritten to specify a correctable log rather than an immutable one (Section 8.6). |
| Shopping list | Must-have for v1.0: auto-generated from low-stock triggers. | Not present in either prototype. The v1 prototype's own "try next" notes list it as a future idea, not a built flow. | Downgraded from Must to a Phase 2/3 candidate, dependent on low-stock alerts shipping first (Section 8.10). |
| Physical inventory counting | Not covered. | A full stock-take workflow exists in both prototypes: checklist or barcode "scan sweep" counting, a numeric keypad for entering counts, a diff/adjust review screen with tagged reasons (Used, Spoiled, Miscount, Given away), and apply/discard. | New Epic 8.7, written from the prototype in full. |
| Item type / unit of measure | Implicit — quantity and a unit field. | Every item has an explicit "kind": Whole units (counted, with a noun like tin/jar/carton) or Weight/Volume (bulk, tracked in grams or millilitres, auto-rolling up to kg/L in the UI above 1000). | Added as a first-class data model concept (Section 9) and as a required field on the New Product form (Section 8.3). |

---

## 3. Executive Summary

Larder is a mobile-first application for a home food warehouse — a pantry, fridge, freezer, or backup storage area — built around three actions: **check something in**, **check something out**, and **see what's on the shelf**. Every check-in creates a dated batch of stock; every check-out draws down the oldest batch first (or a specific one the user chooses), so the app always knows not just how much of something exists but when each portion of it needs to be used. Items without a barcode — produce, bulk-bin goods, leftovers, home-canned jars — are added through the same quick form used for everything else, with a simple toggle for whether the item is counted in whole units (tins, jars, cartons) or by weight/volume (grams, millilitres).

Two rounds of interactive prototyping shaped this document. An initial exploration (v1) modeled a full household feature set — PIN sign-in per family member, named storage locations, per-item low-stock thresholds, and a "quick out" multi-item basket. A follow-up (v2) deliberately stripped this back to the smallest version that is still genuinely useful day to day: one person, one shelf, dated batches, and a proper physical inventory count workflow that neither prototype's predecessor apps (nor the original competitor research) had considered. This PRD adopts v2 as the v1.0 build target and carries v1's richer household/location/threshold model forward as a de-risked Phase 2, since it already exists as a working design.

### Goals

- Let a single person check food in and out fast enough — barcode scan or a short manual form — that the shelf record stays accurate day to day.
- Track stock as dated batches so the app always knows what's oldest, not just how much exists in total.
- Support items that will never have a barcode as a first-class flow, not an afterthought.
- Give the household a real physical stock-take workflow, so the digital record can be reconciled against what's actually on the shelf.

### Non-Goals (for v1.0)

- Multiple household members, sign-in, or per-person attribution (prototyped in v1; deferred to Phase 2 — Section 8.8).
- Named storage locations beyond a single pantry (prototyped in v1; deferred to Phase 2 — Section 8.9).
- Low-stock alerts and an auto-generated shopping list (prototyped in v1 in part; neither is in v2; deferred — Section 8.10).
- Recipe recommendations, meal planning, or nutrition coaching.
- Commercial/industrial warehouse features such as pallet tracking or ERP integration.

---

## 4. Problem Statement & Opportunity

Households that stock a deep pantry or a backup supply lose track of what they own — not just how much, but how old it is. A single "expiration date" field per item, the model most consumer pantry apps use, breaks down the moment a household restocks something before finishing what's already open: the old and new stock get silently merged, and the app can no longer tell you to use the older one first. This is the specific gap Larder is built to close, alongside the two problems every reviewed competitor already addresses reasonably well — fast capture (barcode-first, manual fallback) and knowing what's expiring soon.

**Opportunity:** a fast, batch-aware inventory app for a home food warehouse that treats "when did this batch arrive and when does it expire" as core data, not an afterthought — with a genuine physical stock-take workflow for the periodic reconciliation every warehouse, however small, eventually needs.

---

## 5. Competitive Research Summary

The table below summarizes the consumer and small-business inventory products reviewed during initial discovery, and what Larder still takes from each. This research shaped the original feature set; the prototype (Section 2) then reshaped how much of it belongs in v1.0 versus later phases.

| Product | Category | What it does well | What Larder takes from it |
|---|---|---|---|
| KitchenPal | Pantry/grocery app | Reliable barcode scanning against a 5M+ product library; multi-location organization; auto-detected expiry for produce. | Barcode-first capture as the default path in both Check In and Check Out. |
| Pantry Check | Pantry/grocery app | Crowd-sourced barcode database with user-submitted product info; usage-based shopping list; inventory + usage timeline. | Usage/movement timeline as the basis for the per-item History view (Section 8.6). |
| Pantry Inventory Tracker | Pantry app (offline-first) | Fully offline-capable; scans pull data from Open Food Facts; quick custom-item add when no barcode; per-item minimum-quantity alerts. | Open Food Facts as the recommended barcode data source (Section 8.4); per-item threshold model informs the Phase 2 low-stock epic. |
| Portions Master | AI kitchen app | Two capture modes — barcode scan and photo/image recognition of a shelf. | Treat barcode scanning and manual/photo entry as equally supported paths; photo capture on the New Product form. |
| Sortly | Small-business inventory (non-food) | Explicit check-in/check-out transaction model; low-stock and date-based alerts; activity history for audits; offline mode with sync. | Transactional check-in/check-out with a movement log; the Phase 2 low-stock model. |

*Sources: product listings and reviews for KitchenPal, Pantry Check, Pantry Inventory Tracker, Portions Master, and Sortly (Google Play, App Store, Capterra, Software Advice, and vendor sites), reviewed August 2026, plus the Larder interactive prototype (v1 and v2), reviewed August 2026.*

---

## 6. Target Users & Personas

v1.0 is built for a single primary operator managing one shelf. The personas below describe who that operator typically is; the Family Organizer persona is only fully served once Phase 2 (household sharing) ships.

| Persona | Description | Primary need |
|---|---|---|
| The Bulk Stocker | Buys in bulk; keeps a deep pantry with overlapping batches of the same staple. | Know which batch is oldest so nothing gets pushed to the back and forgotten. |
| The Prepper / Long-Term Stocker | Maintains a rotated supply of long-shelf-life goods. | Batch-level expiry tracking and a reliable stock-take to catch drift between the record and reality. |
| The Family Organizer (Phase 2) | Runs a household where several people pull from the same stock. | Shared, attributed inventory — served once household sharing (Section 8.8) ships. |
| The Budget-Conscious Shopper | Wants to avoid duplicate purchases and reduce food waste. | Fast check of "do we already have this, and how old is it" while at the store. |

---

## 7. Scope

### 7.1 In Scope — v1.0 (matches the v2 prototype)

- Three-tab navigation: Check Out (default), Check In, Stock.
- Barcode scanning to check items in and out; a Manual Pick list as the no-camera fallback for both directions.
- Batch (lot) tracking: every check-in creates a dated batch; check-out draws from the earliest batch by default or a batch the user selects.
- New Product capture (barcode or manual) with a Whole units vs. Weight/Volume toggle, optional photo, and an initial check-in as part of saving.
- Stock browser with search (name or barcode) and an "Expiring ≤ 14 days" filter.
- Per-item detail screen: on-hand total, earliest best-before, a list of batches on the shelf, and full movement history.
- Correctable transaction history: swipe a row to edit or remove a past movement, with the balance rolling back automatically.
- Physical inventory count (stock-take): checklist or scan-sweep counting, numeric keypad entry, a diff/adjust review with reason tags, and apply/discard.
- Toast confirmations after every check-in, check-out, edit, removal, and count application.

### 7.2 Deferred to Phase 2 — prototyped in v1, not in v1.0

- Multi-user household sharing with PIN sign-in, per-person roles, and movements signed with a name.
- Named storage locations (Pantry, Fridge, Freezer, Garage, etc.) with a location filter.
- Per-item low-stock thresholds and a LOW-stock indicator.
- "Quick Out" — a multi-item tray/basket check-out for taking several things out in one pass.

### 7.3 Out of Scope — not prototyped, candidate for Phase 2/3

- Auto-generated shopping list (depends on low-stock alerts landing first).
- Recipe suggestions, meal planning, or nutrition scoring.
- Budget/spend analytics and receipt scanning.
- Multi-household or commercial multi-warehouse support.
- Voice-based entry.

---

## 8. Core User Flows

| # | Flow | Trigger | Outcome |
|---|---|---|---|
| F1 | Check out — hub shortlist | User opens the app (Check Out is the default tab) | Sees the 5 items closest to their best-before date, each openable directly into the quantity sheet. |
| F2 | Check out — scan | User taps SCAN from the Check Out hub | Camera opens in check-out mode; a recognized code opens the quantity sheet pre-filled with the earliest batch. |
| F3 | Check out — manual pick | User taps MANUAL from the Check Out hub | A searchable list of all items opens; selecting one opens the quantity sheet. |
| F4 | Check in — scan | User unpacks groceries and taps SCAN from the Check In hub | A recognized code opens the quantity sheet in check-in mode; an unrecognized code routes to New Product. |
| F5 | Check in — manual / new product | Item has no barcode (produce, bulk, leftovers, home-canned goods) | New Product form captures name, kind, quantity, expiry, and optional photo, and performs an initial check-in on save. |
| F6 | Review a product's batches | User opens an item from Stock, a hub row, or search | Detail screen shows on-hand total, earliest best-before, every batch on the shelf, and full history. |
| F7 | Correct a past movement | User notices a check-in or check-out was logged wrong | Swiping the history row left reveals EDIT (change quantity/date) and REMOVE (undo, balance rolls back). |
| F8 | Run a stock-take | User taps COUNT from the Stock tab | A count session opens in Checklist or Scan sweep mode; counted lines are compared to book quantity on Review. |
| F9 | Apply a stock-take | User reviews counted quantities that differ from the book | Each differing line gets a reason tag; applying writes signed adjustment movements and updates balances. |

---

## 9. Functional Requirements

Requirements are grouped by epic and ordered to match the prototype's information architecture. Each requirement includes a priority (MoSCoW) and testable acceptance criteria in Given/When/Then form.

### 9.1 Epic: Check-Out & Check-In Hub

#### FR-1.1 — Check Out hub (default screen) `Must`

**User story:** As the person managing the shelf, I want the app to open straight into check-out with the things closest to going off, so I use the oldest stock first without having to search for it.

The app opens on the Check Out tab by default. It lists the 5 items with the nearest best-before date across all their batches, each showing on-hand quantity and a colour cue when a date is within 14 days. Two persistent actions, SCAN and MANUAL, sit below the list.

**Acceptance criteria**
- Given the app is opened cold, when it loads, then the Check Out tab is selected and its shortlist is populated from the item with the nearest best-before date downward.
- Given an item has multiple batches, when it appears in the shortlist, then the date shown is its earliest batch's date, not an average or the newest.
- Given the user taps a shortlist row, when tapped, then the check-out quantity sheet opens directly, pre-set to draw from that item's earliest batch.

#### FR-1.2 — Check In hub `Must`

**User story:** As the person putting groceries away, I want a dedicated check-in screen so scanning what I just bought is the first thing I see, not a generic home screen.

The Check In tab lists the 5 most recently checked-in movements (item, date/time, batch date, quantity added), with the same SCAN and MANUAL actions below.

**Acceptance criteria**
- Given a user switches to Check In, when the tab loads, then it shows the 5 most recent IN movements, most recent first.
- Given the user taps a recent row, when tapped, then it opens that item's detail screen rather than re-triggering a check-in.

#### FR-1.3 — Manual pick list `Must`

**User story:** As a user without a barcode to scan — or a product whose barcode is worn off — I want to find the item by name and proceed the same way I would have from a scan.

A searchable list of all items (filtered by name or barcode as the user types) opens the same quantity sheet used by scanning, in whichever mode (IN/OUT) the user arrived from. In Check In mode only, a "+ Add new product" action is also shown, since check-out requires the item to already exist.

**Acceptance criteria**
- Given the user is in Check Out → Manual, when they search, then only items already in stock are searchable (an item with zero total quantity is excluded or clearly marked unavailable).
- Given the user is in Check In → Manual, when the list loads, then a "+ Add new product" option appears above or below the search field.
- Given a search returns no matches, when this happens in Check In mode, then the user is prompted to add it as a new product with the typed text pre-filling the name field.

### 9.2 Epic: Batch (Lot) Tracking

#### FR-2.1 — Check-in creates a dated batch `Must`

**User story:** As the person restocking, I want each check-in to be recorded with its own date so older and newer stock of the same item never get silently merged.

Every check-in specifies a quantity and an expiration/best-before date. If a batch with the same date already exists for that item, the quantity is added to it; otherwise a new batch is created.

**Acceptance criteria**
- Given an item has no existing batch dated 2026-11-15, when a check-in of that date is confirmed, then a new batch is created with the entered quantity.
- Given an item already has a batch dated 2026-11-15, when another check-in of the same date is confirmed, then the quantities are combined into that one batch rather than creating a duplicate.
- Given a check-in is confirmed, when saved, then the item's on-hand total (shown on Stock, the hub, and the detail screen) increases by the checked-in quantity immediately.

#### FR-2.2 — Check-out draws from batches oldest-first, or a chosen batch `Must`

**User story:** As the person taking something off the shelf, I want the app to default to the oldest stock so nothing expires unused, but let me pick a specific batch when it matters.

The check-out quantity sheet defaults to drawing from the earliest-dated batch. When an item has more than one batch, the sheet shows a row of batch chips (quantity + date); tapping one changes which batch the check-out draws from. If the requested quantity exceeds the selected batch, the remainder is drawn from the next-earliest batch automatically.

**Acceptance criteria**
- Given an item has a single batch, when checked out, then no batch selector is shown — the sole batch is used.
- Given an item has two or more batches, when the check-out sheet opens, then batch chips are shown and the earliest is pre-selected.
- Given the user selects a specific batch and requests more than that batch holds, when confirmed, then the shortfall is drawn from the next-earliest batch(es) until the requested quantity is met.
- Given a batch's quantity reaches zero, when this happens, then the batch is removed from the item's batch list (it no longer appears in the detail screen or the batch selector).

#### FR-2.3 — Quantity formatting by item kind `Must`

**User story:** As a user tracking flour by the gram and tins by the tin, I want quantities displayed in a way that makes sense for each — not everything shown as a raw number.

Whole-unit items display as an integer plus their noun (e.g., "4 tins"). Weight/volume items display in their base unit (g or ml) below 1000, and roll up to kg or L (two decimal places) at or above 1000.

**Acceptance criteria**
- Given a bulk item has 750 g on hand, when displayed, then it reads "750 g".
- Given a bulk item has 1,400 g on hand, when displayed, then it reads "1.4 kg".
- Given a whole-unit item has 1 on hand, when displayed, then its noun is singular ("1 tin", not "1 tins"); at any other quantity the noun is plural.

### 9.3 Epic: New Product Capture

#### FR-3.1 — New Product form `Must`

**User story:** As a household member adding produce, bulk-bin goods, leftovers, or a barcode-less homemade item, I want a short form that gets it on the shelf in one pass.

The form captures: name (required), barcode (optional — blank means no barcode), a Whole units / Weight-Volume toggle, quantity and a unit label (a free-text noun for whole units, or g/ml for bulk), expiration date, and an optional photo. Saving performs an initial check-in using the entered quantity and date.

**Acceptance criteria**
- Given the user reached this form from a barcode scan with no match, when the form opens, then the barcode field is pre-filled with the scanned code and a note explains nothing was found on file.
- Given the user saves without a name, when they try, then the save is blocked with an inline prompt to enter a name first.
- Given the form is saved successfully, when saved, then the new item appears immediately in Stock, in search, and in the batch/history views, with its first batch already recorded.
- Given the user switches between Whole units and Weight/Volume, when switched, then the quantity/unit fields relabel accordingly (e.g., "Quantity" + "Unit name (jar, tin, egg…)" vs. "Amount checked in" + "Unit (g / ml)").

#### FR-3.2 — Photo capture on new products `Should`

**User story:** As a household member, I want to attach a photo to a product I've added so it's recognizable at a glance in lists.

The New Product form includes a photo capture control. Once set, the photo (or a placeholder derived from the item's initials if none is set) is reused everywhere the item appears in a list.

**Acceptance criteria**
- Given a user adds a photo, when saved, then that photo appears next to the item in Stock, hub rows, and the manual pick list.
- Given no photo is set, when the item appears in a list, then a monogram placeholder derived from its name is shown instead of a blank space.

### 9.4 Epic: Product Data & Barcode Lookup

#### FR-4.1 — External barcode product lookup `Must`

**User story:** As a user scanning a new product, I want its name and default unit auto-filled so I don't have to type them.

On an unrecognized barcode, the app queries an external open product database (recommended: Open Food Facts — EAN/UPC-indexed, no API key required) for name, brand, and package size, pre-filling the New Product form, and caches the result locally so the same barcode never needs a network call again. The interactive prototype simulates this against a fixed local list; this requirement covers the real integration needed for production.

**Acceptance criteria**
- Given a barcode not yet known locally, when scanned with connectivity available, then the app queries the lookup service and pre-fills available fields on the New Product form within 3 seconds under normal connectivity.
- Given the lookup returns no match or the device is offline, when this happens, then the user lands on the New Product form with just the scanned code filled in, with no error blocking them.
- Given a lookup succeeds, when the result is saved, then it is cached locally so the same barcode is recognized instantly on any future scan without a network call.

### 9.5 Epic: Stock Browser & Expiry Visibility

#### FR-5.1 — Stock list with search and expiry filter `Must`

**User story:** As a household member, I want to see everything on the shelf at once, sorted so what's expiring soonest is easy to find.

The Stock tab lists every item, sorted by earliest batch date (items with no date sort last), each row showing on-hand quantity, an expiry badge when a batch is within 14 days or already past its date, and a batch-count badge when an item has more than one batch. A search field filters by name or barcode; an "Expiring ≤ 14 days" chip filters to just those items.

**Acceptance criteria**
- Given items exist with different earliest dates, when Stock loads, then they are sorted soonest-first, with items that have no batches at all sorted to the end.
- Given an item has 2+ batches, when shown in the list, then a "N BATCHES" tag appears alongside its expiry badge.
- Given the user toggles the "Expiring ≤ 14 days" filter, when active, then only items with at least one batch due within 14 days are shown, and the filter chip is visually marked active.
- Given the search box has 2+ characters, when typed, then results update to match name or barcode substrings in near-real time.

#### FR-5.2 — Product detail screen `Must`

**User story:** As a household member, I want one place that shows everything about a product: how much I have, how old each portion is, and what's happened to it.

The detail screen shows the item's total on-hand quantity, its earliest best-before with a relative label ("in 3 days", "today", "12 days ago"), a list of every batch (quantity, date, relative label), and the item's full movement history. Check In and Check Out actions are always available at the bottom.

**Acceptance criteria**
- Given an item has no batches, when its detail screen is opened, then it shows "Nothing on the shelf. Check some in." instead of an empty batch list.
- Given an item has no movement history, when its detail screen is opened, then it shows "No movements yet." instead of an empty history list.
- Given the user taps Check Out or Check In from the detail screen, when tapped, then the quantity sheet opens for that specific item.

### 9.6 Epic: Correctable Transaction History

#### FR-6.1 — Movement history, editable and reversible `Must`

**User story:** As a household member, I want to fix a mis-entered check-in or check-out after the fact, and have the shelf balance correct itself automatically.

Every check-in and check-out creates a history entry (date, time, action, quantity, batch date) shown newest-first on the item's detail screen. Swiping a row left reveals EDIT (reopens the quantity sheet pre-filled with that movement's values) and REMOVE (deletes the entry and reverses its effect on the item's balance).

**Acceptance criteria**
- Given a user swipes a history row left, when the swipe passes a distance threshold, then EDIT and REMOVE controls are revealed; swiping right or tapping elsewhere closes them again.
- Given a user taps EDIT and changes the quantity or date, when saved, then the old movement's effect is undone and the new values are applied in a single balance update — the item is never left in an inconsistent intermediate state.
- Given a user taps REMOVE, when confirmed, then the movement is deleted from history and the item's balance is rolled back by exactly that movement's effect (an IN of 6 is subtracted; an OUT of 2 is added back).
- Given a removal or edit completes, when it completes, then a toast confirms what changed (e.g., "Movement removed — balance rolled back").

### 9.7 Epic: Inventory Count (Stock-Take)

This epic is new relative to the original PRD — it was not part of the competitor research, but was fully designed in both prototype iterations and is treated as a core v1.0 capability.

#### FR-7.1 — Start and run a count session `Must`

**User story:** As the person doing a periodic shelf check, I want to record what's actually there and compare it to what the app thinks, so drift between the two gets caught and fixed.

Tapping COUNT from the Stock tab starts a session (auto-numbered, e.g. "INV-862") with two entry modes: Checklist (tap any line, key in the actual quantity on a numeric keypad) and Scan sweep (scanning a barcode ticks that line at its current book quantity; scanning again opens the keypad to correct it). A progress bar shows counted lines out of total.

**Acceptance criteria**
- Given a count session is started, when the Stock tab is revisited before it's applied or discarded, then the same in-progress session resumes rather than starting a new one.
- Given Checklist mode, when a line is tapped, then a numeric keypad opens for that item, defaulting to blank (not the book value), and Save records the entered figure.
- Given Scan sweep mode, when a barcode is scanned for the first time in the session, then that line is ticked at its current book quantity, and the user is told to scan again to correct it if wrong.
- Given any line has been counted, when the count screen is viewed, then the progress bar and counted/total figures update immediately.

#### FR-7.2 — Blind count mode `Should`

**User story:** As someone who wants an honest count rather than a confirmation of what the app already believes, I want the option to hide the expected quantity while I'm counting.

A configurable "blind count" mode, when enabled, hides each line's book quantity during counting (both in the list and on the keypad) and only reveals expected-vs-counted differences on the Review/Adjust screen.

**Acceptance criteria**
- Given blind count mode is on, when a Checklist line is shown before being counted, then its book quantity is not displayed — only the item name and best-before appear.
- Given blind count mode is on, when the keypad opens for a line, then it shows "expected hidden until review" instead of the book figure.
- Given the count is reviewed (Section 9.7, FR-7.3), when the Adjust screen loads, then book vs. counted values are shown regardless of whether blind mode was used during counting.

#### FR-7.3 — Review, tag, and apply adjustments `Must`

**User story:** As the person closing out a stock-take, I want to see only what didn't match, understand why, and apply the fix in one action — or throw the whole count away if something went wrong.

Tapping Review moves to an Adjust screen listing only the lines where the counted quantity differs from book, each showing the delta and a set of reason chips (Used, Spoiled, Miscount, Given away — defaulting to Miscount). Apply writes a signed adjustment movement (IN if counted is higher, OUT if lower) against the item's earliest batch and updates the running balance; Discard exits with no changes made.

**Acceptance criteria**
- Given every counted line matches its book quantity, when Review is tapped, then the Adjust screen states there is nothing to adjust rather than showing an empty table.
- Given a line differs, when shown on Adjust, then its delta is signed (+/−) and a reason chip is pre-selected to Miscount, changeable by the user before applying.
- Given the user taps Apply, when applied, then one adjustment movement per differing line is written to history, item balances update to match the counted figures, and the count session closes.
- Given the user taps Discard, when confirmed, then no item balances change and the session is cleared, with a toast confirming the count was discarded.

---

## 10. Deferred Epics — Prototyped in v1, Scheduled for Phase 2

These capabilities were fully designed and interactive in the v1 prototype before being intentionally parked for v1.0's simpler scope (Section 2). They are listed here — rather than left as vague future ideas — because a working reference design already exists, which meaningfully de-risks scheduling them into Phase 2.

### 10.1 Household Sharing & Multi-User Sign-In

#### FR-8.1 — PIN sign-in per household member `Should (Phase 2)`

**User story:** As a family, we want everyone who uses the shelf to sign in briefly so movements can be attributed to a person, without the friction of a full account system.

A member-picker screen lists household members (name, initials, role — Admin or Member); selecting one prompts for a 4-digit PIN. Once entered, the app opens directly to Stock and every movement made in that session is tagged with the signed-in member's name.

**Acceptance criteria**
- Given a household has 2+ members configured, when the app opens, then the member picker is shown before any inventory screen.
- Given a member is selected and a correct PIN entered, when confirmed, then the session is attributed to that member and every check-in/out/adjustment records their name.
- Given a movement is shown in history, when viewed, then it displays who performed it alongside what and when.

#### FR-8.2 — Real-time shared inventory across devices `Should (Phase 2)`

**User story:** As a household, we want everyone's device to reflect the same shelf state, since we all draw from the same physical stock.

Once accounts exist (FR-8.1), inventory read/write extends from a single local device to a shared backend so all household devices converge on the same item, batch, and history state.

**Acceptance criteria**
- Given two household members are on different devices, when one checks an item in or out, then the other's view reflects the change within a few seconds under normal connectivity.
- Given two devices make conflicting offline changes to the same item, when both reconnect, then the changes are merged as additive quantity deltas rather than one overwriting the other.

### 10.2 Named Storage Locations

#### FR-9.1 — Multiple named locations with a filter `Should (Phase 2)`

**User story:** As a household with more than one storage spot, I want to organize stock by location (Pantry, Fridge, Freezer, Garage) and filter to just one.

Items carry a location field. The Stock screen gains a row of location chips (starting with "All" plus the household's configured locations) that filter the list; check-in and check-out record which location a movement applies to.

**Acceptance criteria**
- Given a household has configured locations, when Stock loads, then a chip row lets the user filter to one location or view all.
- Given an item is checked in, when the check-in sheet is used, then a location is required and defaults to that item's most recent location.

### 10.3 Low-Stock Alerts

#### FR-10.1 — Per-item minimum threshold and LOW indicator `Should (Phase 2)`

**User story:** As a household member, I want to be warned when something I track regularly is running low, so I can restock before running out.

Items optionally carry a minimum-quantity threshold. When on-hand total is at or below it, the item is flagged LOW in Stock and on its detail screen, and a Stock-level stat/filter shows how many items are currently low.

**Acceptance criteria**
- Given an item's threshold is set and its total drops to or below it, when this happens, then the item is tagged LOW wherever it's listed.
- Given the user taps the Low stat on Stock, when tapped, then the list filters to just items currently at or below their threshold.

### 10.4 Shopping List (Phase 2/3, not yet prototyped)

An auto-generated shopping list, seeded from items flagged LOW (Section 10.3), was noted as a future direction by the prototype's own designer but has no interactive design yet. It should be scoped and prototyped only after low-stock alerts are validated in production.

### 10.5 Quick Out (Multi-Item Basket Check-Out)

#### FR-11.1 — Step multiple items down in one tray, commit together `Could (Phase 2)`

**User story:** As someone cooking a meal that uses several pantry items at once, I want to adjust several quantities in one screen and commit them together, instead of repeating the single-item check-out flow.

A Quick Out screen lists every item with a stepper (−/quantity/+); the user adjusts as many as needed, then commits the whole tray as a single batch of check-out movements.

**Acceptance criteria**
- Given the user steps down two or more items in the tray, when they tap Commit, then one OUT movement is recorded per adjusted item, each tagged "quick out".
- Given the tray is empty, when the user looks at the commit control, then it is visibly disabled.

---

## 11. Non-Functional Requirements

| Category | Requirement |
|---|---|
| Performance | Barcode scan-to-result feedback in under 1 second on a mid-range device (2022+ hardware). Full check-in/out flow completable in under 5 seconds for a recognized item. |
| Offline capability | All check-in, check-out, manual entry, and count actions must work fully offline against local storage; any future sync (Phase 2, FR-8.2) is eventually consistent, not a blocking requirement. |
| Local data integrity | v1.0 is single-device: the app must guard against data loss on interrupted actions (e.g., killed mid-transaction) and should offer a local backup/export/restore mechanism given there is no account-based cloud backup yet. |
| Platforms | Native mobile experience on iOS and Android (recommended: single React Native codebase, consistent with the prototype's iOS-frame design system, for parity and shared release cadence). |
| Data privacy | Barcode lookups may be sent to an external product database but must contain no personal data. Once accounts exist (Phase 2), household inventory data is private to invited members only. |
| Accessibility | WCAG 2.1 AA target for all core flows: sufficient color contrast (the prototype's high-contrast, monospace-accented style supports this), screen-reader labels on scan/check-in/check-out/count controls, and a manual-entry path for any user who cannot use the camera scanner. |
| Reliability | No data loss on interrupted check-in/out or count-apply — actions are atomic and locally persisted before any network call. |
| Scalability | Support a catalog of up to 5,000 distinct items and, per item, a reasonable number of concurrent open batches (design and test up to 20) without list or detail-screen performance degradation. |
| Localization | English at launch; date and unit formatting (Section 9.2, FR-2.3) should not hard-code locale assumptions, to allow future localization. |

---

## 12. Data Model (Conceptual)

Rewritten around the prototype's actual shape: items own an embedded list of dated batches rather than carrying a single flat quantity and expiration date. This is intended to guide schema design, not to be a final DDL.

| Entity | Key Fields | Notes |
|---|---|---|
| Item | id, name, barcode (nullable), kind ('unit' \| 'bulk'), unit (g \| ml — bulk only), noun (e.g. tin, jar, carton — unit only), photo (nullable), lots[] | The core catalog + stock record. A barcode-less item (kind, form) is a first-class row, not a special case. |
| Lot (batch) | id, itemId, qty, exp (date) | A dated quantity received together. An item's on-hand total is the sum of its lots' quantities; its "earliest" date is the minimum exp across lots. |
| Transaction (movement) | id, itemId, action ('IN' \| 'OUT' \| 'ADJUST'), qty, exp (the batch it affected), date, time, [Phase 2] userId | Editable and reversible in the UI (Section 9.6) — not an immutable ledger. Reversal recomputes the affected lot's quantity. |
| CountSession | id/session no, mode ('list' \| 'scan'), counted (map of itemId → counted qty), reasons (map of itemId → reason label), status (in-progress \| applied \| discarded) | Applying a session writes one ADJUST transaction per differing item and closes the session; discarding leaves item state untouched. |
| [Phase 2] Household / Member | id, name, initials, role ('Admin' \| 'Member'), pin | Enables signed transactions (FR-8.1) and, with a backend, real-time shared state (FR-8.2). |
| [Phase 2] Location | id, name | Adds a location field to Item and to check-in/out movements (FR-9.1). |

---

## 13. Success Metrics

| Metric | Target (90 days post-launch) |
|---|---|
| Weekly active users (of installed base) | ≥ 50% |
| Median check-in/out actions per active user per week | ≥ 10 |
| % of check-ins completed via barcode scan (vs. manual/new product) | ≥ 60% |
| % of items with at least one dated batch (vs. no expiry recorded) | ≥ 70% |
| Stock-take (count) sessions completed per active user per month | ≥ 1 |
| % of counted lines within a session that require no adjustment | ≥ 85% (proxy for day-to-day record accuracy) |
| Crash-free session rate | ≥ 99.5% |
| Median scan-to-confirmation time | < 5 seconds |

---

## 14. Release Plan

### Phase 1 — MVP (Section 9, all Must and Should items)

- Check Out / Check In / Stock tab structure; scan and manual pick in both directions.
- Batch (lot) tracking with earliest-first consumption and batch selection.
- New Product capture with the unit/bulk kind toggle and optional photo.
- External barcode lookup (Open Food Facts) with local caching.
- Stock browser, per-item detail, and expiry filtering.
- Correctable transaction history (edit/remove with automatic balance rollback).
- Full inventory count workflow: checklist/scan-sweep, keypad entry, blind count option, diff/adjust review, apply/discard.

### Phase 2 — Household & Organization (de-risked by the v1 prototype)

- PIN sign-in per household member with signed movements (FR-8.1).
- Real-time shared inventory across devices (FR-8.2).
- Named storage locations with a filter (FR-9.1).
- Per-item low-stock thresholds and a LOW indicator (FR-10.1).
- Quick Out multi-item tray check-out (FR-11.1).

### Phase 3 — Exploratory (not committed)

- Shopping list auto-generated from low-stock items, once Phase 2 ships.
- Photo-based multi-item shelf recognition (as pioneered by Portions Master in the competitor scan).
- Recipe suggestions driven by current inventory.
- Multi-household support; budget and spend analytics via receipt scanning.

---

## 15. Risks & Assumptions

| Risk / Assumption | Type | Mitigation |
|---|---|---|
| Batch-level tracking adds real UI and logic complexity (batch selection, earliest-first draw, lot-merging on matching dates) versus a flat-quantity model. | Risk | Fully specified in Section 9.2 with acceptance criteria taken directly from working prototype behavior, reducing ambiguity for engineering. |
| Without accounts in v1.0, all data lives on a single device with no automatic backup. | Risk | Non-functional requirement for local export/backup (Section 11) called out explicitly; Phase 2 accounts resolve this properly. |
| External barcode database (Open Food Facts) has gaps, especially for regional/store-brand products. | Risk | Manual/New Product entry is a first-class, equally fast fallback (FR-3.1), not a degraded path. |
| Applying a stock-take adjustment against "the earliest batch" may misstate which specific batch was actually short or spoiled. | Risk | Acceptable for v1.0 given the reason-tagging UX (FR-7.3); revisit if user feedback shows this misattributes waste to the wrong batch. |
| Single-operator v1.0 may undersell the product to multi-person households who expected shared access from day one. | Risk | Messaging should be explicit that household sharing is a near-term Phase 2, not an abandoned idea — supported by an already-working v1 design. |
| Cross-platform codebase (React Native) is assumed sufficient for camera-based scanning performance. | Assumption | Validate against the <1 second scan-feedback NFR (Section 11) early in Phase 1 engineering. |

---

## 16. Open Questions for Engineering & Design

- What local backup/export mechanism should ship in v1.0 given there is no backend account yet — a file export, a device-native backup, or a lightweight anonymous cloud sync ahead of full Phase 2 accounts?
- Should the barcode lookup cache be pre-seeded for common products, or purely lazy-loaded on first scan?
- For stock-take adjustments, should the user ever be able to choose which specific batch absorbs the adjustment, rather than always defaulting to the earliest one?
- When Phase 2 introduces locations, should existing single-location v1.0 data migrate into a default "Pantry" location automatically, or prompt the user to assign locations retroactively?
- What conflict-resolution UI, if any, should surface to users once Phase 2 sync (FR-8.2) cannot resolve an offline conflict automatically?

---

## 17. Appendix

### A. Glossary

| Term | Definition |
|---|---|
| Check-in | The action of adding a dated batch of a product to on-hand stock. |
| Check-out | The action of removing quantity from on-hand stock, drawn from one or more batches. |
| Lot / Batch | A quantity of a single item received on a single date, tracked separately from other batches of the same item so expiry stays accurate per portion. |
| Kind (unit / bulk) | Whether an item is counted as whole units (tins, jars, cartons) or tracked continuously by weight/volume (grams, millilitres). |
| Stock-take / Count session | A session in which the physical shelf is counted and compared against the app's book quantities, producing signed adjustment movements for any differences. |
| Blind count | A count-session mode that hides book quantities from the counter until review, to avoid anchoring the physical count to the app's existing figure. |
| FIFO | First-in, first-out — the default batch-consumption order Larder uses on check-out: the earliest-dated batch is drawn from first. |

### B. Research Sources

- KitchenPal — Google Play Store listing and third-party pantry-app comparison roundups, reviewed August 2026.
- Pantry Check — Apple App Store listing, reviewed August 2026.
- Pantry Inventory Tracker (homestorageapp.com) — product site, reviewed August 2026.
- Portions Master — product site (portionsmaster.com), reviewed August 2026.
- Sortly — Capterra, Software Advice, Business.org reviews and sortly.com product pages, reviewed August 2026.
- Open Food Facts — world.openfoodfacts.org API documentation and OpenAPI specification, reviewed August 2026.
- Larder interactive prototype, v1 ("household food warehouse") and v2 ("single user, pantry only, batch-by-expiry") — internal design prototype, reviewed August 2026.
