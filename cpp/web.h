#pragma once

// The web version's helpers (see docs/platform.md, Web): what only the
// browser's JavaScript can do. Built for the web alone (build.rs).

// Whether the browser runs on a Mac, where Koil acts as the Mac app does:
// Qt for the web hands Cmd as Ctrl there too (and Ctrl as Meta).
bool webOnMac();

// Gives the page Koil's colors, now and as they change (CSS variables and
// `data-theme` on its root), for the page to draw the windows' frames
// (Qt's own, in the page's HTML) in them, and its background.
void useWebPage();

// While `on`, has Qt's color scheme follow the browser's light or dark
// mode, now and as it changes. Qt for the web reads neither (its scheme
// is Unknown), and then gives windows a light palette but text areas a
// dark one.
void followBrowserColorScheme(bool on);
