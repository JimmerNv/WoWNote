## 1.14.59

- Restored the original `_Cursor` 3.3.0.2 fullscreen model viewport semantics instead of parenting cursor models to the WowNote/UIParent frame.
- Cursor controller is parentless again and each model uses `SetAllPoints(nil)`, matching the known-working standalone addon.
- Removed the v1.14.58 custom projection/reset layer that did not change the in-game displacement and could alter model rendering on ultrawide layouts.
- Restored the original cursor positioning and trail animation lifecycle while retaining WowNote settings, menu integration, and duplicate-addon suppression.
- Re-ran all 17 module-flow tests plus fresh, existing, and malformed SavedVariables initialization scenarios.

## 1.14.58

- Fixed Cursor Effects rendering against an unanchored parent frame, which could stretch or offset effects on ultrawide resolutions.
- Anchored the integrated cursor viewport explicitly to `UIParent` and anchored every model layer to that viewport.
- Positions cursor models before showing them to prevent trails from drawing a long line from the screen origin.
- Recalculates cursor projection metrics when resolution or UI scale changes.
- Resets trail animations after activation, display changes, alt-tab-sized cursor jumps, cinematics, and mouselook transitions.
- Re-ran the complete WowNote release-gate suite across initialization, SavedVariables, menus, windows, slash commands, and all modules.

## 1.14.57

- Added a full release-gate run across all WowNote modules using a Lua 5.1 / WoW 3.3.5a API mock environment.
- Tested fresh, existing, and malformed SavedVariables initialization scenarios.
- Tested all public window openers, main-menu and submenu routing, slash commands, and frame stacking/clickability constraints.
- Exercised Notes and Character Notes CRUD, Bank Viewer selection/search/tooltips, Item Snapshots, Item Tracker/Restock, Loot Tools, Auto Sell/Repair/Roll, Mail Open All, Manabonk cleanup, Raid Planner, Raid IDs, PallyBuffs, Port Helper, Cursor Effects, Tactical UI, Talent Planner, Minimap, Social protections, and data-transfer round trips.
- Fixed the main-menu `Send / Receive` action by exporting `WowNote_OpenShare` from its module-local implementation.
- Removed a stray undeclared `statusText` global reference from the Raid Planner status updater.
- Re-ran syntax, TOC, initialization, targeted module-flow, and final package verification after the fixes.

## 1.14.56

- Integrated Cursor Effects into WowNote as a native Quality of Life tool.
- Added a dedicated `Cursor Effects` entry to the Quality of Life submenu.
- Added a standalone WowNote-styled cursor configuration window with presets, layers, preview, offsets, scale, facing, custom model paths, saved sets, apply, and reset controls.
- Stores saved sets account-wide and active cursor layers per character inside the existing WowNote SavedVariables.
- Added `/wn cursor` and `/wncursor` shortcuts.
- Added a module toggle for Cursor Effects and preserved automatic hiding during screenshots, cinematics, camera movement, and mouselook.
- Namespaced all frames, globals, popups, and slash commands to avoid collisions with a separately installed `_Cursor` addon.
- Migrates existing `_Cursor` saved sets and character layers when available, and suppresses duplicate standalone cursor effects while the integrated module is enabled.
- Based on `_Cursor` 3.3.0.2 by Saiket.

## 1.14.55

- Hardened account-wide and per-character SavedVariables initialization across all modules.
- Added type validation for module settings, minimap data, character notes, tactical maps, PallyBuffs assignments, Raid ID data, Port Helper state, snapshots, and HUD settings.
- Prevents startup failures when older, incomplete, or malformed nested SavedVariables values are present.
- Verified fresh-install startup, existing-data preservation, malformed-data recovery, TOC load order, all public UI openers, core events, slash commands, and Lua syntax with a WoW 3.3.5a API mock harness.

## 1.14.54

- Standardized WowNote dialog stacking to avoid windows blocking unrelated UI elements.
- Replaced the Bank Viewer `TOOLTIP`/level 1000 setup with a normal top-level dialog configuration.
- Removed unbounded frame-level escalation and use bounded dialog levels plus `Raise()` instead.
- Reduced excessive child-frame offsets in Loot Tools, menus, Raid ID editing, Screen Draw, Tactical Board, and Tactical HUD controls.
- Kept full-screen drawing overlays mouse-transparent outside explicit draw mode.
- Added consistent base levels to the main editor, transfer dialogs, Character Notes, Item Tracker, Restock, Raid Planner, Port Helper, PallyBuffs, and other standalone windows.
- Corrected the Raid ID row highlight texture path discovered during the full Lua syntax audit.

## 1.14.49

- Refined the Raid Planner Port Helper layout.
- Moved the message field to its own full-width row.
- Increased the channel field width and aligned labels and inputs consistently.
- Shifted controls and request rows downward to avoid visual crowding.

## 1.14.48

- Port Helper now automatically removes summon requests after the player remains within approximate 40-yard group range for 0.75 seconds.
- Added a short confirmation delay to avoid removing entries because of a single transient range update.

## 1.14.42

- Added a Raid Planner Port Helper with configurable reply code, chat channel, and announcement text.
- Added typo-tolerant summon request detection for permutations such as `123`, `132`, and `1 2 3`.
- Added one clickable character button per request to target the player for summoning.
- Added group, offline, and approximate in-range status updates plus right-click removal.
- Added `/wnport` to open the Port Helper directly.

# v1.14.41

