-- Options tab "Damage window": visibility, lock and position, the bars'
-- look (the shared window sections, Options.lua), the modes the title bar
-- cycles through, pets and the tooltip. Every setter writes the profile and
-- re-applies the window (S:ApplyDamageWindowSettings), so a change shows at
-- once.

local S, L, P, G = unpack(Stuffs)
local Compat = Stuffs.Compat

local function DB()
	return S.db.profile.damage
end

local function Apply()
	S:ApplyDamageWindowSettings()
end

local function ModeValues()
	local values = {}
	for i = 1, Compat.getn(S.DAMAGE_MODES) do
		local mode = S.DAMAGE_MODES[i]
		values[mode] = S:DamageModeLabel(mode)
	end
	return values
end

local function EnabledModeValues()
	local values = {}
	local db = DB()
	for i = 1, Compat.getn(S.DAMAGE_MODES) do
		local mode = S.DAMAGE_MODES[i]
		if db.modes[mode] then
			values[mode] = S:DamageModeLabel(mode)
		end
	end
	return values
end

local function Toggle(key, order, name, desc)
	return S.OptionToggle(DB, Apply, key, order, name, desc)
end

local function Range(key, order, name, min, max, step, desc, isPercent)
	return S.OptionRange(DB, Apply, key, order, name, min, max, step, desc, isPercent)
end

function S:BuildDamageOptions()
	self.options.args.damage = {
		type = "group",
		order = 1,
		name = L["Damage window"],
		args = {
			modesHeader = { type = "header", order = 20, name = L["Modes"] },
			modes = {
				type = "multiselect",
				order = 21,
				name = L["Modes in the title bar cycle"],
				values = ModeValues,
				get = function(_, key) return DB().modes[key] end,
				set = function(_, key, value)
					local db = DB()
					db.modes[key] = value and true or false
					-- At least one mode stays enabled.
					local any = false
					for i = 1, Compat.getn(S.DAMAGE_MODES) do
						if db.modes[S.DAMAGE_MODES[i]] then any = true end
					end
					if not any then db.modes[key] = true end
					S:ApplyDamageWindowSettings()
				end,
			},
			mode = {
				type = "select",
				order = 22,
				name = L["Shown mode"],
				values = EnabledModeValues,
				get = function() return DB().mode end,
				set = function(_, value)
					DB().mode = value
					S:ApplyDamageWindowSettings()
				end,
			},
			segment = {
				type = "select",
				order = 23,
				name = L["Shown data"],
				values = { current = L["Current"], overall = L["Overall"] },
				get = function() return DB().segment end,
				set = function(_, value)
					DB().segment = value
					S:ApplyDamageWindowSettings()
				end,
			},

			petsHeader = { type = "header", order = 30, name = L["Pets"] },
			mergePets = Toggle("mergePets", 31, L["Merge pets with their owner"],
				L["Add a pet's damage and healing to its owner's row; the tooltip still lists the pet's spells."]),

			tooltipHeader = { type = "header", order = 40, name = L["Tooltip"] },
			tooltip = Toggle("tooltip", 41, L["Show tooltip"],
				L["Hovering a bar shows the totals and the breakdown by spell."]),
			tooltipSpells = Range("tooltipSpells", 42, L["Spells in the tooltip"], 0, 20, 1,
				L["0 shows the totals only."]),

			dataHeader = { type = "header", order = 50, name = L["Data"] },
			reset = {
				type = "execute",
				order = 51,
				name = L["Reset data"],
				desc = L["Clear the current fight and the overall data."],
				func = function() S:ResetData() end,
			},
		},
	}
	S.AddWindowOptions(self.options.args.damage.args, DB, Apply,
		L["A locked window cannot be moved or resized; its title bar still switches modes."],
		function() S:ResetDamageWindowPosition() end)
end
