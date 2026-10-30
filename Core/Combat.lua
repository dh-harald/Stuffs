-- Combat log input through LibVanillaThreat-1.0: the library parses every
-- combat log line once (for its threat engine) and hands each recognized
-- line on through its CombatLine callback. Heal records already carry the
-- effective amount and the overheal.
--
-- Listeners receive (category, record, event); the record table is reused
-- for every line: read it inside the call, never keep a reference to it.
--
-- Debug output (/stuffs debug ...): "combat" prints every recognized line,
-- "all" also the unrecognized ones, "threat" every threat change with its
-- reason.

local S, L, P, G = unpack(Stuffs)
local Compat = Stuffs.Compat

S.combatListeners = {}
S.debug = { combat = false, all = false, threat = false }

-- Registers func(category, record, event) for every recognized line.
function S:AddCombatListener(func)
	table.insert(self.combatListeners, func)
end

function S:Threat()
	return LibStub("LibVanillaThreat-1.0")
end

function S:DebugLine(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Stuffs|r " .. text)
end

local function Optional(label, value)
	if value == nil then
		return ""
	elseif value == true then
		return " " .. label
	end
	return " " .. label .. " " .. value
end

function S:DebugCombatLine(category, rec)
	local text = category .. " " .. tostring(rec.source) .. " > " .. tostring(rec.target)
	if rec.spell then
		text = text .. " : " .. rec.spell
	end
	if rec.amount then
		text = text .. " " .. rec.amount
	end
	text = text .. Optional("school", rec.school)
	if rec.crit then
		text = text .. " crit"
	end
	if category == "heal" then
		text = text .. Optional("effective", rec.effective) .. Optional("overheal", rec.overheal)
	end
	text = text .. Optional("power", rec.power) .. Optional("stacks", rec.stacks)
		.. Optional("absorbed", rec.absorbed) .. Optional("blocked", rec.blocked)
		.. Optional("resisted", rec.resisted) .. Optional("vulnerable", rec.vulnerable)
		.. Optional("crushing", rec.crushing) .. Optional("glancing", rec.glancing)
	self:DebugLine(text .. " |cff888888[" .. rec.kind .. " " .. rec.rule .. "]|r")
end

local function Round(value)
	if not value then return "nil" end
	return string.format("%.1f", value)
end

function S:DebugThreatEvent(unitName, mobName, delta, value, reason)
	local sign = ""
	if delta and delta >= 0 then sign = "+" end
	self:DebugLine("|cffffd100threat|r " .. tostring(unitName) .. " > " .. tostring(mobName)
		.. " " .. sign .. Round(delta) .. " = " .. Round(value) .. " |cff888888(" .. tostring(reason) .. ")|r")
end

-- /stuffs debug [all | threat]: toggles one output.
function S:SetDebug(kind)
	local debug = self.debug
	if kind == "threat" then
		debug.threat = not debug.threat
		if debug.threat then
			self:Print(L["Debug: every threat change is printed."])
		else
			self:Print(L["Threat debug off."])
		end
		return
	end

	if kind == "all" then
		debug.all = not debug.all
		debug.combat = debug.all
	else
		debug.combat = not debug.combat
		debug.all = false
	end

	if debug.all then
		self:Print(L["Debug: recognized and unrecognized combat log lines are printed."])
	elseif debug.combat then
		self:Print(L["Debug: recognized combat log lines are printed."])
	else
		self:Print(L["Debug off."])
	end

	local missing = self:Threat().Parser.missing or {}
	if Compat.getn(missing) > 0 then
		self:Print(string.format(L["Templates missing on this client: %s"], table.concat(missing, ", ")))
	end
end

function S:InitializeCombat()
	local LVT = self:Threat()
	self.combatCallbacks = self.combatCallbacks or {}
	local target = self.combatCallbacks

	LVT.RegisterCallback(target, "CombatLine", function(_, category, rec, event)
		local listeners = S.combatListeners
		for i = 1, Compat.getn(listeners) do
			listeners[i](category, rec, event)
		end
		if S.debug.combat then
			S:DebugCombatLine(category, rec)
		end
	end)
	LVT.RegisterCallback(target, "UnparsedLine", function(_, event, text)
		if S.debug.all then
			S:DebugLine("|cff888888?? " .. string.sub(event, 10) .. ": " .. tostring(text) .. "|r")
		end
	end)
	LVT.RegisterCallback(target, "ThreatEvent", function(_, unitName, mobName, delta, value, reason)
		if S.debug.threat then
			S:DebugThreatEvent(unitName, mobName, delta, value, reason)
		end
	end)
end
