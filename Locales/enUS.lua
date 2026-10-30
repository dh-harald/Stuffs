-- English strings -- the default locale, and currently the only one.
--
-- Keys are the English text itself, and every value is `true` (AceLocale's
-- shorthand for "the key is its own value"), so an untranslated string always
-- reads correctly. The four-argument NewLocale form sets `silent`: an unknown
-- key returns the key instead of raising. AceLocale only accepts `silent` on
-- the first locale registered for an application, which is this file.

local L = LibStub("AceLocale-3.0"):NewLocale("Stuffs", "enUS", true, true)

--Core
L["Initialized."] = true
L["version %s"] = true
L["/stuffs - options window"] = true
L["/stuffs damage - show or hide the damage window"] = true
L["/stuffs reset - clear the current and overall data"] = true
L["/stuffs lock | unlock - lock the windows, or move and resize them"] = true
L["/stuffs debug - print recognized combat log lines"] = true
L["/stuffs threat - show or hide the threat window"] = true
L["/stuffs debug all - also print unrecognized lines"] = true
L["/stuffs debug threat - print every threat change"] = true

--Combat log
L["Debug off."] = true
L["Debug: recognized combat log lines are printed."] = true
L["Debug: recognized and unrecognized combat log lines are printed."] = true
L["Debug: every threat change is printed."] = true
L["Threat debug off."] = true
L["Templates missing on this client: %s"] = true

--Segments
L["Data reset."] = true
L["Melee"] = true
L["Damage Shield"] = true
L["%s (DoT)"] = true
L["%s (HoT)"] = true

--Options
L["Damage window"] = true
L["Window"] = true
L["Show window"] = true
L["Lock window"] = true
L["A locked window cannot be moved or resized; its title bar still switches modes."] = true
L["Reset position"] = true
L["Move the window back to its default place and size."] = true
L["Bars"] = true
L["Bar height"] = true
L["Bar spacing"] = true
L["Bar texture"] = true
L["Textures other addons register with LibSharedMedia are listed too."] = true
L["Background opacity"] = true
L["Modes"] = true
L["Modes in the title bar cycle"] = true
L["Shown mode"] = true
L["Shown data"] = true
L["Pets"] = true
L["Merge pets with their owner"] = true
L["Add a pet's damage and healing to its owner's row; the tooltip still lists the pet's spells."] = true
L["Tooltip"] = true
L["Show tooltip"] = true
L["Hovering a bar shows the totals and the breakdown by spell."] = true
L["Spells in the tooltip"] = true
L["0 shows the totals only."] = true
L["Data"] = true
L["Reset data"] = true
L["Clear the current fight and the overall data."] = true
L["Threat window"] = true
L["A locked window cannot be moved or resized."] = true
L["Aggro warning"] = true
L["Show a warning message"] = true
L["A raid warning style message in the middle of the screen."] = true
L["Warning sound"] = true
L["Played on the Master channel. None plays no sound; sounds other addons register with LibSharedMedia are listed too."] = true
L["Warn at"] = true
L["Share of the threat that pulls aggro from the tank: more than 110% of the tank's threat in melee range, 130% farther away."] = true
L["Minimum threat"] = true
L["No warning below this much threat."] = true
L["Test warning"] = true
L["Test"] = true

--Tooltip
L["Pet of %s"] = true
L["Overheal"] = true
L["%d hits, %.0f%% crit"] = true
L["%d hits, %.0f%% OH"] = true
L["... and %d more"] = true

--Windows
L["Damage"] = true
L["DPS"] = true
L["Healing"] = true
L["HPS"] = true
L["Total healing"] = true
L["%s (%.0f%% OH)"] = true
L["Current"] = true
L["Overall"] = true
L["Windows locked."] = true
L["Windows unlocked. Drag the title bar to move a window, the bottom right corner to resize it."] = true
L["Damage window title: left-click next mode, right-click current/overall, Shift-click reset."] = true
L["Threat"] = true
L["Threat: %s"] = true
L["%s (tank)"] = true
L["Aggro warning: %.0f%% on %s"] = true
