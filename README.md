# DockEcho

Your Dock, echoed on every screen. DockEcho mirrors the macOS Dock on your external
displays (the primary display is excluded by default; there is an option in the menu bar menu).

*Imagined by Daniel Glazman, created by Anthropic Claude.*

## Build
Requirements: macOS 12+, Xcode 15+ or the matching Command Line Tools (`xcode-select --install`).

    ./build.sh
    open DockEcho.app

A menu bar icon gives access to: About, Refresh Dock, Also show on main display, Quit.

## Staying in sync with the main Dock
The `com.apple.dock` preferences are watched continuously (notification + a check every second):
any change made in System Settings > Desktop & Dock, or to the pinned apps of the real Dock,
is applied to every copy within about a second.

Supported settings:
- Icon size (`tilesize`), magnification (`magnification`, `largesize`)
- Position on screen: bottom, left, right (`orientation`)
- Automatically hide and show (`autohide`, `autohide-delay`, `autohide-time-modifier`),
  with a fade in/out
- Launch animation (`launchanim`, bouncing icon)
- Indicators for running apps (`show-process-indicators`)
- Recent apps (`show-recents`) and "show only open applications" (`static-only`)
- Pinned apps, spacers (`spacer-tile`), folders/files (`persistent-others`), Trash

Not supported (no public API or too complex): minimized windows in the Dock, minimize effect,
stacks (fan/grid), notification badges, drag and drop.

## Notes
- Animations: each icon is a Core Animation layer driven by the display's refresh
  (CADisplayLink on macOS 14+, a 120 Hz timer on older systems), so the magnification
  stays smooth. Magnification follows the cursor with no lag and eases in and out only
  when the cursor enters or leaves.
- Trash: the real macOS Trash icons are used. To switch between the empty and full icons,
  DockEcho needs to read `~/.Trash`, which requires Full Disk Access
  (System Settings > Privacy & Security > Full Disk Access). Without it the empty icon is shown.
- To start at login: System Settings > General > Login Items > add DockEcho.app.
