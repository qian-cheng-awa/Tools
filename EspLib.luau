local Player = game:GetService("Players").LocalPlayer
local Camera = workspace.CurrentCamera
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Drawing = Drawing

local EspLib = {
    Objects = {},
    Ray = {
        Enabled = false,
        Origin = Vector2.new(0.5, 0),
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 1,
        Transparency = 1,
        FollowBoxColor = true,
    },
}

local OFFSET_Y = GuiService:GetGuiInset().Y
local OFFSET_X = 0

local V2 = Vector2.new
local C3 = Color3.fromRGB
local MathFloor = math.floor
local MathClamp = math.clamp
local MathHuge = math.huge
local MathSqrt = math.sqrt
local U8Codes = utf8.codes

local function GetVal(val, ...)
    if typeof(val) == "function" then
        return val(...)
    end
    return val
end

local function hasNonASCII(text)
    for _, code in U8Codes(text) do
        if code > 127 then return true end
    end
    return false
end

local function placeTextLeft(drawing, text, leftX, topY, cache)
    if cache.lastText ~= text then
        drawing.Text = text
        cache.lastText = text
        cache.width = drawing.TextBounds.X
    end
    drawing.Center = false
    drawing.Position = V2(leftX, topY)
    return cache.width
end

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

-- ===== ScreenGui =====

local fallbackGui = Instance.new("ScreenGui")
fallbackGui.Name = "EspFallback"
fallbackGui.ResetOnSpawn = false
fallbackGui.IgnoreGuiInset = true
fallbackGui.DisplayOrder = 999
fallbackGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

do
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    fallbackGui.Parent = parent
end

-- 名字行背景 + 文字（圆角由 UICorner 保证）
local function createNameLabel()
    local label = Instance.new("TextLabel")
    label.AnchorPoint = Vector2.new(0, 0)
    label.Font = Enum.Font.SourceSans
    label.TextSize = 14
    label.TextColor3 = C3(255, 255, 255)
    label.TextStrokeTransparency = 0
    label.TextStrokeColor3 = C3(0, 0, 0)
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.BackgroundTransparency = 0.4
    label.BackgroundColor3 = C3(20, 20, 25)
    label.Size = UDim2.fromOffset(120, 20)
    label.Text = ""
    label.TextTransparency = 1   -- 默认隐藏文字，只留背景
    label.Visible = true
    label.Parent = fallbackGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = label

    return label
end

-- ===== Drawing 创建 =====

