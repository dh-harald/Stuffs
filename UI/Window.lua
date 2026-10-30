-- Meter window: a title bar over a column of bars, in ThreatClassic2's plain
-- look (translucent black body, darker title bar, 1px black border, flat
-- bars in class colours).
--
-- The window is movable by its title bar and resizable by its bottom-right
-- grip while unlocked; locking hides the grip and turns the title bar into a
-- click target only. The number of bars follows the height.
--
-- Moving: StartMoving/StopMovingOrSizing driven from OnMouseDown/OnMouseUp,
-- with a throwaway StartMoving/StopMovingOrSizing pair first (Vuh's mover).
-- RegisterForDrag is not used: on Unreal Azeroth a registered frame stays
-- stuck to the cursor until the next click. A press that did not move the
-- window counts as a click on the title bar.
--
-- Resizing: the grip reads the cursor every frame while pressed and sets the
-- size itself; StartSizing is not used. The window is anchored by its top
-- left corner during the resize, so it grows to the right and downwards.
-- Detecting the release follows LibConfig-1.0's slider thumbs: on Unreal
-- Azeroth a frame's OnMouseUp only arrives while the cursor is over it and
-- IsMouseButtonDown does not exist, so while resizing the grip's hit
-- rectangle is expanded over the whole screen, GetButtonState() == "PUSHED"
-- is a second opinion once it has been seen, and a dead-man timer ends a
-- resize that never saw its release. On the 1.12.1 client the expanded hit
-- rectangle breaks mouse focus afterwards, so there the client's own
-- OnDragStart/OnDragStop drive the resize.
--
-- Position, size and style live in the window's profile table:
--   { point, x, y, width, height, locked, shown,
--     barHeight, barSpacing, texture, bodyAlpha }
-- point is the screen point nearest to the window, x/y the window's top
-- left corner relative to it; texture is a LibSharedMedia statusbar name.

local S, L, P, G = unpack(Stuffs)
local Compat = Stuffs.Compat

local TITLE_HEIGHT = 18
local TEXT_MARGIN = 4
local VALUE_WIDTH = 90
local GRIP_SIZE = 10
local MIN_WIDTH, MIN_HEIGHT = 120, TITLE_HEIGHT + 20
local MAX_WIDTH, MAX_HEIGHT = 800, 800
local CLICK_TOLERANCE = 2
local CAPTURE_INSET = -4000
local RESIZE_MAX_SECONDS = 60

local BODY_COLOR = { 0, 0, 0, 1 }
local TITLE_COLOR = { 0, 0, 0, 0.8 }
local BORDER_COLOR = { 0, 0, 0, 1 }
local GRIP_COLOR = { 1, 1, 1, 0.5 }
local TEXT_COLOR = { 1, 1, 1 }
local HIGHLIGHT_COLOR = { 1, 0.82, 0 }

local Window = {}

local function NewTexture(parent, layer, color)
	local texture = parent:CreateTexture(nil, layer)
	texture:SetTexture(S.WHITE_TEXTURE)
	texture:SetVertexColor(color[1], color[2], color[3], color[4])
	return texture
end

local function NewText(parent, justify)
	local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetJustifyH(justify)
	return text
end

-- A 1px border from four textures; a backdrop is not used, because a
-- backdrop fill renders differently on Unreal Azeroth.
local function AddBorder(frame)
	local top = NewTexture(frame, "BORDER", BORDER_COLOR)
	top:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
	top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
	top:SetHeight(1)

	local bottom = NewTexture(frame, "BORDER", BORDER_COLOR)
	bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -1, -1)
	bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
	bottom:SetHeight(1)

	local left = NewTexture(frame, "BORDER", BORDER_COLOR)
	left:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
	left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -1, -1)
	left:SetWidth(1)

	local right = NewTexture(frame, "BORDER", BORDER_COLOR)
	right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
	right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
	right:SetWidth(1)
end

-- Position

function Window.ApplyPosition(window)
	local db = window.db
	local frame = window.frame
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, db.point, db.x, db.y)
	frame:SetWidth(db.width)
	frame:SetHeight(db.height)
end

