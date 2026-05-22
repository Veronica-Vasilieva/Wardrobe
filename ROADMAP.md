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

1. ~~**Verify HIDE + enchant slot interaction.**~~ ✅ Done in v1.11.
   `HideSlot`'s `^hide ` regex already caught both "Hide item" and
   "Hide enchant"; only needed to re-enable the button for enchant
   slots and propagate `isEnchant` into `ParseItemOption`.
2. ~~**Surface action errors more visibly.**~~ ✅ Done in v1.11.
   New `ErrorMsg` helper routes precondition messages to
   `UIErrorsFrame:AddMessage` (red banner) plus chat fallback.
3. ~~**Debounce search-box typing.**~~ ✅ Done in v1.12. New 100 ms
   debounce frame between `OnTextChanged` and `RefreshList` — each
   keystroke resets the timer; refresh fires once typing pauses.
4. ~~**Tab badges for staged slots.**~~ ✅ Done in v1.11. Slot tabs
   now show a gold `* N` when a preview is staged for that slot;
   `UpdatePreviewLabel` also calls `RefreshTabs` so badges sync
   instantly.
5. ~~**Persistent search across slot switches.**~~ ✅ Verified in
   v1.11. Already worked — `EditBox` retains its text across tab
   clicks and `RefreshList` reads `GetText()` on every run.
6. **Throttle apply chain to slow servers.** [M]
   *Why:* `SCAN_STEP_DELAY = 0.10` works on local servers but high-
   latency servers may drop clicks. Detect timeout patterns and back
   off automatically.

## Tier 2 — Quality-of-life features

Visible improvements players will notice. Each is contained.

7. ~~**Favourites system.**~~ ✅ Done in v1.13. Per-character
   `WardrobeDB.chars[key].favourites = {[entry]=true}`, gold `*`
   widget on the leftmost edge of each row, sort comparator bubbles
   favourites to the top above quality and name sorts.
8. ~~**Hide-already-applied toggle.**~~ ✅ Done in v1.14. Checkbox
   below the Background-art toggle. Tracks via
   `char.applied[slotId] = entry` updated during the apply state
   machine. Tracking is forward-looking: pre-existing transmogs
   and Server-Menu applies aren't known until re-applied through
   Wardrobe.
9. **Sort dropdown.** [M]
   *Why:* Currently fixed sort (quality desc, then name asc). Add Name
   asc, Name desc, Quality, "Recently scanned" — saved in
   `db.ui.sortOrder`.
10. ~~**Quick clear button on search box.**~~ ✅ Done in v1.14. Small
    "X" inside the search box's right edge, visible only when the
    box has text. Click empties the search and unfocuses.
11. ~~**Right-click context menu on rows.**~~ ✅ Done in v1.17. Five
    entries (Apply / Try On / Favourite-toggle / Hide-from-List /
    Cancel), purple-gold themed, anchored to the cursor, closes on
    outside click via OnUpdate polling. Replaces the old "right-click
    applies immediately" shortcut with a discoverable menu. Includes a
    new per-character `hiddenEntries` set and `db.ui.showHidden`
    toggle (third doll-column checkbox) so Hide-from-List has a
    visible un-hide path.
12. **Keyboard navigation.** [M]
    *Why:* Tab to cycle slot tabs, Up/Down to move within the list,
    Enter to preview. Useful for power users.
13. ~~**Bottom-bar Apply Preview shortcut.**~~ ✅ Done in v1.12. New
    Apply Preview button at the far left of the bottom bar, mirroring
    the doll-column one. Renamed "Apply All (Save Pending)" to just
    "Save Pending" to free up the room.
14. ~~**Confirmation popup before "Restore Original".**~~ ✅ Done in
    v1.12. New `WARDROBE_CONFIRM_RESTORE_ORIGINAL` StaticPopup with a
    Yes/No prompt and an orange-tinted warning about per-slot gold to
    re-apply.

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
19. ~~**Better enchant row display.**~~ ✅ Done in v1.11. Quality
    column shows "Enchant" in a gold tint instead of "Common", and
    the row name also adopts the gold tint for visual consistency.
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