local function CreateDrawings()
    local d = {}

    d.Box = Drawing.new("Square")
    d.Box.Filled = false
    d.Box.Thickness = 1
    d.Box.Color = C3(255, 255, 255)
    d.Box.Transparency = 1

    d.HpText = Drawing.new("Text")
    d.HpText.Center = false
    d.HpText.Outline = true
    d.HpText.OutlineColor = C3(0, 0, 0)
    d.HpText.Color = C3(80, 220, 120)
    d.HpText.Size = 14
    d.HpText.Font = Drawing.Fonts.System
    d.HpText.Transparency = 1

    d.NameText = Drawing.new("Text")
    d.NameText.Center = false
    d.NameText.Outline = true
    d.NameText.OutlineColor = C3(0, 0, 0)
    d.NameText.Color = C3(255, 255, 255)
    d.NameText.Size = 14
    d.NameText.Font = Drawing.Fonts.System
    d.NameText.Transparency = 1

    d.DistText = Drawing.new("Text")
    d.DistText.Center = false
    d.DistText.Outline = true
    d.DistText.OutlineColor = C3(0, 0, 0)
    d.DistText.Color = C3(160, 160, 170)
    d.DistText.Size = 14
    d.DistText.Font = Drawing.Fonts.System
    d.DistText.Transparency = 1

    d.HealthBarBg = Drawing.new("Square")
    d.HealthBarBg.Filled = true
    d.HealthBarBg.Color = C3(15, 15, 18)
    d.HealthBarBg.Transparency = 0.5

    d.HealthBar = Drawing.new("Square")
    d.HealthBar.Filled = true
    d.HealthBar.Color = C3(40, 160, 70)
    d.HealthBar.Transparency = 0.95

    d.Ray = Drawing.new("Line")
    d.Ray.Visible = false
    d.Ray.Thickness = 1
    d.Ray.Transparency = 1
    d.Ray.Color = C3(255, 255, 255)

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

    d.Box.Visible = visible and tbl.showBox
    d.Ray.Visible = visible and EspLib.Ray.Enabled

    if not visible then
        d.HpText.Visible = false
        d.NameText.Visible = false
        d.DistText.Visible = false
        if tbl.humanoid then
            d.HealthBarBg.Visible = false
            d.HealthBar.Visible = false
        end
        if tbl.nameLabel then tbl.nameLabel.Visible = false end
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
    local DisplayText = Args.DisplayText

    local d = CreateDrawings()
    local nameLabel = createNameLabel()

    local TBL = {
        Drawings = d,
        Cache = { corners = nil },
        HpCache = {},
        NameCache = {},
        DistCache = {},
        visibleState = nil,
        showBox = ShowBox,
        renderDistSq = RenderDistance * RenderDistance,
        humanoid = nil,
        boxColor = C3(255, 255, 255),
        textColorFunc = nil,
        boxColorFunc = nil,
        DisplayText = DisplayText,
        nameLabel = nameLabel,
        Connections = {},
    }

    EspLib.Objects[Object] = TBL

    if typeof(color.Text) == "function" then
        TBL.textColorFunc = color.Text
    end

    if typeof(color.Box) == "function" then
        TBL.boxColorFunc = color.Box
    else
        d.Box.Color = color.Box
        TBL.boxColor = color.Box
    end

    local Humanoid
    if Object:IsA("Model") and ShowHealthBar then
        Humanoid = Object:FindFirstChildOfClass("Humanoid")
    end
    TBL.humanoid = Humanoid

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
                    d.NameText.Color = c
                end
            elseif obj:lower() == "box" then
                if typeof(c) == "function" then
                    TBL.boxColorFunc = c
                else
                    TBL.boxColorFunc = nil
                    d.Box.Color = c
                    TBL.boxColor = c
                end
            end
        end,
    }
end

function EspLib:UnwrapObject(Object)
    if not Object then return false end
    local obj = EspLib.Objects[Object]
    if not obj then return false end

    obj.destroyed = true
    EspLib.Objects[Object] = nil

    if obj.DestroyingConn then obj.DestroyingConn:Disconnect() end
    if obj.AncestryConn then obj.AncestryConn:Disconnect() end
    for _, c in ipairs(obj.Connections) do
        c:Disconnect()
    end

    if obj.nameLabel then obj.nameLabel:Destroy() end

    DestroyDrawings(obj.Drawings)

    return true
end

