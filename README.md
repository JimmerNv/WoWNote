# WoWNote

WoWNote is a World of Warcraft 3.3.5a addon for account-wide notes, character notes, raid planning, talent planning, tactical drawing, item tracking, bank snapshots, post/mail quality-of-life tools, and raid buff coordination.

It is designed for private servers based on Wrath of the Lich King 3.3.5a and focuses on practical in-game tools that reduce addon switching during raids, preparation, trading, mailbox cleanup, and group coordination.

## Current Version

**WoWNote 1.14.20**

## Features

* Account-wide notes
* Account-wide character notes
* Character tooltip notes
* Player context-menu note actions
* Talent planner
* Raid planner
* Raid ID tracker
* Item tracker and restock helper
* Bank snapshot view
* Tactical board
* Screen draw tools
* Tactical HUD drawing
* PallyBuffs raid buff coordination
* Data transfer picker for sending/exporting supported data
* Post/mail quality-of-life features
* Guild invite blocker
* Optional Manabonk postmaster mail cleanup
* Configurable module settings
* Optional minimap icon hiding

## Screenshots

### Main Menu

<img width="1024" height="611" alt="MainMenu" src="https://github.com/user-attachments/assets/2f87b636-6130-494a-a199-5d2c436fbfb3" />

### Settings

<img width="520" height="407" alt="Settings" src="https://github.com/user-attachments/assets/2bed13f3-35a1-4f28-8eb4-d62dfaf937b1" />

### Notes

<img width="538" height="391" alt="NoteExample" src="https://github.com/user-attachments/assets/66c1c48e-0015-4a4e-afc4-448ff448b4d9" />

### Character Notes

Character Notes are stored account-wide and separated by character name and realm.

They can be created or edited from the WoWNote UI or directly from the player context menu. If enabled, notes can also be shown in player tooltips.

<img width="467" height="469" alt="CharNoteMenu" src="https://github.com/user-attachments/assets/4bd19362-75a0-4b89-8b85-dca3d6a65739" />

<img width="169" height="249" alt="CharNootContextMenu" src="https://github.com/user-attachments/assets/41b393b8-199c-410c-a506-7476a8179a56" />

<img width="196" height="153" alt="CharNoteTooltip" src="https://github.com/user-attachments/assets/5310d955-61ad-4971-b4fc-b7f41497ed2b" />

### PallyBuffs

PallyBuffs adds raid buff assignment and coordination workflows with compatible raid buff communication.

It includes mass assignment helpers, Free On behavior, class assignment handling, a secure buff button workflow, and missing or expiring buff information.

<img width="1087" height="575" alt="PallyBuffs" src="https://github.com/user-attachments/assets/bad28303-3642-4b51-bfc7-9d938ef999a2" />

### Talent Planner

Plan, view, and manage talent builds directly in-game.

<img width="1032" height="950" alt="TalentPlaner" src="https://github.com/user-attachments/assets/bcce97da-13e9-4794-81a8-b6c4afca6dfb" />

### Tactical Board and Drawing Tools

WoWNote includes tactical tools for raid planning, positioning, visual explanations, and on-screen drawing.

<img width="1829" height="891" alt="TacDraw" src="https://github.com/user-attachments/assets/866b8a80-0252-4976-9592-aa22e1601f71" />

<img width="2588" height="1163" alt="ScreenDraw" src="https://github.com/user-attachments/assets/36d9f3ca-ba50-4493-9283-9ed7a59f342c" />

### Raid and ID Tools

WoWNote includes raid preparation and ID tracking tools.

<img width="1104" height="805" alt="PugHelper-RaidHelper" src="https://github.com/user-attachments/assets/8bade0dc-520e-4170-b6ad-6a276e0de1a6" />

<img width="942" height="562" alt="IdTracker" src="https://github.com/user-attachments/assets/852f8229-162d-44ce-a3a7-e5cb1c359f2b" />

### Item Tracker and Restock

The item tracker can monitor important consumables, reagents, materials, and supplies.

Restock support calculates the needed amount based on target minus current inventory and buys the required vendor units instead of filling the inventory.

<img width="910" height="615" alt="Restocker" src="https://github.com/user-attachments/assets/583181ab-a285-48da-9557-36585d3b5978" />

<img width="231" height="114" alt="ItemtrackerHud" src="https://github.com/user-attachments/assets/af7f5f25-607f-4e56-989e-41cc309afb22" />

### Bank