24. ~~**Minimap button.**~~ ✅ Done in v1.16. Self-contained (no
    LibDBIcon dependency), draggable around the minimap rim, left-click
    toggles the wardrobe, right-click hides the button. Position saved
    as `db.ui.minimap.angle` (degrees). Hidden state restored via
    `/wb minimap`; `/wb minimap reset` re-centres.
25. **Random outfit generator.** [M]
    *Why:* Fun + helps players discover items they've forgotten about.
    Button: "Surprise me" rolls a random appearance per slot, stages
    the preview.
26. ~~**Outfit sharing via chat.**~~ ✅ Done in v1.18. Right-click an
    outfit in the dropdown for a Load / Share / Delete context menu;
    Share opens a popup with the code (Ctrl+C to copy) plus Say /
    Party / Guild post buttons. `/wb share <Name>` and `/wb import
    <code>` slash variants. ChatFrame hook rewrites any `WBS1:...`
    string into a clickable purple/gold hyperlink that opens the
    import popup pre-filled. Format: `WBS1:<urlenc-name>~<sid>:<entry>
    ~...` with strict validation on decode.
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

1. ~~**Day 1** — items 1, 2, 4, 5, 19~~ ✅ shipped as v1.11.
2. ~~**Day 2** — item 3 (debounce) + item 14 (confirmation popup) +
   item 13 (Apply Preview in bottom bar)~~ ✅ shipped as v1.12.
3. ~~**Day 3** — item 7 (favourites)~~ ✅ shipped as v1.13.
4. ~~**Day 4** — items 8 (hide-already-applied) + 10 (search clear)~~
   ✅ shipped as v1.14.
5. ~~**Day 5** — item 33 (build script) so future releases stop being
   manual~~ ✅ shipped (build_release.py at repo root).
6. ~~**Day 6** — item 24 (minimap button)~~ ✅ shipped as v1.16.
7. ~~**Day 7** — item 11 (right-click context menu) + Hide-from-List
   filter + Show-hidden toggle~~ ✅ shipped as v1.17.
8. ~~**Day 8** — item 26 (outfit sharing via chat)~~ ✅ shipped as
   v1.18.

After that the remaining bigger items (compare mode, settings panel,
sort dropdown, keyboard nav, localization) can be picked up
individually.

## Status

**Shipped so far (15 items + 1 extra), across v1.11 → v1.18:**
- Tier 1 — Hardening (5/6): #1, #2, #3, #4, #5
- Tier 2 — Quality-of-life (6/8): #7, #8, #10, #11, #13, #14
- Tier 3 — UI polish (1/9): #19
- Tier 4 — New features (2/8): #24, #26
- Tier 5 — Architecture (1/5): #33
- **Extras** (not originally listed): right-click slot tab to clear
  that slot's preview (v1.15)

**Release-by-release:**
- **v1.11** — Day 1: HIDE on enchant slots (#1), `UIErrorsFrame`
  routing (#2), staged-slot tab badges (#4), search persistence
  verified (#5), gold-tint enchant rows (#19).
- **v1.12** — Day 2: search debounce (#3), Restore-Original confirm
  popup (#14), bottom-bar Apply Preview shortcut (#13).
- **v1.13** — Day 3: favourites system with star widget + sort-to-top
  (#7).
- **v1.14** — Day 4: hide-already-applied toggle (#8), search clear
  X button (#10).
- **v1.15** — Extras: right-click slot tab clears that slot's preview
  only; slot-tab tooltips.
- **v1.16** — Day 6: self-contained minimap button — drag-around-rim,
  left-click toggle, right-click hide, `/wb minimap [reset]` (#24).
- **v1.17** — Day 7: right-click row context menu (#11) plus the
  Hide-from-List filter and Show-hidden toggle.
- **v1.18** — Day 8: outfit sharing via chat (#26) — right-click
  outfit context menu (Load/Share/Delete), `/wb share` + `/wb import`
  slash subcommands, ChatFrame hook turning `WBS1:` codes into
  clickable hyperlinks.

---

## How to use this file

- Pick an item, open a GitHub Issue for it (so progress is visible),
  link the issue's number back into a checkbox here.
- When done, move the item to a "Done" section at the bottom rather
  than deleting it — that creates an audit trail for future sessions.
- Items can spawn sub-items. If favourites grows to need a UI overlay
  + sort changes + tooltip support, split it into 7a/7b/7c here.
