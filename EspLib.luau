local Player = game:GetService("Players").LocalPlayer
local Camera = workspace.CurrentCamera
local RunService = game:GetService("RunService")
if not Drawing then
	return
end
local Drawing = Drawing
local EspLib = {
	Objects = {},
}

-- ===== 全局偏移校正（根据执行器/游戏实测微调）=====
local OFFSET_X = 0
local OFFSET_Y = 0

-- ===== 局部化高频全局 =====
local V2 = Vector2.new
local C3 = Color3.fromRGB
local MathMin = math.min
local MathMax = math.max
local MathFloor = math.floor
local MathClamp = math.clamp
local MathHuge = math.huge
local MathSqrt = math.sqrt
local U8Codes = utf8.codes

-- ===== 工具函数 =====

local function GetVal(val, ...)
	if typeof(val) == "function" then
		return val(...)
	end
	return val
end

-- 计算模型/部件在屏幕上的包围盒（像素），复用缓存表
local function GetOnScreenBounds(model, cache)
	local cf, size
	if model:IsA("Model") then
		cf, size = model:GetPivot(), model:GetExtentsSize()
	elseif model:IsA("BasePart") then
		cf, size = model.CFrame, model.Size
	else
		return nil
	end

	local corners = cache.corners
	if not corners then
		corners = {}
		cache.corners = corners
	end

	local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
	corners[1] = cf * CFrame.new(-hx, -hy, -hz)
	corners[2] = cf * CFrame.new( hx, -hy, -hz)
	corners[3] = cf * CFrame.new(-hx,  hy, -hz)
	corners[4] = cf * CFrame.new( hx,  hy, -hz)
	corners[5] = cf * CFrame.new(-hx, -hy,  hz)
	corners[6] = cf * CFrame.new( hx, -hy,  hz)
	corners[7] = cf * CFrame.new(-hx,  hy,  hz)
	corners[8] = cf * CFrame.new( hx,  hy,  hz)

	local minX, minY = MathHuge, MathHuge
	local maxX, maxY = -MathHuge, -MathHuge

	for i = 1, 8 do
		local sp = Camera:WorldToScreenPoint(corners[i].Position)
		if sp.Z <= 0 then
			continue
		end
		local sx, sy = sp.X, sp.Y
		if sx < minX then minX = sx end
		if sy < minY then minY = sy end
		if sx > maxX then maxX = sx end
		if sy > maxY then maxY = sy end
	end

	if minX == MathHuge then
		return nil
	end

	cache.bx = minX
	cache.by = minY
	cache.bw = maxX - minX
	cache.bh = maxY - minY
	return cache
end

-- 精确文字尺寸（带缓存，只在文字变化时重算）
local function measureText(drawing, text, cache)
	if cache.lastText == text then
		return cache.size
	end
	drawing.Text = text
	local ok, bounds = pcall(function() return drawing:GetTextBounds() end)
	local size
	if ok and typeof(bounds) == "Vector2" and bounds.X > 0 then
		size = bounds
	else
		local w = 0
		for _, code in U8Codes(text) do
			w = w + (code > 127 and drawing.Size or drawing.Size * 0.55)
		end
		size = V2(w, drawing.Size)
	end
	cache.lastText = text
	cache.size = size
	return size
end

-- 精确居中放置文字
local function placeTextCentered(drawing, text, centerX, topY, cache)
	local size = measureText(drawing, text, cache)
	drawing.Center = false
	drawing.Position = V2(centerX - size.X * 0.5, topY)
	return size
end

-- ===== Drawing 创建 =====

