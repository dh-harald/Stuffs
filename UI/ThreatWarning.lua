-- Aggro warning, after ThreatClassic2's: when the player's threat on the
-- threat window's mob reaches warnThreshold of the threat that pulls aggro
-- (more than 110% of the tank's threat in melee range, 130% outside it --
-- LibVanillaThreat-1.0's UnitDetailedThreatSituation), a message in the
-- middle of the screen and a sound.
--
-- It fires once on crossing the threshold upwards, and again only after the
-- share fell below it, the mob changed or the fight ended; never while the
-- player is the tank, and not below warnMinThreat. Checked four times a
-- second in combat, whether the window is shown or not.
--
-- The message goes to RaidWarningFrame (1.12.1 FrameXML), or UIErrorsFrame
-- on a client without one; the sound is the LSM sound warnSoundName, on the
-- Master channel (S:PlaySound), "None" for silence.

local S, L, P, G = unpack(Stuffs)

P.threat.warnText = true
P.threat.warnSoundName = S.DEFAULT_SOUND_NAME
P.threat.warnThreshold = 0.8
P.threat.warnMinThreat = 0

local CHECK_INTERVAL = 0.25
local WARNING_COLOR = { 1, 0.1, 0.1 }

local lastMob
local lastPercent = 0

function S:ShowThreatWarning(percent, mob)
	local db = self.db.profile.threat
	if db.warnText then
		local text = string.format(L["Aggro warning: %.0f%% on %s"], percent, mob)
		local frame = RaidWarningFrame or UIErrorsFrame
		if frame and frame.AddMessage then
			frame:AddMessage(text, WARNING_COLOR[1], WARNING_COLOR[2], WARNING_COLOR[3])
		else
			self:Print(text)
		end
	end
	self:PlaySound(db.warnSoundName)
end

function S:CheckThreatWarning()
	local db = self.db.profile.threat
	if not db.warnText and db.warnSoundName == "None" then return end

	local mob, mobUnit = self:ThreatMob()
	if not mob then return end
	if mob ~= lastMob then
		lastMob = mob
		lastPercent = 0
	end

	local isTanking, _, percent, _, value = self:Threat():UnitDetailedThreatSituation("player", mobUnit)
	percent = percent or 0
	local threshold = db.warnThreshold * 100
	if percent < threshold then
		lastPercent = percent
	elseif lastPercent < threshold and (isTanking or value >= db.warnMinThreat) then
		-- Taking the mob over counts as the crossing, without a warning.
		lastPercent = percent
		if not isTanking then
			self:ShowThreatWarning(percent, mob)
		end
	end
end

function S:InitializeThreatWarning()
	self:AddTicker(CHECK_INTERVAL, function()
		if S.InCombat("player") then
			S:CheckThreatWarning()
		else
			lastMob = nil
			lastPercent = 0
		end
	end)
end
