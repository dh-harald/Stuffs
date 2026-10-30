-- Shared helpers: ticker, class colours, number formatting, status bar,
-- screen position and cursor helpers.

local S, L, P, G = unpack(Stuffs)
local Compat = Stuffs.Compat

local WHITE = "Interface\\Buttons\\WHITE8x8"

S.WHITE_TEXTURE = WHITE

function S.Round(value)
	return math.floor(value + 0.5)
end

function S.InCombat(unit)
	return Compat.bool(UnitAffectingCombat(unit or "player"))
end

-- Ticker: one OnUpdate frame drives every periodic job. The elapsed time is
-- measured with GetTime, because Unreal Azeroth does not reliably pass it
-- to the handler.

local tickers = {}
local tickFrame = CreateFrame("Frame")
S.tickFrame = tickFrame

tickFrame:SetScript("OnUpdate", function()
	local now = GetTime()
	for i = 1, Compat.getn(tickers) do
		local ticker = tickers[i]
		if now - ticker.last >= ticker.interval then
			ticker.last = now
			ticker.func(now)
		end
	end
end)

function S:AddTicker(interval, func)
	table.insert(tickers, { interval = interval, last = 0, func = func })
end

-- A private copy of RAID_CLASS_COLORS, so other addons' colours are left
-- alone. The 1.12.1 shaman colour is the paladin's pink; the corrected blue
-- is the one later clients use.
S.classColors = {}
if type(RAID_CLASS_COLORS) == "table" then
	local class, color
	for class, color in pairs(RAID_CLASS_COLORS) do
		S.classColors[class] = { r = color.r, g = color.g, b = color.b }
	end
end
S.classColors.SHAMAN = { r = 0.00, g = 0.44, b = 0.87 }

local UNKNOWN_COLOR = { r = 0.6, g = 0.6, b = 0.6 }

function S:ClassColor(class)
	return self.classColors[class or ""] or UNKNOWN_COLOR
end

-- 1234 -> "1234", 12345 -> "12.3k", 1234567 -> "1.23M".
function S.FormatNumber(value)
	if value >= 1000000 then
		return string.format("%.2fM", value / 1000000)
	elseif value >= 10000 then
		return string.format("%.1fk", value / 1000)
	end
	return string.format("%d", value)
end

-- 75 -> "1:15".
function S.FormatDuration(seconds)
	seconds = math.floor(seconds)
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%02d", minutes, seconds - minutes * 60)
end

-- Status bar: a plain Frame with a background and a fill texture whose
-- anchors are computed from the value. The native StatusBar is not used:
-- on Unreal Azeroth its fill texture does not follow SetValue and stays a
-- fixed-size block. Ported from Vuh. The fill depends on the bar's width,
-- so UpdateFill must run again after a resize.
--
-- An optional split fill is drawn over the main fill from the left, up to
-- its own value, in its own colour: a bar showing a total with a part of it
-- highlighted (effective healing within total healing).

local function PlaceFill(bar, texture, value)
	local size = tonumber(bar:GetWidth()) or 0

	local range = bar.maxValue - bar.minValue
	local extent = 0
	if range > 0 and size > 0 then
		extent = size / range * (value - bar.minValue)
	end
	if extent < 0 then extent = 0 end
	if extent > size then extent = size end

	if extent <= 0 then
		texture:Hide()
		return
	end

	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	texture:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -(size - extent), 0)
	texture:Show()
end

local function UpdateFill(bar)
	PlaceFill(bar, bar.fill, bar.value)
	if bar.splitValue then
		PlaceFill(bar, bar.split, bar.splitValue)
	else
		bar.split:Hide()
	end
end

local function BarSetMinMaxValues(bar, minValue, maxValue)
	minValue = tonumber(minValue) or 0
	maxValue = tonumber(maxValue) or 0
	if bar.minValue == minValue and bar.maxValue == maxValue then return end
	bar.minValue, bar.maxValue = minValue, maxValue
	UpdateFill(bar)
end

local function BarSetValue(bar, value)
	value = tonumber(value) or 0
	if bar.value == value then return end
	bar.value = value
	UpdateFill(bar)
end

-- SetVertexColor has no getter on Unreal Azeroth, so the last colour is
-- cached and an unchanged colour is not re-applied.
local function BarSetColor(bar, r, g, b, a)
	a = a or 1
	local c = bar.color
	if c[1] == r and c[2] == g and c[3] == b and c[4] == a then return end
	c[1], c[2], c[3], c[4] = r, g, b, a
	bar.fill:SetVertexColor(r, g, b, a)
