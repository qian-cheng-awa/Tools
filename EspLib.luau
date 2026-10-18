local Player = game:GetService("Players").LocalPlayer
local Camera = workspace.CurrentCamera
local RunService = game:GetService("RunService")

local EspLib = {
	Objects = {},
}

-- ===== 工具函数 =====

local function GetVal(val, ...)
	if typeof(val) == "function" then
		return val(...)
	end
	return val
end

-- 计算模型/部件在屏幕上的包围盒（像素）
local function GetOnScreenBounds(model)
	local cf, size
	if model:IsA("Model") then
		cf, size = model:GetPivot(), model:GetExtentsSize()
	elseif model:IsA("BasePart") then
		cf, size = model.CFrame, model.Size
	else
		return nil
	end

	local half = size * 0.5
	local corners = {
		cf * CFrame.new(-half.X, -half.Y, -half.Z),
		cf * CFrame.new( half.X, -half.Y, -half.Z),
		cf * CFrame.new(-half.X,  half.Y, -half.Z),
		cf * CFrame.new( half.X,  half.Y, -half.Z),
		cf * CFrame.new(-half.X, -half.Y,  half.Z),
		cf * CFrame.new( half.X, -half.Y,  half.Z),
		cf * CFrame.new(-half.X,  half.Y,  half.Z),
		cf * CFrame.new( half.X,  half.Y,  half.Z),
	}

	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge

	for _, c in ipairs(corners) do
		local sp, onScreen = Camera:WorldToScreenPoint(c.Position)
		if sp.Z <= 0 then
			continue
		end
		minX = math.min(minX, sp.X)
		minY = math.min(minY, sp.Y)
		maxX = math.max(maxX, sp.X)
		maxY = math.max(maxY, sp.Y)
	end

	if minX == math.huge then
		return nil
	end

	return {
		X = minX,
		Y = minY,
		W = maxX - minX,
		H = maxY - minY,
	}
end

-- 创建一组 Drawing 对象
local function CreateDrawings()
	local d = {}

	d.Box = Drawing.new("Square")
	d.Box.Thickness = 1
	d.Box.Filled = false
	d.Box.Color = Color3.fromRGB(255, 255, 255)
	d.Box.Transparency = 1

	d.Name = Drawing.new("Text")
	d.Name.Center = true
	d.Name.Outline = true
	d.Name.OutlineColor = Color3.fromRGB(0, 0, 0)
	d.Name.Color = Color3.fromRGB(255, 255, 255)
	d.Name.Size = 14
	d.Name.Font = Drawing.Fonts.System
	d.Name.Transparency = 1

	d.HealthBarBg = Drawing.new("Square")
	d.HealthBarBg.Filled = true
	d.HealthBarBg.Color = Color3.fromRGB(54, 22, 4)
	d.HealthBarBg.Transparency = 1

	d.HealthBar = Drawing.new("Square")
	d.HealthBar.Filled = true
	d.HealthBar.Color = Color3.fromRGB(79, 214, 59)
	d.HealthBar.Transparency = 1

	d.HealthText = Drawing.new("Text")
	d.HealthText.Center = true
	d.HealthText.Outline = true
	d.HealthText.OutlineColor = Color3.fromRGB(0, 0, 0)
	d.HealthText.Color = Color3.fromRGB(255, 255, 255)
	d.HealthText.Size = 14
	d.HealthText.Font = Drawing.Fonts.System
	d.HealthText.Transparency = 1

	return d
end

