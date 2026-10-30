-- Stuffs core bootstrap.
--
-- The global `Stuffs` table is the engine every other file reaches the addon
-- through, as `local S, L, P, G = unpack(Stuffs)`:
--   [1] the AceAddon object, [2] the AceLocale table,
--   [3] profile defaults, [4] global defaults.
-- The 1.12.1 client passes no addon name/private table to a file chunk
-- (and `...` at chunk level does not parse on Lua 5.0), so a global engine
-- table is the only way to share state between files.

Stuffs = Stuffs or {}

local AddOnName = "Stuffs"
local Engine = Stuffs

local AddOn = LibStub("AceAddon-3.0"):NewAddon(AddOnName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local Locale = LibStub("AceLocale-3.0"):GetLocale(AddOnName)

AddOn.noop = function() end

-- The packager replaces the .toc's "@project-version@" with the release tag
-- ("v1.2.3"); an unpackaged working copy reports "dev".
local version = GetAddOnMetadata(AddOnName, "Version")
if version and string.sub(version, 1, 1) == "v" then
	AddOn.version = string.sub(version, 2)
else
	AddOn.version = "dev"
end

-- AceDB defaults. Files loaded after this one fill them in at file load time,
-- which is before ADDON_LOADED drives OnInitialize.
AddOn.defaults = { profile = {}, global = {} }

Engine[1] = AddOn
Engine[2] = Locale
Engine[3] = AddOn.defaults.profile
Engine[4] = AddOn.defaults.global

function AddOn:OnInitialize()
	-- `true`: characters without an explicit profile share "Default".
	self.db = LibStub("AceDB-3.0"):New("StuffsDB", self.defaults, true)

	self:InitializeMedia()
	self:InitializeOptions()

	self:RegisterChatCommand("stuffs", "HandleSlashCommand")

	self:Print(Locale["Initialized."])
end

function AddOn:OnEnable()
	self:InitializeRoster()
	self:InitializeCombat()
	self:InitializeSegments()
	self:InitializeDamageWindow()
	self:InitializeThreatWindow()
	self:InitializeThreatWarning()
end

-- /stuffs alone opens the options; /stuffs damage | threat | reset | lock |
-- unlock | debug [all | threat]; anything else prints the version and the
-- command list.
function AddOn:HandleSlashCommand(input)
	local _, _, command, rest = string.find(input or "", "^%s*(%S*)%s*(.-)%s*$")
	command = string.lower(command or "")
	rest = string.lower(rest or "")

	if command == "" then
		self:ToggleOptions()
	elseif command == "damage" then
		self:ToggleDamageWindow()
	elseif command == "threat" then
		self:ToggleThreatWindow()
	elseif command == "reset" then
		self:ResetData()
	elseif command == "lock" then
		self:SetLocked(true)
	elseif command == "unlock" then
		self:SetLocked(false)
	elseif command == "debug" then
		self:SetDebug(rest)
	else
		self:Print(string.format(Locale["version %s"], self.version))
		self:Print(Locale["/stuffs - options window"])
		self:Print(Locale["/stuffs damage - show or hide the damage window"])
		self:Print(Locale["/stuffs threat - show or hide the threat window"])
		self:Print(Locale["/stuffs reset - clear the current and overall data"])
		self:Print(Locale["/stuffs lock | unlock - lock the windows, or move and resize them"])
		self:Print(Locale["/stuffs debug - print recognized combat log lines"])
		self:Print(Locale["/stuffs debug all - also print unrecognized lines"])
		self:Print(Locale["/stuffs debug threat - print every threat change"])
		self:Print(Locale["Damage window title: left-click next mode, right-click current/overall, Shift-click reset."])
	end
end