RunService.RenderStepped:Connect(function()
    local camPos = Camera.CFrame.Position
    local rayCfg = EspLib.Ray
    local vp = Camera.ViewportSize
    local rayOriginX = rayCfg.Origin.X * vp.X
    local rayOriginY = rayCfg.Origin.Y * vp.Y
    if rayCfg.Origin.Y == 0 then
        rayOriginY = rayOriginY + OFFSET_Y
    end

    for Object, TBL in pairs(EspLib.Objects) do
        if TBL.destroyed or EspLib.Objects[Object] ~= TBL then
            continue
        end
        local d = TBL.Drawings
        local cache = TBL.Cache

        if not Object.Parent then
            continue
        end

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

        if TBL.boxColorFunc then
            local c = TBL.boxColorFunc(Object)
            d.Box.Color = c
            TBL.boxColor = c
        end

        local x = bounds.bx + OFFSET_X
        local y = bounds.by + OFFSET_Y
        local w = bounds.bw
        local h = bounds.bh
        local centerX = x + w * 0.5

        -- 方框
        local thickness = d.Box.Thickness
        d.Box.Visible = TBL.showBox
        d.Box.Position = V2(x + thickness * 0.5, y + thickness * 0.5)
        d.Box.Size = V2(w - thickness, h - thickness)

        -- 射线
        if rayCfg.Enabled then
            d.Ray.Visible = true
            d.Ray.From = Vector2.new(rayOriginX, rayOriginY)
            d.Ray.To = Vector2.new(centerX, y + h * 0.5)
            d.Ray.Color = rayCfg.FollowBoxColor and TBL.boxColor or rayCfg.Color
            d.Ray.Thickness = rayCfg.Thickness
            d.Ray.Transparency = rayCfg.Transparency
        else
            d.Ray.Visible = false
        end

        -- 竖向血条
        local Humanoid = TBL.humanoid
        if Humanoid then
            local hp = Humanoid.Health
            local maxHp = Humanoid.MaxHealth
            local ratio = maxHp > 0 and MathClamp(hp / maxHp, 0, 1) or 0

            local barW = 3
            local barH = h
            local barX = x - barW - 3
            local barY = y

            d.HealthBarBg.Visible = true
            d.HealthBarBg.Position = V2(barX, barY)
            d.HealthBarBg.Size = V2(barW, barH)

            d.HealthBar.Visible = true
            d.HealthBar.Position = V2(barX, barY + barH * (1 - ratio))
            d.HealthBar.Size = V2(barW, barH * ratio)

            if ratio > 0.5 then
                local t = (ratio - 0.5) / 0.5
                d.HealthBar.Color = C3(180, 140, 0):Lerp(C3(40, 160, 70), t)
            else
                local t = ratio / 0.5
                d.HealthBar.Color = C3(150, 35, 35):Lerp(C3(180, 140, 0), t)
            end
        end

        -- 名字三段
        local nameTxt
        local displayText = TBL.DisplayText
        if displayText then
            nameTxt = typeof(displayText) == "function" and displayText(Object) or tostring(displayText)
        else
            nameTxt = Object.Name
        end
        nameTxt = tostring(nameTxt or "")

        local dist = MathSqrt(distSq)
        local distInt = MathFloor(dist)

        local nameColor = C3(255, 255, 255)
        if TBL.textColorFunc then
            nameColor = TBL.textColorFunc(Object)
        else
            local team = Object:FindFirstChildOfClass("Team")
            if not team and Object.Parent and Object.Parent:IsA("Team") then
                team = Object.Parent
            end
            if team and team:IsA("Team") then
                nameColor = team.TeamColor.Color
            end
        end

        local hpStr = ""
        if Humanoid then
            hpStr = "HP" .. MathFloor(Humanoid.Health)
        end
        local distStr = distInt .. "m"

        local nameH = d.NameText.Size
        local nameTopY = y - nameH - 6

        -- 测量宽度
        local hpW = 0
        if hpStr ~= "" then
            hpW = placeTextLeft(d.HpText, hpStr, 0, 0, TBL.HpCache)
        end
        local nameCN = hasNonASCII(nameTxt)
        local nameW = 0
        if not nameCN then
            nameW = placeTextLeft(d.NameText, nameTxt, 0, 0, TBL.NameCache)
        end
        local distW = placeTextLeft(d.DistText, distStr, 0, 0, TBL.DistCache)

        local gap = 4
        local nameDisplayW = nameCN and 120 or nameW
        local totalW = hpW + nameDisplayW + distW
        if hpStr ~= "" then totalW = totalW + gap end
        totalW = totalW + gap

        local startX = centerX - totalW * 0.5

        -- 血量段
        if hpStr ~= "" then
            d.HpText.Visible = true
            placeTextLeft(d.HpText, hpStr, startX, nameTopY, TBL.HpCache)
            startX = startX + hpW + gap
        else
            d.HpText.Visible = false
        end

        -- 名字段：TextLabel 统一承载背景，中文时显示文字
        local lbl = TBL.nameLabel
        lbl.Position = UDim2.fromOffset(startX, nameTopY - 3)
        lbl.Size = UDim2.fromOffset(nameDisplayW, nameH + 6)
        lbl.Visible = true

        if nameCN then
            d.NameText.Visible = false
            lbl.Text = nameTxt
            lbl.TextColor3 = nameColor
            lbl.TextTransparency = 0
        else
            d.NameText.Visible = true
            d.NameText.Color = nameColor
            placeTextLeft(d.NameText, nameTxt, startX, nameTopY, TBL.NameCache)
            lbl.Text = ""
            lbl.TextTransparency = 1   -- 只留背景
        end
        startX = startX + nameDisplayW + gap

        -- 距离段
        d.DistText.Visible = true
        placeTextLeft(d.DistText, distStr, startX, nameTopY, TBL.DistCache)

        SetVisible(TBL, true)
    end
end)

return EspLib
