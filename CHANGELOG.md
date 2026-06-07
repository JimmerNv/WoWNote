# Changelog

## 1.14.13

- Changed Restock buying to purchase the exact missing amount expressed as merchant vendor units instead of one unit at a time.
- Set the pending state before calling `BuyMerchantItem` so a synchronous bag event cannot leave the restock UI stuck on Wait.
- Recount bags after purchase before making any further restock decision.
- Added a timeout fallback that clears stale pending state and rechecks merchant restock if no delayed bag update arrives.
- Added a per-merchant auto-buy guard so one item cannot be auto-bought repeatedly in the same vendor session.

## 1.14.12

- Changed tracker auto-restock to buy only one vendor unit per item before waiting for bag updates.
- Recounts bags after every purchase before deciding whether another restock purchase is needed.
- Prevents auto-restock loops from filling the full inventory when target counts are configured.
- Updated restock UI text to show missing item counts and vendor units instead of firing bulk buys.

## 1.14.11

- Fixed Item Tracker row controls being blocked by overlapping frame levels.
- Added an explicit clickable item area for item icon/name rows.
- Raised row controls above the scroll background to keep middle rows clickable.

## 1.14.6

## 1.14.8

- Added a Settings option to hide or show the WowNote minimap icon.
- The minimap visibility setting is stored account-wide in `WowNoteDB.minimap.hide`.


- Fixed PallyBuffs buff button taint by replacing TargetUnit-based casting with secure button attributes.
- Moved anchored side submenus further to the right and widened them slightly for cleaner layout.

## 1.14.5

- Add visible delete buttons to the Character Notes list.
- Add delete confirmation for character note removal.
- Keep Character Notes account-wide in `WowNoteDB.characterNotes`.

## 1.14.4

- Store character notes account-wide in `WowNoteDB.characterNotes`.
- Add defensive migration from legacy per-character character-note tables.
- Keep name-realm keys to avoid cross-realm player-name collisions.


## 1.14.1

- Embedded the Postal mail addon as `WowNotePostal` inside WoWNote.
- Added the Postal mailbox tools directly to the WoWNote package: Open All, selected-mail operations, express clicks, money subject helper, trade blocking, session money summary, contact/alt/recent recipient support, and delete/return helper icons.
- Renamed the embedded addon namespace, database, frames, dropdowns, and popup IDs to avoid clashing with a separately installed native Postal addon.
- Added `/wnpostal` to open the integrated Postal menu while the mailbox is open.

## 1.13.9

- Integrated the PallyPower compatibility layer more deeply into WoWNote instead of only announcing a minimal client presence.
- Mirrored native PallyPower tables (`AllPallys`, `PallyPower_Assignments`, `PallyPower_NormalAssignments`, `PallyPower_AuraAssignments`) when native PallyPower is not loaded.
- Added original PallyPower class icons under WoWNote so the assignment UI shows icons without requiring a separate PallyPower install.
- Added native protocol parsing for `NASSIGN` and stricter permission handling for incoming `ASSIGN`, `MASSIGN`, `AASSIGN`, and `CLEAR`.
- Kept the WoWNote `All` button: normal click fills empty slots, Shift-click overwrites all, right-click clears all.

# 1.13.8

- Replaced the separate Free On / Free Off controls with one stateful Free On / Free Off toggle.
- Defaulted PallyPower free assignment to enabled.
- Added an integrated WowNote PallyPower-style buff frame that can be shown or hidden.
- Added PallyPower-compatible SELF, ASELF, SYMCOUNT and FREEASSIGN announcements on the PLPWR addon channel so native PallyPower clients can discover WowNote paladins without waiting for manual sync.

# Changelog

## 1.14.9

- Added a central Data Transfer picker for Send and Export flows.
- Send/Export now lets users choose Notes, Character Notes, Tactics, Raid Planner presets, Talents, Raid IDs, Tracker/Restock data, Bank snapshots, or all supported data.
- Added generic WowNote data import/export format while keeping legacy note imports supported.
- Generic transfers now save incoming data into the matching WowNote account-wide data tables.

## 1.9.30-channel-safe-no-share-menu

- Removed the visible Share entry from the note context menu.
- Kept the existing note editor, item-link support, and talent planner.
- Kept internal communication/debug code in the source for future experiments.
- Updated addon metadata text to avoid advertising unsupported sharing on the tested server.

## Earlier development notes

This project went through several transport experiments:

- Addon whisper via `SendAddonMessage`
- Normal chat whisper fallback
- Carbonite-style shared channel transport
- Channel payload escaping for WoW chat safety

On the tested server, reliable user-facing share behavior could not be guaranteed because server-side chat throttling/muting interfered with larger transfers. The UI therefore no longer exposes the Share workflow.
