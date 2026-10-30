-- Options window: an AceConfig-format table rendered by LibConfig-1.0 in its
-- own window (AceConfigDialog-3.0 and AceGUI-3.0 do not work on Unreal
-- Azeroth). The root group is a tab strip; every tab is built by its own
-- file into S.options.args before InitializeOptions registers the table.
-- Pattern of Vuh's Options/Options.lua.
--
-- The builders below are shared by the window tabs: getDB returns the
-- window's profile table, apply re-applies the window after a change, so a
-- change shows at once.

local S, L, P, G = unpack(Stuffs)
local Compat = Stuffs.Compat

local APP_NAME = "Stuffs"

S.options = {
	type = "group",
	name = "Stuffs",
	childGroups = "tab",
	args = {},
}

function S.OptionToggle(getDB, apply, key, order, name, desc)
	return {
		type = "toggle",
		order = order,
		name = name,
		desc = desc,
		get = function() return getDB()[key] end,
		set = function(_, value)
			getDB()[key] = value and true or false
			apply()
		end,
	}
end

function S.OptionRange(getDB, apply, key, order, name, min, max, step, desc, isPercent)
	return {
		type = "range",
		order = order,
		name = name,
		desc = desc,
		min = min,
		max = max,
		step = step,
		isPercent = isPercent,
		get = function() return getDB()[key] end,
		set = function(_, value)
			getDB()[key] = value
			apply()
		end,
	}
end

-- Every LibSharedMedia entry of a media type by name, built on every
-- render: other addons register theirs at load time or later.
local function MediaValues(mediaType)
	local values = {}
	local names = LibStub("LibSharedMedia-3.0"):List(mediaType)
	for i = 1, Compat.getn(names) do
		values[names[i]] = names[i]
	end
	return values
end

local function TextureValues()
	return MediaValues("statusbar")
end

function S.SoundValues()
	return MediaValues("sound")
end

-- Adds the "Window" (orders 1-4) and "Bars" (10-14) sections of a window
-- tab to args: shown, locked, Reset position; bar height, spacing, texture
-- and background opacity.
function S.AddWindowOptions(args, getDB, apply, lockDesc, resetPosition)
	args.windowHeader = { type = "header", order = 1, name = L["Window"] }
	args.shown = S.OptionToggle(getDB, apply, "shown", 2, L["Show window"])
	args.locked = S.OptionToggle(getDB, apply, "locked", 3, L["Lock window"], lockDesc)
	args.resetPosition = {
		type = "execute",
		order = 4,
		name = L["Reset position"],
		desc = L["Move the window back to its default place and size."],
		func = resetPosition,
	}

	args.barsHeader = { type = "header", order = 10, name = L["Bars"] }
	args.barHeight = S.OptionRange(getDB, apply, "barHeight", 11, L["Bar height"], 10, 40, 1)
	args.barSpacing = S.OptionRange(getDB, apply, "barSpacing", 12, L["Bar spacing"], 0, 10, 1)
	args.texture = {
		type = "select",
		dialogControl = "LSM30_Statusbar",
		order = 13,
		name = L["Bar texture"],
		desc = L["Textures other addons register with LibSharedMedia are listed too."],
		values = TextureValues,
		get = function() return getDB().texture end,
		set = function(_, value)
			getDB().texture = value
			apply()
		end,
	}
	args.bodyAlpha = S.OptionRange(getDB, apply, "bodyAlpha", 14, L["Background opacity"], 0, 1, 0.05, nil, true)
end

function S:InitializeOptions()
	self:BuildDamageOptions()
	self:BuildThreatOptions()
	LibStub("LibConfig-1.0"):RegisterOptionsTable(APP_NAME, APP_NAME, self.options)
end

-- The LibConfig-1.0 window is shared by every addon that embeds the
-- library, so "shown" may mean another addon's page is open; a toggle then
-- closes that too.
function S:ToggleOptions()
	local LC = LibStub("LibConfig-1.0")
	local panel = LC:AddToBlizOptions(APP_NAME, APP_NAME)
	if panel and panel:IsShown() then
		LC:Close()
	else
		LC:OpenToCategory(APP_NAME)
	end
end
