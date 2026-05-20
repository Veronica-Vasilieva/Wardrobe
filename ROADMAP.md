# Wardrobe — Roadmap

A grouped, prioritised list of follow-up work. Items inside a tier are
roughly comparable in cost; tiers progress from quick wins to bigger
investments. **Order within a tier is the suggested working order** —
items at the top of a tier deliver visible improvements fastest.

Effort labels:
- **S** = ~30 min  — single focused edit
- **M** = ~1–2 h — touches a few functions, contained
- **L** = ~3–6 h — design work + code + testing
- **XL** = 1+ day — meaningful architectural change

Every item has a one-line **Why** so it's clear what problem it solves.

---

## Tier 1 — Hardening & known follow-ups

These address bugs or rough edges we've already noticed but haven't
fixed. Highest priority because they affect users today.

1. **Verify HIDE + enchant slot interaction.** [S]
   *Why:* Staging HIDE on Main hand enchant probably tries to click a
   "Hide item" option that doesn't exist (the enchant submenu has
   "Hide enchant" instead). Test, and if broken, make `HideSlot` look
   for either variant.
2. **Surface action errors more visibly.** [S]
   *Why:* "Open the Warpweaver first" lands in chat where it gets lost.
   Use `UIErrorsFrame:AddMessage` (the red top-of-screen banner) for
   user-facing failures.
3. **Debounce search-box typing.** [M]
   *Why:* Every keystroke runs a full `RefreshList`. Fast typists do 5+
   pointless rebuilds. Add a 100 ms debounce so we only refresh after
   typing pauses.
4. **Tab badges for staged slots.** [S]
   *Why:* Easy to forget which slots you've staged a preview on. Show
   a small gold dot or `[*]` on the tab's count column when
   `previewSlots[slotId]` is set.
5. **Persistent search across slot switches.** [S]
   *Why:* If you're hunting "Crusader" across multiple weapon slots,
   the search clears every time. Remember the last query (don't save
   to disk — session-local is enough).
6. **Throttle apply chain to slow servers.** [M]
   *Why:* `SCAN_STEP_DELAY = 0.10` works on local servers but high-
   latency servers may drop clicks. Detect timeout patterns and back
   off automatically.

## Tier 2 — Quality-of-life features

Visible improvements players will notice. Each is contained.

7. **Favourites system.** [M]
   *Why:* Players want to mark go-to appearances and pin them to the
   top of the list. Store `WardrobeDB.chars[key].favourites = {entry=true}`,
   sort favourites first, show a star icon.
8. **Hide-already-applied toggle.** [M]
   *Why:* Once you've used an item, seeing it in the list every visit
   is noise. Checkbox to filter it out. Reads `newItem->transmog` from
   gossip submenu's current state — or just track in
   `WardrobeDB.chars[key].applied`.
9. **Sort dropdown.** [M]
   *Why:* Currently fixed sort (quality desc, then name asc). Add Name
   asc, Name desc, Quality, "Recently scanned" — saved in
   `db.ui.sortOrder`.
10. **Quick clear button on search box.** [S]
    *Why:* `Esc` clears it but isn't discoverable. Add a small × on the
    right edge of the editbox.
11. **Right-click context menu on rows.** [M]
    *Why:* Apply / Try On / Favourite / Hide from List in one place
    instead of needing to know the shift/right-click convention.
12. **Keyboard navigation.** [M]
    *Why:* Tab to cycle slot tabs, Up/Down to move within the list,
    Enter to preview. Useful for power users.
13. **Bottom-bar Apply Preview shortcut.** [S]
    *Why:* Right now Apply Preview is in the doll column. Mirror it in
    the bottom bar so you don't have to look across the window.
14. **Confirmation popup before "Restore Original".** [S]
    *Why:* It's a destructive global action; one accidental click and
    every slot reverts. Add a Yes/No confirmation.

## Tier 3 — UI polish

Cosmetic but raises the perceived quality.

15. **Slot icons on tabs.** [M]
    *Why:* Tabs currently show text only. The gossip menu uses the
    actual slot icons (helmet, shoulder, etc.) — mirror those so the
    tab column matches the server's vocabulary.
16. **Doll slot indicators.** [M]
    *Why:* Visual dots around the model showing which slots are
    currently previewed. Helps users see at a glance what's staged.
17. **Outfit rename.** [S]
    *Why:* You can only delete and re-save. Add an "Edit Name" entry
    in the outfit dropdown context.
18. **Quality filter as proper dropdown.** [M]
    *Why:* The cycle button is awkward. Use a real dropdown with all
    levels visible at once.
19. **Better enchant row display.** [S]
    *Why:* Enchant rows show "Common" in the quality column because
    enchants have no quality. Show "Enchant" or leave it blank.
20. **Item-level filter slider.** [M]
    *Why:* Old players want to find low-iLvl vanity gear, raiders want
    current-tier looks. Slider above the list (e.g., 80–284).
21. **Apply-progress indicator.** [S]
    *Why:* When Apply Preview is committing 10 items, the user sees
    nothing happen for several seconds. Add a "Applying 4/10..." line.
