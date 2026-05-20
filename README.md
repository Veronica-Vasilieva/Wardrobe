# Wardrobe

Interactive transmog browser for the **Warpweaver** NPC on
Project Ebonhold / Valanior-WoW (a 3.3.5a private server running a
customised fork of Rochet2's transmog module).

The server's native UI is a paginated gossip menu — click a slot, scroll
ten pages of helms, remember a name, do it again for shoulders, repeat.
Wardrobe replaces it with a real interface: searchable per-slot lists, a
rotatable 3D paper-doll preview, outfit save/load, and direct integration
with the server's Manage Sets feature so you don't pay every time you
change your look.

![Wardrobe screenshot placeholder]

## Features

- **Per-slot searchable lists** of every appearance you've collected,
  populated by an async scan that walks the gossip menu in the
  background. Items are quality-coloured; tooltips show full item
  details. Name search + quality filter cycle through the list.
- **Interactive 3D paper doll** with the standard `DressUpModel`
  controls — left-drag rotates, right-drag pans vertically, mouse wheel
  zooms, and a **Reset View** button on the doll restores the default
  camera. Left-clicking any item stages a `TryOn` so you can build a
  full look across multiple slots before committing.
- **Outfit save / load / delete.** Per-character, stored in the addon's
  SavedVariables. Save the current preview under a name, restore it
  from the dropdown, and Apply Preview to commit. Outfit data round-
  trips with hide markers too.
- **Server Sets integration.** The addon scans your server-side Manage
  Sets at the end of every normal scan and lets you Use / Save / Delete
  them from the same panel — Use is **free** (the server only charges
  on Save), so once you've stored a few looks you can swap them without
  paying the per-transmog fee each time.
- **Enchant illusion slots** (Main hand enchant, Off hand enchant) are
  surfaced as additional pseudo-slots and follow the same flow.
- **Hide slot** stages a "Hide item" preview rather than firing
  immediately — committed by Apply Preview alongside any other staged
  changes, so a single Save Pending popup handles the whole batch.
- **Apply Preview** drains all staged changes through the gossip flow
  one at a time, then auto-clicks Save Pending so the whole batch
  commits in **one cost popup** instead of one per slot.
- **Live cache warming** for items the client has never seen. WoW
  3.3.5a's `GetItemInfo` doesn't auto-fetch from the server — Wardrobe
  works around it with a hidden `GameTooltip:SetHyperlink` scanner
  throttled to ~20 pings/sec. Progress is shown in the bottom-bar
  stamp ("Warming 47/256") so you can watch unfamiliar appearances
  populate live.
- **Custom background art** behind the wardrobe window (purple/gold
  transmog scene). Column backdrops are kept at moderate alpha so the
  art is visible without sacrificing foreground readability.
- **In-game help** — hover the **?** badge in the top-right of the
  wardrobe for the addon name + version, a one-paragraph About, the
  full slash command list, control reference, license summary, and
  GitHub URL.
- **Server Menu** button hands you back to the native Warpweaver gossip
  (without ending the session) if you ever need a feature the addon
  doesn't surface directly.

## Installation

1. Download the latest `Wardrobe-vX.Y.zip` from the
   [Releases](https://github.com/Veronica-Vasilieva/Wardrobe/releases)
   page.
2. Extract into your `Interface/AddOns/` folder.
3. **The folder must be named `Wardrobe` exactly** — rename if your zip
   tool used a different name.
4. `/reload` in-game.

## Usage

Talk to a **Warpweaver** NPC. The first interaction triggers a 1–3
second scan of your appearance collection plus a quick detour through
Manage Sets, then the Wardrobe window opens. After that, every visit
reuses the cache (rescan every 30 minutes automatically, or
`/wb rescan` on demand).

### Interactive controls

| Where | Action | What happens |
|---|---|---|
| Item row | Left-click | Stages on the doll (no server cost) |
| Item row | Right-click | Applies immediately |
| Paper doll | Left-drag | Rotate model |
| Paper doll | Right-drag | Pan camera vertically |
| Paper doll | Mouse wheel | Zoom in/out |
| Paper doll | **Reset** button | Restore default camera |

### Buttons

- **Apply Preview** — commits all staged changes in one batch with one
  cost popup
- **Reset Preview** — clears all staged changes and re-syncs the doll
- **Save as Outfit** — stores the current preview under a name (addon
  storage, free)
- **Save Server Set** — costs gold per the server's fee; lets you
  re-Use it for free later
- **Hide _Slot_** — stages a hide for the active slot (committed by
  Apply Preview)
- **Apply All (Save Pending)** — commits any server-side pending
  transmogs
- **Cancel Pending** / **Restore Original** — server-side
- **Server Menu** — hand off to the native gossip frame

### Slash commands

| Command | What it does |
|---|---|
| `/wb`, `/wardrobe` | Open / close the wardrobe |
| `/wb rescan` | Force a full rescan of your collection and server sets |
| `/wb reset` | Wipe all SavedVariables (requires `/reload`) |
| `/wb debug` | Toggle verbose chat logging (per-page gossip option dump during scans / apply flows) |
| `/wb npcname <Name>` | Register an alias if your server uses a different name than "Warpweaver" |

## Server requirements

Wardrobe is built for **Project Ebonhold / Valanior-WoW**'s customised
Rochet2 transmog module:

- Persistent appearance collection (clicking an item adds it, you don't
  need to keep it in your bag)
- Staged "pending transmogrifications" with a single Save Pending commit
- "Manage sets" gossip option in the main menu
- "Show main menu" option on page 1 of each slot submenu
- Per-slot "Hide item" option

If your server has a different gossip layout, scanning may misbehave —
turn on `/wb debug` and `/wb rescan` while at the NPC and the per-page
dump will show what's actually being emitted in chat. Paste the output
in a GitHub Issue and we can adapt.

## Contributors

- **Veronica-Vasilieva** — original author and current maintainer.

Bug reports and pull requests welcome via
[GitHub Issues](https://github.com/Veronica-Vasilieva/Wardrobe/issues).

## License

Source-available — see [LICENSE](LICENSE).

Short version: free to use, modify for personal use, and contribute back.
You may NOT rebrand, redistribute as your own work, repackage on addon
sites under a different author, or sell it. Forks are allowed with a
clearly different name, attribution to this project, and the same
license.
