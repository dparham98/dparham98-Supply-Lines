# Command card art

The 82 ruby and gold cards in `assets/ui/command_cards/` come from the `supply-lines-command-cards-v1` pack. Each is an opaque 128 px PNG with no text, imported lossless with no mipmaps. The small tinted glyphs in `assets/ui/icons/` stay in use for stats, portraits, alerts and other small graphics.

## Where they are used

- All 36 square tiles use cards: the command grid, the global build page and the Cancel button on the pick prompt. They are assigned in `scenes/ui/skirmish_hud.tscn`.
- Each tile uses the `CommandCard` theme variation in `assets/ui/supply_lines_theme.tres`. It draws the card edge to edge at the 46 px tile size, without changing other buttons.
- The other cards (header, selection strip, alerts, crate panel, dropdowns, rail hints, F10 panel) are in the folder but not assigned. Those controls have text labels or dynamic content and are not square tiles.

## Art that follows state

`set_card()` in `scripts/gameplay/skirmish_hud.gd` swaps the image:

| Button | Images |
| --- | --- |
| Auto-refuel | On or off, showing the current setting |
| Trips | Once, all or repeat, showing the current setting |
| Deploy/Pack up supplies | The action the button will take |
| Generator Pause/Resume | The action the button will take |
| Pin/Unpin payer | The action the button will take |

## Button states

Cards are opaque, so states use the image colour instead of the background: hover brightens, pressed and disabled darken. A tile that cannot be afforded is also darkened, and its tooltip still says what is missing. Unaffordable and disabled tiles look similar, but the card is still clickable.

`tests/command_cards_test.gd` covers assignment, fit and the state swaps. Nobody has judged the look or the small-size readability in play.
n## HUD colours

The HUD palette matches the supplied HUD reference: olive-black panels, bronze borders, gold accents, a crimson message strip and cream text. Health stays green. Energy is now cream everywhere it appears as a resource. Team colours, the other resource colours and world markers (selection box, Depot range ring, order pings) did not change.