22. **Resizable main frame.** [L]
    *Why:* Some users have small screens, some have ultrawide. Drag
    handles on the corners.
23. **Drag-to-reorder outfit list.** [M]
    *Why:* Favourites bubble to the top. Right now the order is fixed
    by save time.

## Tier 4 — New features

Bigger value adds. Each warrants design discussion before coding.

24. **Minimap button.** [M]
    *Why:* Browse / build outfits without being at the NPC. Apply still
    requires the NPC, but inspection doesn't.
25. **Random outfit generator.** [M]
    *Why:* Fun + helps players discover items they've forgotten about.
    Button: "Surprise me" rolls a random appearance per slot, stages
    the preview.
26. **Outfit sharing via chat.** [L]
    *Why:* Players want to share looks. `/wb share Tank PvP` posts a
    compact encoded string. Receiver pastes into a search-style box to
    import.
27. **Compare two outfits side-by-side.** [L]
    *Why:* Hard decisions between two looks. Two doll frames in a
    compare overlay.
28. **Class/role template outfits.** [M]
    *Why:* Ship a handful of "good defaults" per class/role to give
    new players a starting point.
29. **Per-slot lock when loading outfits.** [S]
    *Why:* Sometimes you want to keep your current shoulders but load
    everything else from an outfit. Pin a slot to exclude it from
    outfit-load.
30. **Achievement-style stats panel.** [M]
    *Why:* "You've collected 1,247 / 3,000 appearances. Best slot:
    Shoulders at 92 %." Fun completion metric.
31. **Per-character vs account-wide outfit preference.** [S]
    *Why:* Currently outfits are per-character. Some players want to
    share looks across alts (e.g., paladin → death knight plate). Add
    an "Account-wide" toggle on Save.

## Tier 5 — Architecture & maintenance

Pays off in iteration speed for everything above.

32. **Split Wardrobe.lua into multiple files.** [L]
    *Why:* It's currently ~2200 lines. Split into `Core.lua`, `Scan.lua`,
    `UI.lua`, `Outfits.lua`, `ServerSets.lua`. Easier diffs, easier
    onboarding.
33. ~~**Build script.**~~ ✅ Done — `build_release.py` lives at repo
    root. `python build_release.py` builds the zip in `dist/`;
    `python build_release.py --release` does the full GitHub flow
    with notes auto-extracted from CHANGELOG.md.
34. **Settings panel.** [L]
    *Why:* `/wb debug`, `/wb npcname`, and the BG checkbox are
    scattered. A proper settings frame with grouped checkboxes.
35. **Localization framework.** [XL]
    *Why:* Match AutoLoot's structure — a `Locale.lua` with key→string
    tables and per-language overlay files. Wraps every user-visible
    string in `L["…"]`. Not urgent but unlocks community translations.
36. **Lua tests for the parser.** [M]
    *Why:* `ParseItemOption`, `MatchesSlotLabel`, and `FindNavOptions`
    handle gossip text under many variants. A few asserts catching
    regressions would save debug cycles.

## Tier 6 — Server compatibility / discovery

Make the addon work on more variants than just Ebonhold/Valanior.

37. **Auto-detect server fork variant.** [L]
    *Why:* Some servers run vanilla Rochet2, some Sunwell, some
    AzerothCore mod-transmog. Sniff the main-menu fingerprint and
    pick the right parser strategy automatically.
38. **NPC auto-discovery.** [M]
    *Why:* Currently the NPC name list is hard-coded with `/wb npcname`
    as an escape hatch. When a gossip menu *looks* like Rochet2-style
    transmog, ask the user "Add this NPC?" with a one-click button.
39. **`/wb diag` command.** [S]
    *Why:* Outputs version, server, character, scan timestamp, slot
    counts, etc. Paste into bug reports.
40. **Documentation for other server admins.** [M]
    *Why:* `docs/SERVER_COMPAT.md` describing the gossip protocol
    expectations so other server runners can verify (or fix) their
    fork.

---

## Suggested first-week order

If you want a concrete plan for the next few sessions, this is the
order I'd recommend, picking from each tier to mix quick wins with
deeper work:

1. **Day 1** — items 1, 2, 4, 5, 19 (T1/T3 quick polish bundle, ~2 h total)
2. **Day 2** — item 3 (debounce) + item 14 (confirmation popup) +
   item 13 (Apply Preview in bottom bar)
3. **Day 3** — item 7 (favourites) — its own session because the
   storage + sort + visual indicator touch a few places
4. **Day 4** — items 8 (hide-already-applied) + 10 (search clear)
5. **Day 5** — item 33 (build script) so future releases stop being
   manual
6. **Day 6** — item 24 (minimap button)
7. **Day 7** — item 11 (right-click context menu)

After that the bigger items (compare mode, outfit sharing, settings
panel, localization) can be picked up individually.

---

## How to use this file

- Pick an item, open a GitHub Issue for it (so progress is visible),
  link the issue's number back into a checkbox here.
- When done, move the item to a "Done" section at the bottom rather
  than deleting it — that creates an audit trail for future sessions.
- Items can spawn sub-items. If favourites grows to need a UI overlay
  + sort changes + tooltip support, split it into 7a/7b/7c here.