local function CreateDrawings()
	local d = {}

	d.BoxShadow = Drawing.new("Square")
	d.BoxShadow.Filled = false
	d.BoxShadow.Thickness = 2
	d.BoxShadow.Color = C3(0, 0, 0)
	d.BoxShadow.Transparency = 0.8

	d.Box = Drawing.new("Square")
	d.Box.Filled = false
	d.Box.Thickness = 1
	d.Box.Color = C3(255, 255, 255)
	d.Box.Transparency = 1

	d.NameBg = Drawing.new("Square")
	d.NameBg.Filled = true
	d.NameBg.Color = C3(20, 20, 25)
	d.NameBg.Transparency = 0.35

	d.Name = Drawing.new("Text")
	d.Name.Center = false
	d.Name.Outline = true
	d.Name.OutlineColor = C3(0, 0, 0)
	d.Name.Color = C3(255, 255, 255)
	d.Name.Size = 14
	d.Name.Font = Drawing.Fonts.System
	d.Name.Transparency = 1

	d.HealthBarBg = Drawing.new("Square")
	d.HealthBarBg.Filled = true
	d.HealthBarBg.Color = C3(30, 30, 35)
	d.HealthBarBg.Transparency = 0.6

	d.HealthBar = Drawing.new("Square")
	d.HealthBar.Filled = true
	d.HealthBar.Color = C3(80, 220, 120)
	d.HealthBar.Transparency = 0.95

	d.HealthText = Drawing.new("Text")
	d.HealthText.Center = false
	d.HealthText.Outline = true
	d.HealthText.OutlineColor = C3(0, 0, 0)
	d.HealthText.Color = C3(255, 255, 255)
	d.HealthText.Size = 12
	d.HealthText.Font = Drawing.Fonts.System
	d.HealthText.Transparency = 1

	d.Distance = Drawing.new("Text")
	d.Distance.Center = false
	d.Distance.Outline = true
	d.Distance.OutlineColor = C3(0, 0, 0)
	d.Distance.Color = C3(200, 200, 200)
	d.Distance.Size = 12
	d.Distance.Font = Drawing.Fonts.System
	d.Distance.Transparency = 1

	return d
end

local function DestroyDrawings(d)
	for _, obj in pairs(d) do
		if obj and obj.Destroy then
			obj:Destroy()
		end
	end
end

-- ===== 可见性批量切换 =====

local function SetVisible(tbl, visible)
	if tbl.visibleState == visible then return end
	tbl.visibleState = visible
	local d = tbl.Drawings
	local infoDrawings = tbl.infoDrawings
	local showBox = tbl.showBox

	d.Box.Visible = visible and showBox
	d.BoxShadow.Visible = visible and showBox
	d.NameBg.Visible = visible
	d.Name.Visible = visible

	local hasHp = tbl.humanoid ~= nil
	if hasHp then
		d.HealthBarBg.Visible = visible
		d.HealthBar.Visible = visible
		d.HealthText.Visible = visible
	end
	d.Distance.Visible = visible

	for i = 1, #infoDrawings do
		infoDrawings[i].Drawing.Visible = visible
	end
end

-- ===== 核心 API =====