- Reworked PostalLite Open All for Auction House item mails.
- Prefer native AutoLootMailItem when available, falling back to TakeInboxMoney/TakeInboxItem.
- Try attachment slots in ascending order so AH-returned items in slot 1 are handled first.
- Keep stale-index retries and empty-letter cleanup for delayed 3.3.5a mailbox updates.

## 1.14.39

- Restored the Raid ID detail area to the previous read-only display by default.
- Moved manual boss kill toggles behind a dedicated "Edit Kills" button.
- Added an inline boss editor panel that opens only when explicitly requested and can be closed with "Done".

## 1.14.38

- PallyBuffs: pre-binds the main cast button and class-row buttons while out of combat so they remain usable in combat.
- PallyBuffs: avoids clearing or rewriting protected secure spell/unit attributes during combat.

## 1.14.36

- Fixed PostalLite Open All still stopping on Auction House mailboxes.
- Open All now also deletes safe empty letters during the worker run so looted AH mail does not leave a full mailbox behind.
- Added repeated inbox refresh calls and longer idle polling for stale Warmane/3.3.5a mailbox updates.

# 1.14.35

- Added an ICC live-combat fallback for Deathbringer Saurfang.
- As soon as combat log activity involving Saurfang is seen inside ICC, the tracker marks the three previous encounters as completed: Lord Marrowgar, Lady Deathwhisper, and Icecrown Gunship Battle.
- This covers the case where the raid reaches/pulls Saurfang before the server exposes reliable saved encounter data for Gunship.


### 1.14.32

- Fixed Raid ID Tracker progress detection for Icecrown Gunship Battle.
- Added Gunship/Luftschiff aliases and an ICC fallback boss order so progress-based saved instance data can mark Gunship as killed even when no normal boss death event fires.

# 1.14.29

## 1.14.32

- Restored Loot Tools access in the side menu under Character Tools.
- Added direct menu entries for Loot Tools, Auto Sell, and Auto Repair.


- Added an `Assign` button to the top of the PallyBuffs overlay.
- The overlay button opens the full PallyBuffs distribution menu directly without going through the main WoWNote UI.

# 1.14.26

- Fixed PostalLite Open All regression where a full AH mailbox could be reported as having no lootable mail.
- Open All now starts the rescan worker even when the first header scan is stale.
- Attachment detection now checks visible attachment slots via GetInboxItemLink/GetInboxItem instead of trusting only header itemCount.
- Attachment taking now prefers real visible slots and falls back to header itemCount only when needed.

## 1.14.24

- Fixed a startup error in PallyPower compatibility where saved assignment loading called `EnsurePally` before the local upvalue was declared.
- Keeps persisted blessing and aura assignments loading through the local helper instead of accidentally resolving a missing global.

## 1.14.23

- Removed the Item Tracker count-mode button from each row. Item counts are character-only now.
- Removed the visible repeat-seconds edit field from Item Tracker rows. The Repeat checkbox remains, using the internal default interval.
- Kept Item Tracker data stored per character in `WowNoteCharDB.itemTracker`.

## 1.14.22

- Restored mailbox-facing Postal-lite controls in the package instead of relying on missing embedded Postal files.
- Kept Manabonk cleanup automatic and moved manual cleanup into the mailbox toolbar without disturbing other mailbox buttons.
- Deletes already-empty Manabonk letters when the wand was already taken and only the letter remains.
- Persists PallyBuffs blessing and aura assignments across client restarts.
- Stores Item Tracker and Restock configuration per character via `WowNoteCharDB`.

## 1.14.21

- Fixed Manabonk mail cleanup so it no longer depends on `BAG_UPDATE_DELAYED` only.
- Added timed retry handling after `TakeInboxItem()` because 3.3.5a mailbox state can lag after taking attachments.
- Added a mailbox-local `Clean Manabonk` button and enabled automatic Manabonk cleanup by default.
- Deletes The Mischief Maker from bags first, then deletes the emptied Manabonk mail after the inbox confirms the attachment is gone.

# Changelog

## 1.14.37

- PallyBuffs overlay now tracks partial class buffs, for example 2/3 druids buffed, and keeps the class row red until every unit of that class has the assigned blessing.
- Raid ID Tracker adds clickable manual boss kill toggles for the selected raid ID.


## 1.14.20

- Added Social option to clean Manabonk mail containing The Mischief Maker.
- Uses item ID 44817 from the mailbox attachment check and only processes mails with exactly that one attachment.
- Takes the attachment, removes The Mischief Maker from the bags, and deletes the emptied mail after bag update.

## 1.14.19

- Fixed side submenu lifecycle so anchored submenus close together with the main WoWNote window.
- Exposed a shared submenu hide helper for future main-frame close/toggle handling.


## 1.14.18
- Replaced the Tactical HUD S-/S+ scale buttons with a single scale slider.
- Widened the Tactical HUD control frame so scale controls and status text fit cleanly.

## 1.14.17

- Fixed Tactical HUD close button frame level and mouse handling so the X button stays clickable.


## 1.14.16

- Added missing Draw Tools entries to the Quality of Life submenu.
- Added menu access for Screen Draw, Tactical Board and Tactical HUD clearing.
- Kept the draw tools reachable from the anchored submenu without requiring slash commands.

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

## 1.14.44

- Added explicit Start Tracking / Stop Tracking controls to the Raid Planner Port Helper GUI.
- Posting a port request now starts tracking automatically.
- Added `/wnport start` and `/wnport stop` commands.
- Chat requests and periodic range refreshes are ignored while tracking is stopped.
- Added a visible tracking status indicator to the Port Helper window.
