# Changelog

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