function EspLib:WrapObject(Args)
	if not Args or not Args.Object then return end
	if EspLib.Objects[Args.Object] then return end

	Args.Configs = Args.Configs or {}

	local color = Args.Color
	if color then
		if typeof(color) == "table" then
			color = {
				Text = color.Text or C3(255, 255, 255),
				Box = color.Box or C3(255, 255, 255),
			}
		else
			color = { Text = color, Box = color }
		end
	else
		color = {
			Text = C3(255, 255, 255),
			Box = C3(255, 255, 255),
		}
	end

	local Object = Args.Object
	local RenderDistance = Args.RenderDistance or MathHuge
	local ShowHealthBar = Args.Configs.HealthBar ~= false
	local ShowBox = Args.Configs.Box ~= false
	local Infos = Args.Infos or {}
	local DisplayText = Args.DisplayText

	local d = CreateDrawings()

	local TBL = {
		Drawings = d,
		infoDrawings = {},
		Cache = { corners = nil },
		TextCache = {},
		visibleState = nil,
		showBox = ShowBox,
		renderDistSq = RenderDistance * RenderDistance,
		renderDistance = RenderDistance,
		humanoid = nil,
		textColorFunc = nil,
		boxColorFunc = nil,
		lastDistInt = nil,
		lastDistTxt = nil,
		lastHpTxt = nil,
		Connections = {},
	}

	EspLib.Objects[Object] = TBL

	-- 颜色应用
	local function applyTextColor(c)
		d.Name.Color = c
		d.HealthText.Color = c
		d.Distance.Color = c
	end
	local function applyBoxColor(c)
		d.Box.Color = c
	end

	if typeof(color.Text) == "function" then
		TBL.textColorFunc = color.Text
	else
		applyTextColor(color.Text)
	end

	if typeof(color.Box) == "function" then
		TBL.boxColorFunc = color.Box
	else
		applyBoxColor(color.Box)
	end

	-- 血量
	local Humanoid
	if Object:IsA("Model") and ShowHealthBar then
		Humanoid = Object:FindFirstChildOfClass("Humanoid")
	end
	TBL.humanoid = Humanoid

	-- 信息行
	for _, v in pairs(Infos) do
		local t = Drawing.new("Text")
		t.Center = false
		t.Outline = true
		t.OutlineColor = C3(0, 0, 0)
		t.Color = C3(220, 220, 220)
		t.Size = 12
		t.Font = Drawing.Fonts.System
		t.Transparency = 1
		TBL.infoDrawings[#TBL.infoDrawings + 1] = {
			Drawing = t,
			Config = v,
			Cache = {},
		}
	end

	-- 清理连接
	TBL.DestroyingConn = Object.Destroying:Once(function()
		EspLib:UnwrapObject(Object)
	end)

	TBL.AncestryConn = Object.AncestryChanged:Connect(function()
		if not Object:IsDescendantOf(workspace) then
			EspLib:UnwrapObject(Object)
		end
	end)

	return {
		ChangeColor = function(obj, c)
			if obj:lower() == "text" then
				if typeof(c) == "function" then
					TBL.textColorFunc = c
				else
					TBL.textColorFunc = nil
					applyTextColor(c)
				end
			elseif obj:lower() == "box" then
				if typeof(c) == "function" then
					TBL.boxColorFunc = c
				else
					TBL.boxColorFunc = nil
					applyBoxColor(c)
				end
			end
		end,
	}
end

function EspLib:UnwrapObject(Object)
	if not Object then return false end
	local obj = EspLib.Objects[Object]
	if not obj then return false end

	if obj.DestroyingConn then obj.DestroyingConn:Disconnect() end
	if obj.AncestryConn then obj.AncestryConn:Disconnect() end
	for _, c in ipairs(obj.Connections) do
		c:Disconnect()
	end

	DestroyDrawings(obj.Drawings)

	EspLib.Objects[Object] = nil
	return true
end

-- ===== 全局单 RenderStepped =====

