# pfQuest Targeting

A companion addon for [pfQuest](https://github.com/shagu/pfQuest) that turns your active kill objectives into a live targeting panel. Instead of hunting through your quest log, every mob you need to kill appears as a clickable button, click to target instantly.

## Features

### Target Panel
- Automatically populates with every mob from your active kill objectives
- Buttons dim when a mob isn't nearby and light up with a green glow when one enters nameplate range
- Click any button to target that mob directly
- Shows a live portrait when the mob is on your screen (nameplate range)
- Resizes dynamically as objectives are completed or added
- Draggable and lockable, saves position across sessions

### Auto-Mark
- Automatically applies a raid marker to quest mobs when they appear on your nameplate, when you target them, or when you mouseover them
- Configurable mark type (Star through Skull)
- "Mark on mouseover" can be toggled independently so hovering doesn't disturb an existing mark

### Drop Quest Support
- Reads pfQuest's item database to resolve which mobs drop required items, so item collection quests show up in the panel alongside kill quests

### Macro Integration
- Maintains a macro (`pfQTarget`) with `/targetexact` lines for every active mob, drag it to your bar for one-click cycling through targets

### Sound Alert
- Plays a sound when a quest mob enters nameplate range (2-second cooldown to prevent spam)

### Completion Flash
- Flashes the panel and plays a sound when an objective is completed

### Minimap Button
- Draggable minimap button to toggle the panel; right-click to hide it (re-enable in settings)

## Options

Open with `/pfqt options` or click the gear icon on the panel.

| Option | Description |
|---|---|
| Show portraits | Display mob portrait when in nameplate range |
| Lock window position | Prevent accidental dragging |
| Show minimap button | Toggle the minimap button |
| Background opacity | Adjust panel transparency |
| Buttons per row | Control panel layout |
| Auto-target | Target mobs automatically when their nameplate appears |
| Auto-target in combat | Allow auto-targeting while in combat |
| Auto-mark | Apply raid marker to quest mobs |
| Mark on mouseover | Apply mark when mousing over a quest mob |
| Mark type | Choose which raid icon to use (Star–Skull) |
| Sound alert | Play a sound when a quest mob enters range |
| Include drop quests | Show mobs for item collection objectives |
| Enable targeting macro | Maintain the `pfQTarget` macro |
| Window scale | Resize the target panel |

## Commands

| Command | Description |
|---|---|
| `/pfqt` | Force refresh |
| `/pfqt options` | Open settings panel |
| `/pfqt debug` | Print active mobs and drop quest info |

## Requirements

- [pfQuest](https://github.com/shagu/pfQuest) (or a compatible fork with pfDB), used for mob name lookups and drop quest resolution. The target panel still works without pfQuest but drop quest support will be unavailable.

## Compatibility

WoW WotLK 3.3.5 tested on [Ascension](https://ascension.gg/) Epoch.