function Window.SavePosition(window)
	local frame = window.frame
	local point, px, py = S:NearestScreenPoint(frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not (point and left and top) then return end

	local db = window.db
	db.point = point
	db.x = S.Round(left - px)
	db.y = S.Round(top - py)
	db.width = S.Round(frame:GetWidth())
	db.height = S.Round(frame:GetHeight())
	Window.ApplyPosition(window)
end

-- Pins the top left corner in UIParent coordinates, so a size change keeps
-- the corner in place whatever the saved anchor point is.
local function PinTopLeft(frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not (left and top) then return end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- Moving

local function StartMove(window)
	local frame = window.frame
	window.pressLeft, window.pressTop = frame:GetLeft(), frame:GetTop()
	if window.db.locked then return end

	frame:SetMovable(true)
	if pcall(frame.StartMoving, frame) then
		pcall(frame.StopMovingOrSizing, frame)
	end
	frame:StartMoving()
	window.moving = true
end

-- Returns true when the press moved the window.
local function StopMove(window)
	local frame = window.frame
	if window.moving then
		window.moving = nil
		frame:StopMovingOrSizing()
		-- The 1.12.1 client would also store and restore a user-placed
		-- frame itself, fighting the saved position.
		pcall(frame.SetUserPlaced, frame, false)
	end

	local left, top = frame:GetLeft(), frame:GetTop()
	local moved = window.pressLeft and left and top
		and (math.abs(left - window.pressLeft) > CLICK_TOLERANCE
			or math.abs(top - window.pressTop) > CLICK_TOLERANCE)
	window.pressLeft, window.pressTop = nil, nil

	if moved then
		Window.SavePosition(window)
		return true
	end
	return false
end

-- Resizing

local function ApplyCursorSize(window)
	local sizing = window.sizing
	local frame = window.frame
	local cx, cy = S.CursorPoint(frame)
	if not cx then return end

	local width = sizing.width + cx - sizing.x
	local height = sizing.height + sizing.y - cy
	if width < MIN_WIDTH then width = MIN_WIDTH end
	if width > MAX_WIDTH then width = MAX_WIDTH end
	if height < MIN_HEIGHT then height = MIN_HEIGHT end
	if height > MAX_HEIGHT then height = MAX_HEIGHT end

	if width ~= sizing.lastWidth or height ~= sizing.lastHeight then
		sizing.lastWidth, sizing.lastHeight = width, height
		frame:SetWidth(width)
		frame:SetHeight(height)
		Window.Layout(window)
	end
end

-- true / false / nil, where nil means the client would not tell.
local function GripStillHeld(grip)
	if not grip.GetButtonState then return nil end
	local ok, state = pcall(grip.GetButtonState, grip)
	if not ok or type(state) ~= "string" then return nil end
	return state == "PUSHED"
end

local function StopResize(window)
	local sizing = window.sizing
	if not sizing then return end
	window.sizing = nil

	local grip = window.grip
	if Compat.isUA then
		pcall(grip.SetHitRectInsets, grip, 0, 0, 0, 0)
		pcall(grip.SetFrameLevel, grip, sizing.gripLevel)
	end

	Window.SavePosition(window)
	Window.Layout(window)
end

local function ResizeUpdate(window)
	local sizing = window.sizing
	if not sizing then return end

	ApplyCursorSize(window)

	if Compat.isUA then
		local held = GripStillHeld(window.grip)
		if held == true then
			sizing.armed = true
		elseif held == false and sizing.armed then
			StopResize(window)
			return
		end
	end

	if GetTime() - sizing.startedAt > RESIZE_MAX_SECONDS then
		StopResize(window)
	end
end

local function StartResize(window)
	if window.db.locked or window.sizing then return end
	local frame = window.frame
	local cx, cy = S.CursorPoint(frame)
	if not cx then return end

	PinTopLeft(frame)
	local grip = window.grip
	window.sizing = {
		x = cx, y = cy,
		width = frame:GetWidth(), height = frame:GetHeight(),
		startedAt = GetTime(),
		gripLevel = grip:GetFrameLevel(),
	}

	if Compat.isUA then
		pcall(grip.SetHitRectInsets, grip, CAPTURE_INSET, CAPTURE_INSET, CAPTURE_INSET, CAPTURE_INSET)
		pcall(grip.SetFrameLevel, grip, window.sizing.gripLevel + 50)
	end
end

-- Bars

-- Hovering a bar calls window.onEnterBar(bar, row) and again on every
-- redraw while the cursor stays on it, so a tooltip follows live values.
local function CreateBar(window)
	local bar = S:CreateStatusBar(window.frame)
	bar:SetBackgroundColor(0, 0, 0, 0)

	bar:EnableMouse(true)
	bar:SetScript("OnEnter", function()
		window.hoverBar = bar
		if window.onEnterBar and bar.row then
			window.onEnterBar(bar, bar.row)
		end
	end)
	bar:SetScript("OnLeave", function()
		if window.hoverBar == bar then
			window.hoverBar = nil
		end
		GameTooltip:Hide()
	end)

	bar.leftText = NewText(bar, "LEFT")
	bar.leftText:SetPoint("LEFT", bar, "LEFT", TEXT_MARGIN, 0)

	bar.rightText = NewText(bar, "RIGHT")
	bar.rightText:SetPoint("RIGHT", bar, "RIGHT", -TEXT_MARGIN, 0)
	bar.rightText:SetWidth(VALUE_WIDTH)

	bar:Hide()
	return bar
end

-- How many bars fit under the title bar.
function Window.BarCount(window)
	local db = window.db
	local height = window.frame:GetHeight() or 0
	local count = math.floor((height - TITLE_HEIGHT - 1 + db.barSpacing) / (db.barHeight + db.barSpacing))
	if count < 0 then count = 0 end
	return count
end

-- Positions the bars for the current size and style, and redraws the rows.
function Window.Layout(window)
	local db = window.db
	local frame = window.frame
	local width = frame:GetWidth() or 0
	local count = Window.BarCount(window)
	local bars = window.bars
	local texture = S:BarTexture(db.texture)

	for i = Compat.getn(bars) + 1, count do
		bars[i] = CreateBar(window)
	end

	local textWidth = width - VALUE_WIDTH - TEXT_MARGIN * 3
	if textWidth < 10 then textWidth = 10 end

	for i = 1, Compat.getn(bars) do
		local bar = bars[i]
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(TITLE_HEIGHT + 1 + (i - 1) * (db.barHeight + db.barSpacing)))
		bar:SetWidth(width - 2)
		bar:SetHeight(db.barHeight)
		bar:SetBarTexture(texture)
		bar.leftText:SetWidth(textWidth)
		bar:UpdateFill()
	end

	window.body:SetVertexColor(BODY_COLOR[1], BODY_COLOR[2], BODY_COLOR[3], db.bodyAlpha)

	window.title:SetWidth(width - VALUE_WIDTH - TEXT_MARGIN * 3)
	Window.Render(window)
end

-- rows: array of { label, value, max, text, r, g, b }, already sorted. A row
-- may add split = { value, r, g, b }: a part of the bar from the left drawn
-- in its own colour over the main fill; and highlight = true: both texts in
-- gold instead of white.
function Window.SetRows(window, rows)
	window.rows = rows
	Window.Render(window)
end

function Window.Render(window)
	local rows = window.rows or {}
	local bars = window.bars
	local count = Window.BarCount(window)

	for i = 1, Compat.getn(bars) do
		local bar = bars[i]
		local row = rows[i]
		if row and i <= count then
			bar:SetMinMaxValues(0, row.max)
			bar:SetValue(row.value)
			bar:SetColor(row.r, row.g, row.b, 1)
			local split = row.split
			if split then
				bar:SetSplit(split.value, split.r, split.g, split.b, 1)
			else
				bar:SetSplit(nil)
			end
			bar.leftText:SetText(row.label)
			bar.rightText:SetText(row.text)
			local text = TEXT_COLOR
			if row.highlight then text = HIGHLIGHT_COLOR end
			bar.leftText:SetTextColor(text[1], text[2], text[3])
			bar.rightText:SetTextColor(text[1], text[2], text[3])
			bar.row = row
			bar:Show()
			if window.hoverBar == bar and window.onEnterBar then
				window.onEnterBar(bar, row)
			end
		else
			bar.row = nil
			if window.hoverBar == bar then
				window.hoverBar = nil
				GameTooltip:Hide()
			end
			bar:Hide()
		end
	end
end

function Window.SetTitle(window, left, right)
	window.title:SetText(left or "")
	window.info:SetText(right or "")
end

-- Re-applies everything stored in the profile: position, size, style,
-- lock and visibility (after an options change or a profile switch).
function Window.ApplyStyle(window)
	Window.ApplyPosition(window)
	Window.Layout(window)
end

function Window.ApplyLock(window)
	if window.db.locked then
		window.grip:Hide()
	else
		window.grip:Show()
	end
end

function Window.ApplyShown(window)
	if window.db.shown then
		window.frame:Show()
	else
		window.frame:Hide()
	end
end

-- Creates a window. db is its profile table, onClick(button) runs for a
-- click on the title bar that did not move the window, onEnterBar(bar, row)
-- when a bar is hovered (see CreateBar).
function S:CreateMeterWindow(db, onClick, onEnterBar)
	local window = { db = db, bars = {}, rows = {}, onClick = onClick, onEnterBar = onEnterBar }

	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("MEDIUM")
	window.frame = frame

	local body = NewTexture(frame, "BACKGROUND", BODY_COLOR)
	body:SetAllPoints(frame)
	window.body = body
	AddBorder(frame)

	local titleBar = CreateFrame("Button", nil, frame)
	titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	titleBar:SetHeight(TITLE_HEIGHT)
	titleBar:EnableMouse(true)
	window.titleBar = titleBar

	local titleBg = NewTexture(titleBar, "BACKGROUND", TITLE_COLOR)
	titleBg:SetAllPoints(titleBar)

	window.title = NewText(titleBar, "LEFT")
	window.title:SetPoint("LEFT", titleBar, "LEFT", TEXT_MARGIN, 0)
	window.info = NewText(titleBar, "RIGHT")
	window.info:SetPoint("RIGHT", titleBar, "RIGHT", -TEXT_MARGIN, 0)
	window.info:SetWidth(VALUE_WIDTH)

	titleBar:SetScript("OnMouseDown", function(a, b)
		if S.HandlerButton(a, b) == "LeftButton" then
			StartMove(window)
		end
	end)
	titleBar:SetScript("OnMouseUp", function(a, b)
		local button = S.HandlerButton(a, b)
		if button == "LeftButton" then
			if StopMove(window) then return end
		end
		if window.onClick then
			window.onClick(button)
		end
	end)

	local grip = CreateFrame("Button", nil, frame)
	grip:SetWidth(GRIP_SIZE)
	grip:SetHeight(GRIP_SIZE)
	grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	grip:SetFrameLevel(frame:GetFrameLevel() + 5)
	grip:EnableMouse(true)
	local gripTexture = NewTexture(grip, "OVERLAY", GRIP_COLOR)
	gripTexture:SetAllPoints(grip)
	window.grip = grip

	if Compat.isUA then
		grip:SetScript("OnMouseDown", function(a, b)
			if S.HandlerButton(a, b) == "LeftButton" then
				StartResize(window)
			end
		end)
	else
		pcall(grip.RegisterForDrag, grip, "LeftButton")
		grip:SetScript("OnDragStart", function() StartResize(window) end)
		grip:SetScript("OnDragStop", function() StopResize(window) end)
	end
	-- Idempotent second chances: a release over the grip, and a grip hidden
	-- mid-resize (lock, window closed) must not leave a screen-wide hit
	-- rectangle behind.
	grip:SetScript("OnMouseUp", function() StopResize(window) end)
	grip:SetScript("OnHide", function() StopResize(window) end)
	grip:SetScript("OnUpdate", function() ResizeUpdate(window) end)

	Window.ApplyPosition(window)
	Window.ApplyLock(window)
	Window.ApplyShown(window)
	Window.Layout(window)

	window.SetRows = Window.SetRows
	window.SetTitle = Window.SetTitle
	window.ApplyStyle = Window.ApplyStyle
	window.ApplyLock = Window.ApplyLock
	window.ApplyShown = Window.ApplyShown
	window.BarCount = Window.BarCount
	return window
end