RunService.RenderStepped:Connect(function()
	local camPos = Camera.CFrame.Position

	for Object, TBL in pairs(EspLib.Objects) do
		local d = TBL.Drawings
		local cache = TBL.Cache

		-- 对象已移除则跳过（清理由 AncestryChanged 处理）
		if not Object.Parent then
			continue
		end

		-- 距离（平方比较，避免开方）
		local objPos
		if Object:IsA("Model") then
			objPos = Object:GetPivot().Position
		else
			objPos = Object.Position
		end
		local dx, dy, dz = camPos.X - objPos.X, camPos.Y - objPos.Y, camPos.Z - objPos.Z
		local distSq = dx * dx + dy * dy + dz * dz

		if distSq > TBL.renderDistSq then
			SetVisible(TBL, false)
			continue
		end

		local bounds = GetOnScreenBounds(Object, cache)
		if not bounds then
			SetVisible(TBL, false)
			continue
		end

		SetVisible(TBL, true)

		-- 函数型颜色
		if TBL.textColorFunc then
			d.Name.Color = TBL.textColorFunc(Object)
			d.HealthText.Color = d.Name.Color
			d.Distance.Color = d.Name.Color
		end
		if TBL.boxColorFunc then
			d.Box.Color = TBL.boxColorFunc(Object)
		end

		local x = bounds.bx + OFFSET_X
		local y = bounds.by + OFFSET_Y
		local w = bounds.bw
		local h = bounds.bh
		local centerX = x + w * 0.5

		-- 方框
		local thickness = d.Box.Thickness
		d.BoxShadow.Position = V2(x - 1, y - 1)
		d.BoxShadow.Size = V2(w + 2, h + 2)

		d.Box.Position = V2(x + thickness * 0.5, y + thickness * 0.5)
		d.Box.Size = V2(w - thickness, h - thickness)

		local nameTxt
		local displayText = TBL.DisplayText
		if displayText then
			nameTxt = typeof(displayText) == "function" and displayText(Object) or tostring(displayText)
		else
			nameTxt = Object.Name
		end
		nameTxt = tostring(nameTxt or "")

		local nameH = d.Name.Size
		local nameTopY = y - nameH - 6
		local nameSize = placeTextCentered(d.Name, nameTxt, centerX, nameTopY, TBL.TextCache.name or (function()
			TBL.TextCache.name = {}
			return TBL.TextCache.name
		end)())

		d.NameBg.Position = V2(centerX - nameSize.X * 0.5 - 4, nameTopY - 2)
		d.NameBg.Size = V2(nameSize.X + 8, nameSize.Y + 4)

		-- 血量
		local Humanoid = TBL.humanoid
		if Humanoid then
			local hp = Humanoid.Health
			local maxHp = Humanoid.MaxHealth
			local ratio = maxHp > 0 and MathClamp(hp / maxHp, 0, 1) or 0

			local barW = w
			local barH = 4
			local barY = y + h + 3

			d.HealthBarBg.Position = V2(x, barY)
			d.HealthBarBg.Size = V2(barW, barH)

			d.HealthBar.Position = V2(x, barY)
			d.HealthBar.Size = V2(barW * ratio, barH)

			if ratio > 0.5 then
				local t = (ratio - 0.5) / 0.5
				d.HealthBar.Color = C3(255, 200, 0):Lerp(C3(80, 220, 120), t)
			else
				local t = ratio / 0.5
				d.HealthBar.Color = C3(220, 60, 60):Lerp(C3(255, 200, 0), t)
			end

			local hpInt = MathFloor(hp)
			local maxHpInt = MathFloor(maxHp)
			if TBL.lastHp ~= hpInt or TBL.lastMaxHp ~= maxHpInt then
				TBL.lastHp = hpInt
				TBL.lastMaxHp = maxHpInt
				TBL.lastHpTxt = hpInt .. " / " .. maxHpInt
			end
			local hpCache = TBL.TextCache.hp or (function()
				TBL.TextCache.hp = {}
				return TBL.TextCache.hp
			end)()
			placeTextCentered(d.HealthText, TBL.lastHpTxt, centerX, barY + barH + 2, hpCache)
		end

		-- 距离
		local dist = MathSqrt(distSq)
		local distInt = MathFloor(dist)
		if TBL.lastDistInt ~= distInt then
			TBL.lastDistInt = distInt
			TBL.lastDistTxt = "[" .. distInt .. " studs]"
		end
		local distCache = TBL.TextCache.dist or (function()
			TBL.TextCache.dist = {}
			return TBL.TextCache.dist
		end)()
		local distTopY = y + h + (Humanoid and 30 or 8)
		placeTextCentered(d.Distance, TBL.lastDistTxt, centerX, distTopY, distCache)

		-- 信息行
		local infoY = y
		for i = 1, #TBL.infoDrawings do
			local item = TBL.infoDrawings[i]
			local v = item.Config
			local txt = tostring(GetVal(v.Text, Object) or "")
			local col = GetVal(v.Color, Object)
			local drawing = item.Drawing
			drawing.Color = col or C3(220, 220, 220)
			drawing.Position = V2(x + w + 6, infoY)
			if item.lastText ~= txt then
				item.lastText = txt
				drawing.Text = txt
			end
			infoY = infoY + 14
		end
	end
end)

return EspLib