local function DestroyDrawings(d)
	for _, obj in pairs(d) do
		if obj and obj.Destroy then
			obj:Destroy()
		end
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
				Text = color.Text or Color3.fromRGB(255, 255, 255),
				Box = color.Box or Color3.fromRGB(255, 255, 255),
			}
		else
			color = { Text = color, Box = color }
		end
	else
		color = {
			Text = Color3.fromRGB(255, 255, 255),
			Box = Color3.fromRGB(255, 255, 255),
		}
	end

	local Object = Args.Object
	local RenderDistance = Args.RenderDistance or math.huge
	local ShowHealthBar = Args.Configs.HealthBar ~= false
	local ShowBox = Args.Configs.Box ~= false
	local Infos = Args.Infos or {}
	local DisplayText = Args.DisplayText

	local d = CreateDrawings()
	d.Box.Visible = ShowBox

	local TBL = {
		Drawings = d,
		Connections = {},
		TextConnect = nil,
		BoxColorConnect = nil,
		TextColorConnect = nil,
	}

	EspLib.Objects[Object] = TBL

	-- 文本显示
	local function updateDisplayText()
		local txt
		if DisplayText then
			txt = typeof(DisplayText) == "function" and DisplayText(Object) or tostring(DisplayText)
		else
			txt = Object.Name
		end
		d.Name.Text = tostring(txt or "")
	end
	updateDisplayText()

	-- 颜色
	local function applyTextColor(c)
		d.Name.Color = c
		d.HealthText.Color = c
	end
	local function applyBoxColor(c)
		d.Box.Color = c
	end

	if typeof(color.Text) == "function" then
		TBL.TextColorConnect = RunService.RenderStepped:Connect(function()
			applyTextColor(color.Text(Object))
		end)
	else
		applyTextColor(color.Text)
	end

	if typeof(color.Box) == "function" then
		TBL.BoxColorConnect = RunService.RenderStepped:Connect(function()
			applyBoxColor(color.Box(Object))
		end)
	else
		applyBoxColor(color.Box)
	end

	-- 血量
	local Humanoid
	if Object:IsA("Model") and ShowHealthBar then
		Humanoid = Object:FindFirstChildOfClass("Humanoid")
	end

	-- 信息行
	local infoDrawings = {}
	for i, v in pairs(Infos) do
		local t = Drawing.new("Text")
		t.Center = true
		t.Outline = true
		t.OutlineColor = Color3.fromRGB(0, 0, 0)
		t.Color = Color3.fromRGB(255, 255, 255)
		t.Size = 13
		t.Font = Drawing.Fonts.System
		t.Transparency = 1
		infoDrawings[#infoDrawings + 1] = { Drawing = t, Config = v, Index = i }
	end

	-- 每帧更新
	local renderConn = RunService.RenderStepped:Connect(function()
		if not Object or not Object.Parent then
			EspLib:UnwrapObject(Object)
			return
		end

		local dist = (Camera.CFrame.Position - (Object:IsA("Model") and Object:GetPivot().Position or Object.Position)).Magnitude
		if dist > RenderDistance then
			-- 超出距离隐藏
			for _, obj in pairs(d) do
				if obj.Visible ~= nil then obj.Visible = false end
			end
			for _, item in ipairs(infoDrawings) do
				item.Drawing.Visible = false
			end
			return
		end

		local bounds = GetOnScreenBounds(Object)
		if not bounds then
			for _, obj in pairs(d) do
				if obj.Visible ~= nil then obj.Visible = false end
			end
			for _, item in ipairs(infoDrawings) do
				item.Drawing.Visible = false
			end
			return
		end

		local x, y, w, h = bounds.X, bounds.Y, bounds.W, bounds.H
		local centerX = x + w * 0.5

		-- 框
		d.Box.Visible = ShowBox
		d.Box.Position = Vector2.new(x, y)
		d.Box.Size = Vector2.new(w, h)

		-- 名字（框上方）
		d.Name.Visible = true
		d.Name.Position = Vector2.new(centerX, y - 16)
		if DisplayText and typeof(DisplayText) == "function" then
			d.Name.Text = tostring(DisplayText(Object) or "")
		end

		-- 血量
		if Humanoid then
			local hp = Humanoid.Health
			local maxHp = Humanoid.MaxHealth
			local ratio = maxHp > 0 and math.clamp(hp / maxHp, 0, 1) or 0

			local barW = w
			local barH = 4
			local barY = y + h + 3

			d.HealthBarBg.Visible = true
			d.HealthBarBg.Position = Vector2.new(x, barY)
			d.HealthBarBg.Size = Vector2.new(barW, barH)

			d.HealthBar.Visible = true
			d.HealthBar.Position = Vector2.new(x, barY)
			d.HealthBar.Size = Vector2.new(barW * ratio, barH)

			d.HealthText.Visible = true
			d.HealthText.Position = Vector2.new(centerX, barY + barH + 2)
			d.HealthText.Text = string.format("%.1f/%.1f", hp, maxHp)
		else
			d.HealthBarBg.Visible = false
			d.HealthBar.Visible = false
			d.HealthText.Visible = false
		end

		-- 信息行（框下方依次排列）
		local infoY = y + h + (Humanoid and 30 or 6)
		for _, item in ipairs(infoDrawings) do
			local v = item.Config
			local txt = GetVal(v.Text, Object)
			local col = GetVal(v.Color, Object)
			item.Drawing.Visible = true
			item.Drawing.Text = tostring(txt or "")
			item.Drawing.Color = col or Color3.fromRGB(255, 255, 255)
			item.Drawing.Position = Vector2.new(centerX, infoY)
			infoY = infoY + 15
		end
	end)

	TBL.RenderConn = renderConn

	-- 清理
	local destroyingConn = Object.Destroying:Once(function()
		EspLib:UnwrapObject(Object)
	end)
	TBL.DestroyingConn = destroyingConn

	local ancestryConn = Object.AncestryChanged:Connect(function()
		if not Object:IsDescendantOf(workspace) then
			EspLib:UnwrapObject(Object)
		end
	end)
	TBL.AncestryConn = ancestryConn

	return {
		ChangeColor = function(obj, c)
			if obj:lower() == "text" then
				if TBL.TextColorConnect then TBL.TextColorConnect:Disconnect() end
				if typeof(c) == "function" then
					TBL.TextColorConnect = RunService.RenderStepped:Connect(function()
						applyTextColor(c(Object))
					end)
				else
					applyTextColor(c)
				end
			elseif obj:lower() == "box" then
				if TBL.BoxColorConnect then TBL.BoxColorConnect:Disconnect() end
				if typeof(c) == "function" then
					TBL.BoxColorConnect = RunService.RenderStepped:Connect(function()
						applyBoxColor(c(Object))
					end)
				else
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

	if obj.TextConnect then obj.TextConnect:Disconnect() end
	if obj.BoxColorConnect then obj.BoxColorConnect:Disconnect() end
	if obj.TextColorConnect then obj.TextColorConnect:Disconnect() end
	if obj.RenderConn then obj.RenderConn:Disconnect() end
	if obj.DestroyingConn then obj.DestroyingConn:Disconnect() end
	if obj.AncestryConn then obj.AncestryConn:Disconnect() end
	for _, c in ipairs(obj.Connections) do
		c:Disconnect()
	end

	DestroyDrawings(obj.Drawings)

	EspLib.Objects[Object] = nil
	return true
end

return EspLib
