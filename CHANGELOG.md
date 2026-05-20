# Wardrobe — changelog

## [1.10] - 2026-05-20

### Fixed
- **Corrected the "Server Sets are free to Use" misconception throughout
  the addon.** The Ebonhold/Valanior fork still charges the per-transmog
  fee every time a set is applied — only the paper-doll preview is
  truly free. Earlier docs/tooltips wrongly implied the Rochet2 vanilla
  model (paid at Save, free thereafter) was in effect. Updated:
  - README intro and Features list
  - "Save Server Set" tooltip
  - "Server Sets ▼" dropdown tooltip
  - SERVER SETS section code comments
- v0.11 and v1.0 CHANGELOG entries are left unchanged for historical
  accuracy (they reflect what was believed at the time).

## [1.9] - 2026-05-20

### Fixed
- **Enchant slots populate.** Cause confirmed by reading the
  Sunwell/Valanior server source
  ([Transmogifier.cpp line 247](https://github.com/coolzoom/sunwellcore-world2024/blob/main/src/server/game/Custom/Transmogification/Transmogifier.cpp)):
  enchant options are emitted as `"|Ticon|t<EnchantName>"` with no
  hyperlink — neither `|Hitem:` nor `|Henchant:`. The previous parser
  returned nil for every enchant row.
- `ParseItemOption` now takes an `isEnchant` flag. In enchant mode it
  treats any non-navigation plain-text option as an enchant, using the
  name itself as a synthetic string entry ID. The icon path is pulled
  from the `|T...|t` prefix so each row renders with the actual server
  icon (defaults to `INV_Enchant_FormulaGood_01` if missing).
- `CaptureSlotItems` detects enchant slots via `IsEnchantSlot(slotId)`
  and stores `resolved = true` so the cache-warming scanner and lazy
  GetItemInfo refresh skip them (neither would work for non-items
  anyway).
- `ApplyEntry` captures the enchant flag in its `findTarget` closure
  so the entry comparison stays consistent between scan-time and
  apply-time parses.

### Notes
- Apply by enchant works because we drive the gossip option by *index*
  — we never needed the server-side `enchantentry`. Name equality
  between scan and apply parses is enough.

## [1.8] - 2026-05-20

### Fixed
- **Search past 2 letters showed empty list — actual root cause this
  time.** 3.3.5a's `FauxScrollFrame_Update` contains this:

  ```lua
  if ( numItems > numToDisplay or alwaysShowScrollBar ) then
      frame:Show();
  else
      scrollBar:SetValue(0);
      frame:Hide();      -- hides the WHOLE scroll frame
  end
  ```

  When the filtered list (4 items for "arc") fit inside the row pool
  (22 rows), Update called `frame:Hide()` on the scroll frame, which
  hid all child rows. Symptom: stamp said "4 items" but the list
  area was empty. 2 chars usually still matched >22 items so the
  scroll frame stayed visible; 3+ chars dropped below the threshold.

  Fix: call `ui.listScroll:Show()` right after every Update to
  counteract the auto-hide.

### Notes
- The v1.7 re-entry guard and v1.2 offset clamp remain as defensive
  code; they handled real but different edge cases.

## [1.7] - 2026-05-20

### Fixed
- **Search past 2 letters showed no items.** The same scroll-offset
  drift bug v1.2 papered over had a deeper root cause: when
  `FauxScrollFrame_Update` resets the scrollbar via
  `SetMinMaxValues(0, 0)`, the auto-clamp fires `OnVerticalScroll`,
  which calls `ui.RefreshList` **recursively** (because that's set
  as the scroll's update function). The recursive call competed
  with the outer call's row rendering, and on narrowing searches
  the outer call would Hide every row after the recursive call had
  shown them — net result: empty list.
- Added a `ui._refreshing` re-entry guard so the recursive call
  no-ops cleanly. Outer call's row rendering is now the source of
  truth.

### Notes
- The v1.2 offset clamp is kept as belt-and-braces; it still helps
  if anything else ever ends up out of sync.

## [1.6] - 2026-05-20

### Added
- **Background-art toggle.** Labeled "Background art" checkbox at
  the bottom of the doll column lets you switch between the
  custom wallpaper (translucent columns) and the original opaque
  dark backdrop. Saved per-character in
  `WardrobeDB.ui.showBackground` (default on).
- `ui.ApplyBackgroundPref()` centralises the visual swap —
  shows/hides the texture and flips the three column backdrop
  alphas between 0.55 (wallpaper visible through columns) and
  0.85 (opaque, no-wallpaper look).

### Changed
- Doll model height trimmed from 380px to 348px to make room for
  the toggle. Doll is still large enough for clear preview and
  full rotation/zoom interaction.
- `GetDB` now backfills nested `ui.*` defaults so the new
  `showBackground` flag is added to older saves without a wipe.

## [1.5] - 2026-05-20

### Fixed
- **Background image didn't show up.** Two combined issues:
  - WoW 3.3.5a's texture loader rejected the v1.4 1024×680 TGA
    because the height wasn't a power of two. Regenerated at
    **1024×512** PoT with scale-to-cover (matches the frame's
    ~1.47:1 aspect closely with only a modest top/bottom crop).
  - Even if the texture had loaded, the column backdrops
    (`listBg`, `dollBg`, bottom bar) had alpha 0.85, blocking
    the art behind them. Dropped those alphas to 0.55 so the
    image shows through while the foreground content stays
    readable.
- Background texture now also uses the explicit `.tga` extension
  in `SetTexture` (some 3.3.5a clients are picky about
  extension-less paths for addon-installed files) and renders at
  BACKGROUND sublevel 7 to guarantee it sits above the frame's
  bgFile fill.
- Vertex colour set to `(1,1,1,1)` (was `0.65`-dimmed) since the
  child backdrops now do the dimming work instead.

## [1.4] - 2026-05-20

### Added
- **Custom background art.** Purple/gold transmog scene
  (`Media/Background.tga`, 1024×680) rendered on the wardrobe
  frame's BACKGROUND layer, anchored 5px inside the border so
  the dark backdrop forms an edge frame. Vertex colour dimmed
  to ~65% so foreground text/buttons stay readable. The
  original dark `UI-DialogBox-Background-Dark` backdrop remains
  underneath as a fallback in case the texture file is missing.

## [1.3] - 2026-05-20

### Fixed
- **Question marks on the Outfits / Server Sets buttons.** The
  `▼` glyph isn't in WoW 3.3.5a's default font and renders as
  `?`. Replaced all six occurrences with the ASCII `(v)` so the
  dropdown indicator shows correctly. Per the project's known
  unicode-restriction list.

## [1.2] - 2026-05-20

### Fixed
- **Tabard tab (and any other small-collection slot) appeared empty
  even though items were cached.** Same root cause as the search
  bug below: `FauxScrollFrame` keeps its scroll offset across slot
  switches and search refilters, so going from a 256-item slot
  scrolled to row 100 → a 9-item slot left every row reading past
  the end of `filtered`. `RefreshList` now clamps the offset to
  `max(0, #filtered - #ui.rows)` and re-syncs `SetVerticalScroll`.
- **Search stopped returning matches after a few letters.** Same
  scroll-offset-stale issue — narrowing the search shrank
  `#filtered` below the parked offset. The same clamp fixes it.
- **Preview label overflowed the doll column** and clipped behind
  the right pane. The label now has `SetWidth(DOLL_WIDTH)` +
  `SetJustifyH("CENTER")` and its messages were split into two
  shorter lines so everything fits cleanly under the doll.

## [1.1] - 2026-05-20

### Added
- **"?" info badge** in the top-right corner of the wardrobe window
  (just left of the close button). Hovering it shows the addon name,
  version, author, a one-paragraph About summary, the full slash
  command list, in-window control reference (left-click stages,
  right-click applies, doll rotation/pan/zoom), license summary,
  and the project GitHub URL. Mirrors AutoLoot's info badge.

## [1.0] - 2026-05-20

First public release. Cumulative feature set:

### Core
- Interactive transmog browser for Project Ebonhold's Warpweaver NPC,
  replacing the paginated gossip menu with a real interface.
- Async scan walks the gossip menu in the background — slots forward via
  Next page, back via Previous, then click "Show main menu" on page 1.
- Server-side Manage Sets detour at the end of every scan caches set
  names for in-addon Use / Save / Delete.
- Account-wide `WardrobeDB` SavedVariables, keyed per-character inside
  (`chars[Name-Realm]`) so each alt has its own collection, outfits,
  and server-set cache.

### UI
- 1000×680 main frame with three columns: slot tabs, 3D paper-doll
  preview, item list. Bottom action bar for batch operations.
- Slot tabs include every equipment slot plus the customised server's
  enchant illusion pseudo-slots (Main hand enchant, Off hand enchant).
- Per-row item list with quality-coloured names, tooltips, name search,
  and a cycling quality filter.
- Paper-doll preview is fully interactive: left-drag rotates,
  right-drag pans, mouse wheel zooms, Reset View button restores
  default camera.

### Apply / Preview / Outfits
- Left-click an item → previews on the doll; right-click → applies
  immediately.
- Apply Preview drains all staged transmogs through the gossip flow
  one at a time and auto-clicks Save Pending so the whole batch commits
  in a single cost popup.
- Outfits (addon-side) save the current preview under a name, restore
  it from a dropdown, delete with confirmation. Stored per-character.
- Hide slot stages a HIDE sentinel that commits via gossip when Apply
  Preview runs.

### Server Sets
- Use / Save / Delete server-side sets without leaving the addon.
- Use is free; Save uses the server's per-transmog fee.

### Robustness fixes (for 3.3.5a quirks)
- Gossip frame suppression uses `SetAlpha(0)` + off-screen positioning
  rather than `Hide()` — calling `Hide()` would trigger
  `GossipFrame_OnHide → CloseGossip` and end the session server-side.
- Hidden `GameTooltip:SetHyperlink` scanner warms the item cache for
  appearances the player has never owned (3.3.5a's `GetItemInfo` does
  not auto-fetch). Throttled to ~20/sec.
- `StaticPopup` text-input uses `_G[dialog:GetName() .. "EditBox"]`
  rather than the `dialog.editBox` field that doesn't exist in 3.3.5a.
- `ParseItemOption` recognises both `|Hitem:` and `|Henchant:` links so
  enchant illusion submenus parse correctly.
- Graceful partial-scan recovery if Previous-page closes gossip
  prematurely or the user closes the wardrobe mid-apply.

### Provenance
- Author: Veronica-Vasilieva.
- Source-available license — see LICENSE.
- Provenance globals (`WARDROBE_IDENT`, `WARDROBE_ORIGIN`, etc.) and
  SavedVariables stamps make attribution removal annoying without a
  deep refactor.

## [0.14] - 2026-05-20

### Added
- **Interactive 3D paper-doll preview.** Mirrors the standard
  `CharacterModelFrame` / `DressUpFrame` controls in WoW 3.3.5a:
  - **Left-drag** rotates the model around its vertical axis
  - **Right-drag** pans the camera vertically (useful for looking at
    boots / helms close-up)
  - **Mouse wheel** zooms in/out
- **Reset View button** overlaid in the doll's bottom-right corner —
  restores the default camera if the model gets dragged off-screen.
  Tooltip explains the drag/zoom controls.

### Changed
- `RefreshDoll` now preserves the user-adjusted facing and position
  across the `SetUnit("player")` reset. Without this, each preview
  click would snap the model back to its default angle, making the
  rotation feature unusable while staging a multi-slot preview.

### Internal
- `doll.resetView()` captures the initial facing + position once at
  frame creation so the Reset button has a stable target to restore to.

## [0.13] - 2026-05-19

### Fixed
- **`attempt to call global 'BuildWarmQueue' (a nil value)` after scan.**
  `BuildWarmQueue` is defined in the UI section (further down in the
  file), but `FinishScan` (defined earlier) was trying to call it.
  Lua's closure-by-scope rules meant the reference fell through to a
  nil global. Added forward declarations near the top of the file
  for `BuildWarmQueue`, `WarmingActive`, and `WarmTick`, and switched
  their later definitions from `local function` to `function` so they
  assign to the forward-declared locals. Also dropped FinishScan's
  redundant `BuildWarmQueue()` call since `ShowWardrobeUI` already
  invokes it on every show.
- **Enchant slots showing 0 items.** Likely cause: the customized
  Warpweaver emits `|Henchant:N|h..|h` hyperlinks for illusion
  options rather than `|Hitem:N:|h..|h`. `ParseItemOption` now tries
  both formats — items still take priority, but enchant links are
  recognised as a fallback.

### Notes
- If enchant slots are still empty after `/wb reset` + `/reload` +
  fresh scan, the server is emitting something else entirely (e.g.
  `|Hspell:`, plain text, custom hyperlink namespace). Enable
  `/wb debug` and `/wb rescan` while looking at the Warpweaver — the
  per-page dump will show the actual option text and we can adapt
  the parser.

## [0.12] - 2026-05-19

### Added
- **Enchant illusion slots are now first-class.** New synthetic SLOTS
  entries (IDs 96 and 97) for Main hand enchant and Off hand enchant,
  ordered before their non-enchant counterparts in iteration so the more
  specific label wins on a first-match-and-break scan. They appear as
  additional slot tabs, get scanned/paged like regular slots, and apply
  through the existing `StartSlotAction` flow.
- New `IsEnchantSlot(slotId)` helper.

### Changed
- `MatchesSlotLabel` no longer excludes options containing "enchant" —
  the strict `" ["` suffix requirement was already enough to prevent
  "Main hand enchant [enchant]" from matching the "Main hand" label, and
  removing the blanket exclusion is what lets the new enchant entries
  match cleanly.
- **Paper-doll preview** skips `TryOn` for enchant pseudo-slots —
  `DressUpModel` can't render illusions, but the preview label still
  tracks them so the user sees what's queued before Apply Preview.
- **Hide button** disables itself when an enchant slot is selected
  (their submenu has no "Hide item" option, so the button would just
  surface an error).

### Notes
- Best-effort implementation: the enchant submenu structure (pagination,
  item links, "Show main menu" option) is assumed to mirror regular
  slots. If your server's enchant menu differs, `/wb debug` plus a
  `/wb rescan` will dump every option so we can adapt.

## [0.11] - 2026-05-19

### Fixed
- **Server Menu regression.** v0.10's Server Menu button revealed the
  native gossip frame, but `OnGossipShow` then re-suppressed it on every
  option click, making the gossip vanish as soon as the user tried to use
  it. New `ui.userInServerMenu` flag is set when the button fires and
  cleared on `GOSSIP_CLOSED`; while set, `OnGossipShow` skips the
  suppression branch entirely so the native menu renders normally.

### Added
- **Manage Sets is now in the addon.** Server-side sets are scanned at
  the end of every normal scan (a new `scanning_sets_entering` phase
  detours into "Manage sets" and parses the set names before returning
  to main) and surfaced in a new **Server Sets** section in the doll
  column below the addon's outfit controls.
- **Use Server Set** — click a set name from the Server Sets dropdown to
  re-apply it for free. Drives the gossip flow: Manage sets → set name →
  Use set → walk back to main.
- **Save Server Set** — new popup asks for a name, then drives the
  gossip flow: Manage sets → Save set (with the name passed as the
  code parameter to `SelectGossipOption`) → walk back. Server takes
  the per-transmog fee server-side; the addon bypasses the native cost
  popup because we surface our own confirmation.
- **Delete Server Set** — confirms then drives Manage sets → set name →
  Delete set → walk back. Local cache is updated immediately so the
  dropdown reflects the change without a rescan.
- Tooltips on Server Sets controls explain that Use is free, Save costs
  gold, and addon outfits remain separate from server sets.

### Internal
- New `setActionState` state machine drives Use/Save/Delete sequences,
  hooked into the GOSSIP_SHOW dispatcher alongside `scanState` and
  `applyState`. Closed gossip mid-action calls `ResetSetAction` so the
  machine doesn't dangle.
- `ClickMatchAndAdvance(opts, predicate, nextPhase, code)` helper finds
  an option by predicate, transitions phase, and schedules the click —
  optionally passing a code for gossip text input.

## [0.10] - 2026-05-19

### Fixed
- **Save as Outfit silently did nothing.** WoW 3.3.5a's `StaticPopup_Show`
  does NOT set `dialog.editBox` as a field on the dialog frame — that
  assignment was added in a later client version. So my `self.editBox:GetText()`
  in `OnAccept` was indexing nil, erroring silently, and never reaching
  `SaveCurrentPreviewAsOutfit`. The popup looked correct visually but
  nothing persisted. Fixed by routing edit-box access through a
  `PopupEditBox()` helper that uses `_G[dialog:GetName() .. "EditBox"]`
  (with the field as a forward-compat fallback). Also added
  `EditBoxOnEscapePressed` to dismiss the popup on Esc.

### Added
- **Server Menu button** in the bottom action bar. Hides Wardrobe and
  reveals the underlying Warpweaver gossip frame *without* closing the
  session, so you can reach server-side features Wardrobe doesn't surface
  directly (notably "Manage sets", but also "How transmogrification works"
  and similar info options). New `ui.skipCloseGossip` flag makes the
  wardrobe's `OnHide` handler skip the CloseGossip call when this is the
  reason the frame is hiding.
- **Tooltip on Save as Outfit** spells out that addon outfits live in
  local SavedVariables and are separate from the server's Manage sets —
  the two systems don't share data and won't overwrite each other.

### Internal
- `PopupEditBox(dialog)` helper centralises the cross-version edit-box
  lookup so any future StaticPopups stay correct.

## [0.9] - 2026-05-19

### Fixed
- **Item qualities and icons now populate automatically** for appearances
  the player has never owned. In WoW 3.3.5a, `GetItemInfo()` does NOT
  trigger a server fetch when the entry isn't cached — it just returns
  nil — so previously the user had to manually hover/click each row to
  warm the cache. v0.9 adds a hidden `GameTooltip:SetHyperlink()` scanner
  that pings every unresolved item at ~20 pings/second after a scan or
  on wardrobe open. Progress is shown in the bottom-bar stamp as
  "Warming N/M" while the queue drains.

### Internal
- Dual ticker in the main frame's OnUpdate: cache-warming pass every
  0.05s when items are pending, display refresh pass every 0.4s to pick
  up newly-resolved entries and re-render the list.
- BuildWarmQueue runs on `ShowWardrobeUI` and `FinishScan` — deduped by
  entry ID so popular items aren't pinged twice.

## [0.8] - 2026-05-19

### Fixed
- **Hide button no longer overflows past the frame edge.** Search box
  shrunk 380→240, quality button 130→120; the top-right cluster now
  totals 510px and fits comfortably inside the ~534px right pane.

### Changed
- **Hide is now a preview action, not an immediate gossip click.**
  Clicking Hide stages a `"HIDE"` sentinel into `previewSlots[slotId]`;
  nothing is sent to the server until Apply Preview runs, at which point
  the queue dispatches the existing `HideSlot` gossip flow for each
  staged hide alongside any normal transmog applies. Single Save Pending
  popup commits the lot.
- Preview-doll best-effort undress: calls `:UndressSlot(slotId)` inside
  `pcall` so it works if a later WoW version (or DressUpModel extension)
  exposes it, and silently no-ops on stock 3.3.5a. The preview label
  still tracks the pending hide so the user knows what's queued.
- Hide button tooltip now spells out the staged-vs-committed semantics
  and warns that once committed, the slot stays hidden until the user
  transmogs something else onto it or runs Cancel Pending.
- Preview status label below the doll now splits transmog vs hide counts
  ("3 transmogs + 1 hide staged | Apply Preview to commit") and shows a
  hint line when the preview is empty.

### Internal
- Outfit save/load naturally supports HIDE entries — they're just another
  value in the per-slot preview map, so existing outfits round-trip with
  hides included.

## [0.7] - 2026-05-19

### Added
- **Paper-doll preview using `DressUpModel`.** New centre column shows
  your character with currently equipped (and transmogged) gear. Clicking
  an item in the list now stages a `TryOn` on the doll instead of applying
  immediately. Build a complete look across multiple slots before
  committing.
- **Apply Preview button.** Drains all previewed slots through the gossip
  apply flow one at a time (chained via `applyState.onComplete`), then
  auto-clicks Save Pending to commit the whole batch in one cost popup.
- **Outfit save / load / delete.** Per-character outfits stored in
  SavedVariables. Save current preview under a name via a `StaticPopup`
  text input; load any saved outfit from the Outfits dropdown to restore
  it as the active preview; delete with confirmation. Loading + Apply
  Preview = one-click full-outfit switch.
- **Right-click row = apply immediately.** Bypasses the preview flow for
  quick single-item changes.
- Reset Preview button clears all staged previews and re-syncs the doll
  to your current look.

### Changed
- Main frame widened to 1000×680 to make room for the doll column. Row
  count restored to 22 (more vertical real estate now available).
- Backwards-compatible: characters without `outfits` in their saved data
  get backfilled with an empty array on next login.

## [0.6] - 2026-05-19

### Added
- **Hide Slot button.** New button to the right of the Quality filter
  drives the Warpweaver's per-slot "Hide item" gossip action. Label updates
  with the active slot ("Hide Head", "Hide Shoulders", …). Tooltip
  clarifies that being at the Warpweaver is required.
- Unified per-slot action driver: ApplyEntry and HideSlot now share the
  same state machine, parameterised by a `findTarget(opts) -> optIdx`
  callback. Same pagination, same return-to-main walk-back.

### Changed
- **Gossip frame is now both alpha-zeroed AND parked off-screen** while
  the addon is driving it, so no brief flash even if the OnShow hook fires
  late or another addon clobbers alpha. Original anchors are snapshotted
  on first interception and restored when suppression ends.

## [0.5] - 2026-05-19

### Fixed
- **Return-to-main flow now matches the Ebonhold Warpweaver menu structure.**
  Each submenu's page 1 has a "Show main menu" option (and per-slot actions
  like "Hide item", "Remove pending transmogrification", "Restore original
  look"); pages 2+ have only Previous/Next nav. v0.4 walked Previous and
  expected page 1 to have a Previous-to-main, which doesn't exist. v0.5
  walks Previous until "Show main menu" appears, then clicks it.
- **Item rows no longer overflow under the bottom action bar.** Row pool
  reduced from 22 to 18 (18 × 22px = 396px fits inside the ~432px scroll
  area cleanly).

### Changed
- `FindNavOptions` now returns `(next, prev, showMain)` instead of
  `(next, back, prev)` — reflecting the actual server protocol.
- Debug per-page log now shows `[next]`, `[prev]`, `[main]` indicators so
  you can see at a glance which nav options each page exposes.

## [0.4] - 2026-05-19

### Fixed
- **Scan aborted after the first slot.** The Ebonhold Warpweaver has no
  explicit "Back" option in slot submenus — only Previous and Next page
  navigation. v0.3's `ReturnToMain` looked for a "back" string, failed, and
  aborted the scan after Head completed. Now after forward-paging to the
  last page, the scanner walks Previous-page clicks one at a time until the
  main menu is detected (via an "at least 3 slot rows visible" heuristic),
  then moves to the next slot.
- Apply flow uses the same Previous-walk strategy to return to main after a
  transmog is confirmed, so a successful apply now leaves you ready to pick
  another item without re-opening the NPC.
- Default `GossipFrame` no longer ends up in a stuck/empty state after a
  partial scan — closing the wardrobe always calls `CloseGossip()`, and the
  `suppressing` flag is now always cleared via `GOSSIP_CLOSED`.

### Added
- **Graceful partial-scan recovery.** If gossip closes mid-scan (e.g. the
  Previous button "breaks" and exits gossip prematurely), the addon saves
  whatever it captured, updates `lastScan`, and prints a clear notice. The
  wardrobe opens with partial data instead of losing everything.
- **Verbose debug dump.** `/wb debug` now prints every gossip option's
  index and plain text on every GOSSIP_SHOW during a scan or apply. Use this
  to diagnose unexpected menu structures on the server side.
- Scan completion message now reports total appearances cached across all
  slots.

## [0.3] - 2026-05-18

### Added
- **Pagination support.** The Ebonhold Warpweaver submenu uses Next-page
  buttons rather than showing all items at once. Scan now follows
  Next-page links until exhausted (with a 200-page safety cap and a
  "page contributed zero new items → stop" guard).
- Lazy GetItemInfo refresh now runs on a 1-second OnUpdate tick while the
  wardrobe is open, so item names/qualities/icons populate live as the
  client cache warms.

### Fixed
- Item rows now anchor `TOPLEFT`/`TOPRIGHT` to the scroll frame and let the
  name field flex between the icon and the right-aligned quality label, so
  text no longer overflows under the scrollbar.
- Slot detection on the customised main menu no longer matches
  "Main hand enchant" against the "Main hand" slot (excluded any option
  whose plain text contains "enchant"; required the `" ["` tag suffix for
  prefix matches).
- Apply flow now pages through the slot submenu to find the requested
  entry if it's not on page 1.

## [0.2] - 2026-05-18

### Fixed
- **Scan captured zero items in every slot.** `SuppressGossipFrame()` was
  calling `GossipFrame:Hide()`, and `GossipFrame_OnHide` in WoW 3.3.5a's
  default UI calls `CloseGossip()` — which ended the gossip session
  server-side. Subsequent `SelectGossipOption` calls were silently ignored
  by the server, so the scan loop spun through the queue without ever
  receiving real submenus. Fix: suppress via `SetAlpha(0)` + `EnableMouse(false)`
  rather than `Hide()`, which keeps the session alive.
- Apply flow no longer briefly re-shows the default `GossipFrame` after a
  successful transmog. Gossip stays suppressed for the lifetime of the
  wardrobe window; closing the window calls `CloseGossip()` to end the
  session cleanly, which restores `GossipFrame` visibility for next time.
- Apply flow now re-reads the submenu for the Back option after a transmog
  applies, rather than relying on the (possibly stale) main-menu mapping.

## [0.1] - 2026-05-18

### Added
- First playable skeleton: interactive transmog browser for Project Ebonhold's
  Warpweaver NPC.
- Auto-detects Warpweaver gossip and replaces the default paged menu with a
  searchable per-slot wardrobe window (880×600).
- Async scan engine walks each equipment slot submenu via the gossip protocol
  and caches the appearance collection per character (name-realm keyed),
  account-wide SavedVariables. Re-scans after 30 minutes or on demand.
- Per-slot list with name search, quality filter (cycles All → Common+ →
  Uncommon+ → … → Legendary+), and quality-coloured item rows.
- Item tooltip on hover via `GameTooltip:SetHyperlink`.
- Single-click apply: drives the gossip flow behind the scenes to transmog the
  selected slot. Server-side cost popup is passed through to the user — the
  addon never auto-accepts a money confirmation.
- Bottom action bar with Apply All (Save pending transmogrifications), Cancel
  Pending, Restore Original, Rescan.
- Lazy `GetItemInfo` refresh in the list: items the client hadn't cached at
  scan time populate on subsequent opens.
- Slash commands: `/wardrobe`, `/wb` (toggle), `/wb rescan`, `/wb reset`,
  `/wb debug`, `/wb npcname <Name>` (add aliases for NPCs named other than
  Warpweaver).
- Enchant slots and the "Manage sets" presets submenu are intentionally not
  surfaced in v0.1 (enchants are server-managed without user input; sets are
  deferred to v0.3).
