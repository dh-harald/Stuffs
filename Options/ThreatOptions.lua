-- Options tab "Threat window": visibility, lock and position, the bars'
-- look (the shared window sections, Options.lua) and the aggro warning.
-- Every setter writes the profile and re-applies the window
-- (S:ApplyThreatWindowSettings), so a change shows at once.

local S, L, P, G = unpack(Stuffs)

local function DB()
	return S.db.profile.threat
end

local function Apply()
	S:ApplyThreatWindowSettings()
end

local function Toggle(key, order, name, desc)
	return S.OptionToggle(DB, Apply, key, order, name, desc)
end

local function Range(key, order, name, min, max, step, desc, isPercent)
	return S.OptionRange(DB, Apply, key, order, name, min, max, step, desc, isPercent)
end

function S:BuildThreatOptions()
	local args = {
		warningHeader = { type = "header", order = 20, name = L["Aggro warning"] },
		warnText = Toggle("warnText", 21, L["Show a warning message"],
			L["A raid warning style message in the middle of the screen."]),
		warnSoundName = {
			type = "select",
			dialogControl = "LSM30_Sound",
			order = 22,
			name = L["Warning sound"],
			desc = L["Played on the Master channel. None plays no sound; sounds other addons register with LibSharedMedia are listed too."],
			values = S.SoundValues,
			get = function() return DB().warnSoundName end,
			set = function(_, value)
				DB().warnSoundName = value
				S:PlaySound(value)
			end,
		},
		warnThreshold = Range("warnThreshold", 23, L["Warn at"], 0.5, 1, 0.01,
			L["Share of the threat that pulls aggro from the tank: more than 110% of the tank's threat in melee range, 130% farther away."],
			true),
		warnMinThreat = Range("warnMinThreat", 24, L["Minimum threat"], 0, 10000, 50,
			L["No warning below this much threat."]),
		testWarning = {
			type = "execute",
			order = 25,
			name = L["Test warning"],
			func = function()
				S:ShowThreatWarning(DB().warnThreshold * 100, L["Test"])
			end,
		},
	}
	S.AddWindowOptions(args, DB, Apply, L["A locked window cannot be moved or resized."],
		function() S:ResetThreatWindowPosition() end)

	self.options.args.threat = {
		type = "group",
		order = 2,
		name = L["Threat window"],
		args = args,
	}
end