end

-- value nil removes the split fill.
local function BarSetSplit(bar, value, r, g, b, a)
	a = a or 1
	if value then
		local c = bar.splitColor
		if c[1] ~= r or c[2] ~= g or c[3] ~= b or c[4] ~= a then
			c[1], c[2], c[3], c[4] = r, g, b, a
			bar.split:SetVertexColor(r, g, b, a)
		end
	end
	if bar.splitValue == value then return end
	bar.splitValue = value
	UpdateFill(bar)
end

-- The fills share the texture. The colours are applied again after the swap,
-- so a client that resets the vertex colour on SetTexture keeps the tint.
local function BarSetTexture(bar, path)
	if bar.texture == path then return end
	bar.texture = path
	bar.fill:SetTexture(path)
	bar.split:SetTexture(path)
	local c = bar.color
	if c[1] then bar.fill:SetVertexColor(c[1], c[2], c[3], c[4]) end
	c = bar.splitColor
	if c[1] then bar.split:SetVertexColor(c[1], c[2], c[3], c[4]) end
end

local function BarSetBackgroundColor(bar, r, g, b, a)
	a = a or 1
	local c = bar.bgColor
	if c[1] == r and c[2] == g and c[3] == b and c[4] == a then return end
	c[1], c[2], c[3], c[4] = r, g, b, a
	bar.bg:SetVertexColor(c[1], c[2], c[3], c[4])
end

function S:CreateStatusBar(parent)
	local bar = CreateFrame("Frame", nil, parent)

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(WHITE)
	bg:SetAllPoints(bar)
	bar.bg = bg
	bar.bgColor = {}
	BarSetBackgroundColor(bar, 0, 0, 0, 0)

	-- Layers: background, main fill (BORDER), split fill (ARTWORK); texts
	-- stay free to use OVERLAY above all of them.
	local fill = bar:CreateTexture(nil, "BORDER")
	fill:SetTexture(WHITE)
	bar.fill = fill
	bar.texture = WHITE

	local split = bar:CreateTexture(nil, "ARTWORK")
	split:SetTexture(WHITE)
	split:Hide()
	bar.split = split
	bar.splitColor = {}

	bar.minValue, bar.maxValue, bar.value = 0, 1, 1
	bar.color = {}

	bar.SetMinMaxValues = BarSetMinMaxValues
	bar.SetValue = BarSetValue
	bar.SetSplit = BarSetSplit
	bar.SetBarTexture = BarSetTexture
	bar.SetColor = BarSetColor
	bar.SetBackgroundColor = BarSetBackgroundColor
	bar.UpdateFill = UpdateFill

	UpdateFill(bar)
	return bar
end

-- The screen point a frame is closest to: the screen is split into thirds
-- horizontally and halves vertically, as in ElvUI's CalculateMoverPoints.
-- Returns the point name and its position in UIParent coordinates. A small
-- offset from the nearest edge survives a resolution change better than a
-- large offset from the centre. Ported from Vuh.
function S:NearestScreenPoint(frame)
	local cx, cy = frame:GetCenter()
	local screenWidth, screenHeight = UIParent:GetRight(), UIParent:GetTop()
	if not (cx and cy and screenWidth and screenHeight) then return end

	local point, px, py
	if cy >= screenHeight / 2 then
		point, py = "TOP", screenHeight
	else
		point, py = "BOTTOM", 0
	end

	if cx >= screenWidth * 2 / 3 then
		point, px = point .. "RIGHT", screenWidth
	elseif cx <= screenWidth / 3 then
		point, px = point .. "LEFT", 0
	else
		px = screenWidth / 2
	end

	return point, px, py
end

-- The cursor in the frame's own coordinate space, or nil. Same recipe as
-- LibConfig-1.0's slider thumbs, which work on both clients.
function S.CursorPoint(frame)
	if type(GetCursorPosition) ~= "function" then return nil end
	local ok, cx, cy = pcall(GetCursorPosition)
	if not ok or not tonumber(cx) or not tonumber(cy) then return nil end
	local scaleOk, scale = pcall(frame.GetEffectiveScale, frame)
	if not scaleOk or not tonumber(scale) or scale <= 0 then return nil end
	return cx / scale, cy / scale
end

-- The mouse button of a script handler: Unreal Azeroth may pass it as an
-- argument, the 1.12.1 client only sets the global arg1.
function S.HandlerButton(a, b)
	if type(a) == "string" then return a end
	if type(b) == "string" then return b end
	return arg1
end
