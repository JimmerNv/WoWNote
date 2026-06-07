# WowNote

WowNote is a World of Warcraft 3.3.5a addon for account-wide notes, talent builds, raid planning, raid ID tracking, tactical drawings, and loot/vendor convenience tools.

It provides an in-game note editor, a talent planner, a raid planner with reusable presets, roster assignments, import/export support, loot tools, raid lockout tracking, screen drawing, tactical map drawings, and HUD-style tactical overlays.

## Features

### Notes

- Account-wide saved notes through `WowNoteDB`
- In-game note editor
- Markdown-style lightweight note formatting
- Item link handling in note content
- Import/export support for sharing notes as text

### Talent Planner

- Built-in talent planner for Wrath of the Lich King
- Save and load talent builds
- Export/import talent builds for sharing
- Designed for client interface `30300`

### Raid Planner

- Create and preview LFM messages directly in-game
- Raid size selection: `10`, `25`, or custom
- Editable raid name
- Role requirements for Tanks, Healers, DPS, mDPS, and rDPS
- Automatic missing-role calculation
- Optional roster assignments by role
- Automatic role counting based on assigned players
- Automatic removal of tracked group/raid members when they leave
- Configurable posting channel, such as `/2`, `/5`, `/y`, `/g`, `/p`, or `/raid`
- Custom message templates with placeholders
- Additional info field
- Contact field, for example `/w me` or `/w CharacterName`
- Internal note field that is saved but not posted

### Raid Planner Presets

- Save reusable raid planner presets
- Load, update, and delete saved presets
- Import/export presets as text
- Share complete raid setups with other players
- Presets include role setup, roster assignments, channel, template, additional info, contact text, and internal notes

### Loot Tools

WowNote includes a combined Loot Tools window with multiple tabs.

Available tools:

- Auto Roll
- Auto Sell
- Auto Repair

Settings are saved per character where appropriate.

### Auto Loot Roller

- Optional auto roll system for loot windows
- Automatically rolls Disenchant if available, otherwise Greed
- Configurable maximum item rarity
- Optional maximum item level filter
- Level protection for level 80+ characters
- Queue-based handling for multiple simultaneous loot rolls
- Automatic confirmation handling for Disenchant rolls
- Character-specific Auto Roll settings
- Auto Roll blacklist support

Safety exclusions:

- Epic Bind-on-Equip items are always excluded
- Primordial Saronite is always excluded
- Need rolls are never performed automatically

### Auto Sell

- Automatically sell gray items
- Optionally sell weapons automatically
- Optionally sell armor automatically
- Configurable maximum rarity for equipment selling
- Optional maximum item level filter for weapons and armor
- Force Sell list for items that should always be sold
- Never Sell list for items that should never be sold
- Supports item names, item links, and item IDs
- Quick-add support for adding bag items to Force Sell or Never Sell
- Automatic sorting and cleanup of sell lists when saved
- Chat summary showing how many items were sold and how much gold was gained

Safety exclusions:

- Epic Bind-on-Equip items are never auto-sold
- Primordial Saronite is never auto-sold

### Auto Repair

- Automatically repair at repair vendors
- Optional guild bank repair support
- Falls back to personal gold if guild repair is unavailable
- Prints repair cost feedback in chat

### Raid ID Tracker

WowNote can track raid lockouts across characters on the same account.

Features:

- Raid ID overview window
- Tracks saved raid IDs per character
- Stores raid name, size/mode, ID, and remaining lockout time
- Shows lockouts account-wide
- Shows which of your characters share the same raid ID
- Stores known group/raid members seen with a specific raid ID
- Tracks additional players if they join later during the same lockout
- Allows clearing saved member lists for a selected ID
- Allows posting selected IDs or all known IDs
- Allows posting saved member lists for a selected raid ID
- Supports posting to channels such as `/g`, `/p`, `/raid`, `/2`, `/5`, `/y`, and `/s`
- Supports whisper posting, for example `/w CharacterName`
- Imports compatible WowNote raid ID data from chat if the local character has the same ID

Important limitation:

WowNote cannot query the server for a full list of everyone saved to a raid ID. It can only store players your client has seen while grouped or raiding with that lockout, plus data shared by other WowNote users.

### Screen Draw

Screen Draw provides a simple shared screen overlay for quick explanations.

Features:

- Draw directly on a screen overlay
- 10 selectable colors
- Configurable line thickness
- Undo
- Clear
- Hide/show overlay
- Export/import drawings as text
- Share drawings over the WowNote addon channel

This is a screen overlay, not a true 3D world drawing. Drawings stay on the screen and do not attach to the game world.

### Tactical Board

The Tactical Board is a separate planning window for raid and boss tactics.

Features:

- Draw on a dedicated tactical board
- Use the current map as a background where available
- Save and load tactical drawings
- Select saved drawings from a preset list
- Export/import tactical drawings
- Share tactical drawings over the WowNote addon channel
- 10 selectable colors
- Configurable line thickness
- Undo
- Clear
- Optional HUD handoff for displaying tactical drawings as an overlay

This is intended for raid explanations, boss planning, movement sketches, and shared tactical preparation.

### HUD Draw

HUD Draw can display tactical drawing data as a radar-style overlay.

Features:

- Shows tactical points/lines relative to the player
- Uses map/player position and facing where available
- Designed as a best-effort HUD overlay similar in concept to Gatherer-style positional HUDs
- Can display tactical drawings created in the Tactical Board

Important limitation:

HUD Draw is not true 3D rendering and does not place real lines on the ground. It is a best-effort tactical overlay based on map/player positioning.

### UI Integration

- Main WowNote window
- Note editor
- Talent Planner window
- Raid Planner window
- Loot Tools window
- Raid ID Tracker window
- Screen Draw window
- Tactical Board window
- HUD Draw overlay
- Minimap button
- Titan Panel integration via optional dependency

Minimap controls:

- Left-click: open WowNote
- Right-click: open Raid Planner
- Middle-click: open Loot Tools
- Drag: move the minimap icon

## Screenshots

### Notes

<img width="844" height="544" alt="WowNote Notes" src="https://github.com/user-attachments/assets/3367bfa2-932b-4134-93a6-e879d86ee6de" />

### Talent Planner

<img width="1135" height="675" alt="WowNote Talent Planner" src="https://github.com/user-attachments/assets/06b3fb60-9bb8-4ba9-a727-e8ec626579ce" />

### Raid Planner

<img width="1865" height="1014" alt="WowNote Raid Planner" src="https://github.com/user-attachments/assets/48cb69f9-abf9-4627-ad7a-283b65071822" />

### Loot Tools

<img width="1101" height="874" alt="WowNote Loot Tools" src="https://github.com/user-attachments/assets/033f1ee5-81b4-4559-892e-dceefb0253a1" />

### Screen Draw

<img width="1415" height="513" alt="Draw" src="https://github.com/user-attachments/assets/aefe7b2a-57d5-42ca-858c-7de050c49bc3" />

### Raid ID Tracker

<img width="1155" height="662" alt="Id" src="https://github.com/user-attachments/assets/d052b505-8573-40dd-bfef-ec6ceb1a8535" />

### Tactical Board and HUD

<img width="2142" height="936" alt="TacticAndHud" src="https://github.com/user-attachments/assets/5aaec821-77cd-480f-a955-84de4774ed48" />

## Installation

1. Download the latest release ZIP from the [Releases](https://github.com/JimmerNv/WoWNote/releases) page.
2. Extract the ZIP.
3. Make sure the addon folder is named exactly:

   ```text
   WowNote
