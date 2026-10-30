-- Shared media through LibSharedMedia-3.0: bar textures and sounds are
-- chosen by their LSM name, so media registered by other addons can be
-- picked too. Pattern of Vuh's Core/Media.lua.
--
-- "Stuffs Flat" (the default bar texture) is the plain white pixel the bars
-- are tinted from. The sounds are stock 1.12.1 files (paths as in the
-- client's MPQs; Unreal Azeroth matches paths case-sensitively, and plays
-- Sound\Interface\RaidWarning.wav and LevelUp.wav in this spelling).
-- Sounds always play on the "Master" channel: the 1.12.1 client then plays
-- them at a zero effects volume too, though neither client plays anything
-- while sound is disabled.

local S, L, P, G = unpack(Stuffs)

S.FLAT_TEXTURE_NAME = "Stuffs Flat"
S.DEFAULT_SOUND_NAME = "Raid Warning"

local SOUNDS = {
	{ "Raid Warning", [[Sound\Interface\RaidWarning.wav]] },
	{ "Ready Check", [[Sound\Interface\ReadyCheck.wav]] },
	{ "Level Up", [[Sound\Interface\LevelUp.wav]] },
	{ "Flag Taken", [[Sound\Spells\PVPFlagTaken.wav]] },
	{ "Alliance Bell", [[Sound\Doodad\BellTollAlliance.wav]] },
	{ "Horde Bell", [[Sound\Doodad\BellTollHorde.wav]] },
	{ "You Will Die!", [[Sound\Creature\CThun\CThunYouWillDIe.wav]] },
}

-- The texture path of a bar texture name. A name nothing registers (its
-- addon disabled since it was chosen) falls back to the flat texture.
function S:BarTexture(name)
	local LSM = LibStub("LibSharedMedia-3.0")
	return LSM:Fetch("statusbar", name or "", true) or S.WHITE_TEXTURE
end

-- Plays the LSM sound `name` on the Master channel; "None" and names
-- nothing registers play nothing.
function S:PlaySound(name)
	if not name or name == "None" or type(PlaySoundFile) ~= "function" then return end
	local path = LibStub("LibSharedMedia-3.0"):Fetch("sound", name, true)
	if path then
		pcall(PlaySoundFile, path, "Master")
	end
end

-- Media registered after the windows took the fallback (an addon loading
-- later) is applied as soon as it appears.
local function OnMediaRegistered(event, mediatype, key)
	if mediatype ~= "statusbar" then return end
	if S.damageWindow and key == S.db.profile.damage.texture then
		S.damageWindow:ApplyStyle()
	end
	if S.threatWindow and key == S.db.profile.threat.texture then
		S.threatWindow:ApplyStyle()
	end
end

function S:InitializeMedia()
	local LSM = LibStub("LibSharedMedia-3.0")
	LSM:Register("statusbar", S.FLAT_TEXTURE_NAME, S.WHITE_TEXTURE)
	for i = 1, Stuffs.Compat.getn(SOUNDS) do
		LSM:Register("sound", SOUNDS[i][1], SOUNDS[i][2])
	end
	if not self.mediaCallbacks then
		self.mediaCallbacks = {}
		LSM.RegisterCallback(self.mediaCallbacks, "LibSharedMedia_Registered", OnMediaRegistered)
	end
end