Bank snapshots help track stored items and inventory-related data.

<img width="799" height="618" alt="Bank" src="https://github.com/user-attachments/assets/c5877f47-5db1-4673-93f0-36df1a192fda" />

### Post Features

Post/mail quality-of-life tools are available as an optional module.

<img width="392" height="480" alt="PostFeatures" src="https://github.com/user-attachments/assets/417b0e80-18c0-47a5-baf1-0e52e65987d8" />

### Social Features

Social tools include guild invite blocking and optional Manabonk mail cleanup.

<img width="188" height="73" alt="GuildInviteBlocker" src="https://github.com/user-attachments/assets/56137184-d24c-4117-93bf-4b7713271fa0" />

## Menu Structure

WoWNote uses a structured main menu with anchored submenus.

```text
Notes
Character Notes
Bank

Quality of Life
- Raid Planner
- PallyBuffs
- Screen Draw
- Tactical Board
- Clear Tactical HUD

Data Transfer
- Send / Receive
- Import / Export

Character Tools
- Talents
- Raid IDs
- Tracker
- Restock

Social
- Block Guild Invite
- Clean Manabonk Mail

Settings
- Module settings
- Always show character note
- Mail features
- PallyBuffs
- Social protections
- Data transfer
- Hide minimap icon
```

## Data Transfer

The Data Transfer Picker allows choosing what should be sent or exported without opening the matching feature first.

Supported categories include:

* Notes
* Character Notes
* Tactics
* Raid Planner data
* Talents
* Raid IDs
* Tracker / Restock data
* Bank data

## Character Notes

Character Notes are account-wide and stored by character name and realm.

Supported actions:

* Create character note from player context menu
* Edit character note
* Delete character note
* Show character note from context menu
* Optional tooltip display when hovering players

## PallyBuffs

PallyBuffs provides raid buff coordination tools.

Supported features:

* Blessing assignments
* Aura assignments
* Free assignment state
* Mass assignment helpers
* All-button support for quick class-wide assignment
* Secure buff button workflow
* Missing-buff detection
* Remaining-time display
* Compatible communication with existing raid buff clients

## Item Tracker and Restock

The item tracker can monitor inventory counts and display alerts when configured thresholds are reached.

Restock behavior:

```text
Target - Current = Need
Need / Vendor stack size = Vendor units to buy
```

The restock logic is guarded against repeated purchase loops and avoids filling the inventory unintentionally.

## Social Tools

### Guild Invite Blocker

When enabled, WoWNote can block incoming guild invites.

### Manabonk Mail Cleanup

When enabled, WoWNote can clean Manabonk postmaster mail.

The cleanup is defensive:

* Detects `The Mischief Maker` by item ID `44817`
* Only processes mails with exactly one matching attachment
* Ignores mails with money
* Ignores COD mails
* Ignores mails with multiple attachments
* Takes the matching attachment
* Removes the matching item
* Deletes the empty mail afterwards

This feature is disabled by default.

## Settings

Settings include module toggles and UI behavior options.

Available settings include:

* Mail features
* PallyBuffs
* Character Notes
* Social protections
* Data transfer
* Always show character note
* Clean Manabonk mail
* Block guild invite
* Hide minimap icon

## Installation

1. Download the latest release ZIP.
2. Extract the `WoWNote` folder into:

```text
World of Warcraft/Interface/AddOns/
```

3. Restart the game or run:

```text
/reload
```

4. Open WoWNote from the minimap icon or slash command.

## Slash Commands

```text
/wownote
/wn
/wnpp
/wnpostal
```

Available commands may depend on enabled modules.

## Compatibility

WoWNote targets **World of Warcraft 3.3.5a**.

The addon is designed for Wrath of the Lich King private-server environments and may not work correctly on modern retail clients.

## Notes

Some features interact with protected WoW UI behavior. WoWNote avoids automated protected actions where possible and uses click-based workflows for secure actions such as buff casting.

## Version History

### 1.14.20

* Fixed anchored submenu interaction and lifecycle behavior.
* Restored missing tool entries in the Quality of Life menu.
* Fixed Talent Planner menu routing.
* Improved Tactical HUD controls.
* Added optional Manabonk mail cleanup.
* Added and improved account-wide Character Notes.
* Improved PallyBuffs raid buff coordination.
* Improved item tracker alerts and safer restock behavior.
* Added minimap icon visibility setting.
* Improved Data Transfer Picker workflows.
* Updated WoWNote to version **1.14.20**.
