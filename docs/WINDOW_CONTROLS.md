# Window controls

Added 2026-11-24. The camera keeps the cursor inside the window while the game has focus, so edge panning stops at the edge (docs/CAMERA_RIG.md). That also kept it off the title bar, so the window could not be moved, closed with its X, or made fullscreen.

- **F11** or **Alt+Enter** switches between fullscreen and a window, on every screen, paused or not, including while the pause menu is open. It is `scripts/ui/window_controls.gd`, the `WindowControls` autoload.
- **The pause menu (Esc) frees the cursor.** While it is open, the cursor can leave the window, so you can move, resize or close it. Resume gives back the cursor's mode, so edge panning is confined again. Restart and Main menu leave it to the next screen: a map's camera confines it again, and the main menu leaves it free.
- **Alt+Tab** still frees the cursor as before, and Alt+F4 still closes the game.

## Checks

`tests/window_controls_test.gd` (headless) checks:
- F11 and Alt+Enter are the fullscreen key, and Enter alone, a held F11 and F10 are not;
- the mode it picks: windowed or maximised goes to fullscreen, and either fullscreen goes back to a window;
- the autoload runs while the game is paused;
- the pause menu frees the cursor and gives back its mode on Resume.

A headless run has no real window or cursor, so neither the switch on screen nor the confinement after Resume is checked there.
