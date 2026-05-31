# Development Notes

## Target environment

- World of Warcraft 3.3.5a
- Interface version `30300`
- Lua 5.1 as embedded by the WoW client

## Important constraints

### Lua local variable limit

WoW/Lua 5.1 can fail when one chunk contains too many local variables. Keep top-level `local` declarations under control, especially because `WowNote.lua` is loaded as one large chunk.

Typical error:

```text
main function has more than 200 local variables
```

### Chat payload escaping

WoW chat messages treat `|` as a control/escape character for links, colors, and textures. Any experimental channel transport must escape raw pipe characters before sending.

The Carbonite-style workaround is to replace `|` with `\001` during chat transport and restore it on receive.

### Private-server throttling

The tested server appears to throttle or mute characters that send too many chat/channel messages too quickly. Larger note transfers over normal chat channels are therefore not reliable enough for a visible user-facing feature.

## Share code status

The code still contains internal sharing/transport functions for future work. The visible Share menu entry has been removed so normal users do not trigger a workflow that is unreliable on the tested server.

## Packaging

Run from the repository root:

```bash
./scripts/package.sh
```

The output is written to:

```text
dist/WowNote.zip
```
