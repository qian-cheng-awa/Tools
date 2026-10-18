local Player = game:GetService("Players").LocalPlayer
local Camera = workspace.CurrentCamera
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Drawing = Drawing

local EspLib = {
    Objects = {},
    Ray = {
        Enabled = false,
        Origin = Vector2.new(0.5, 0),   -- 比例坐标：0.5,0 = 屏幕水平中心最上方
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 1,
        Transparency = 1,
        FollowBoxColor = true,          -- 颜色跟随各自方框颜色
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

local function placeTextCentered(drawing, text, centerX, topY, cache)
    if cache.lastText ~= text then
        drawing.Text = text
        cache.lastText = text
        cache.width = drawing.TextBounds.X
    end
    drawing.Center = false
    drawing.Position = V2(centerX - cache.width * 0.5, topY)
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

-- ===== ScreenGui（中文 TextLabel 回退） =====

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

local function createFallbackLabel()
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromOffset(240, 20)
    label.AnchorPoint = Vector2.new(0.5, 0)
    label.Font = Enum.Font.SourceSans
    label.TextSize = 14
    label.TextColor3 = C3(255, 255, 255)
    label.TextStrokeTransparency = 0
    label.TextStrokeColor3 = C3(0, 0, 0)
    label.Text = ""
    label.Visible = false
    label.Parent = fallbackGui
    return label
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

    -- 每个对象一条射线
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
    local infoDrawings = tbl.infoDrawings
    local showBox = tbl.showBox

    d.Box.Visible = visible and showBox
    d.BoxShadow.Visible = visible and showBox
    d.NameBg.Visible = visible and not tbl.isChinese
    d.Name.Visible = visible and not tbl.isChinese

    if tbl.humanoid then
        d.HealthBarBg.Visible = visible
        d.HealthBar.Visible = visible
        d.HealthText.Visible = visible
    end
    d.Distance.Visible = visible
    d.Ray.Visible = visible and EspLib.Ray.Enabled

    for i = 1, #infoDrawings do
        local item = infoDrawings[i]
        item.Drawing.Visible = visible and not item.isChinese
        if item.fallbackLabel then
            item.fallbackLabel.Visible = visible and item.isChinese
        end
    end

    if tbl.fallbackLabel then
        tbl.fallbackLabel.Visible = visible and tbl.isChinese
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
        NameCache = {},
        HealthCache = {},
        DistCache = {},
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
        DisplayText = DisplayText,
        isChinese = false,
        fallbackLabel = nil,
        boxColor = C3(255, 255, 255),
        Connections = {},
    }

    EspLib.Objects[Object] = TBL

    local function applyTextColor(c)
        d.Name.Color = c
        d.HealthText.Color = c
        d.Distance.Color = c
        if TBL.fallbackLabel then
            TBL.fallbackLabel.TextColor3 = c
        end
    end
    local function applyBoxColor(c)
        d.Box.Color = c
        TBL.boxColor = c
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

    local Humanoid
    if Object:IsA("Model") and ShowHealthBar then
        Humanoid = Object:FindFirstChildOfClass("Humanoid")
    end
    TBL.humanoid = Humanoid

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
            lastText = nil,
            fallbackLabel = nil,
            isChinese = false,
        }
    end

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

    obj.destroyed = true
    EspLib.Objects[Object] = nil

    if obj.DestroyingConn then obj.DestroyingConn:Disconnect() end
    if obj.AncestryConn then obj.AncestryConn:Disconnect() end
    for _, c in ipairs(obj.Connections) do
        c:Disconnect()
    end

    if obj.fallbackLabel then
        obj.fallbackLabel:Destroy()
    end

    for i = 1, #obj.infoDrawings do
        local item = obj.infoDrawings[i]
        if item.fallbackLabel then
            item.fallbackLabel:Destroy()
            item.fallbackLabel = nil
        end
    end

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

        if TBL.textColorFunc then
            local c = TBL.textColorFunc(Object)
            d.Name.Color = c
            d.HealthText.Color = c
            d.Distance.Color = c
            if TBL.fallbackLabel then TBL.fallbackLabel.TextColor3 = c end
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
        local centerY = y + h * 0.5

        local thickness = d.Box.Thickness
        d.BoxShadow.Visible = TBL.showBox
        d.BoxShadow.Position = V2(x - 1, y - 1)
        d.BoxShadow.Size = V2(w + 2, h + 2)

        d.Box.Visible = TBL.showBox
        d.Box.Position = V2(x + thickness * 0.5, y + thickness * 0.5)
        d.Box.Size = V2(w - thickness, h - thickness)

        -- ===== 每个对象的射线 =====
        if rayCfg.Enabled then
            d.Ray.Visible = true
            d.Ray.PointA = Vector2.new(rayOriginX, rayOriginY)
            d.Ray.PointB = Vector2.new(centerX, centerY)
            d.Ray.Color = rayCfg.FollowBoxColor and TBL.boxColor or rayCfg.Color
            d.Ray.Thickness = rayCfg.Thickness
            d.Ray.Transparency = rayCfg.Transparency
        else
            d.Ray.Visible = false
        end

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
        local isChinese = hasNonASCII(nameTxt)

        if isChinese then
            d.Name.Visible = false
            d.NameBg.Visible = false
            if not TBL.fallbackLabel then
                TBL.fallbackLabel = createFallbackLabel()
            end
            local lbl = TBL.fallbackLabel
            lbl.Text = nameTxt
            lbl.TextXAlignment = Enum.TextXAlignment.Center
            lbl.Position = UDim2.fromOffset(centerX, nameTopY)
            lbl.Visible = true
        else
            if TBL.fallbackLabel then
                TBL.fallbackLabel.Visible = false
            end
            d.Name.Visible = true
            d.NameBg.Visible = true
            local nameW = placeTextCentered(d.Name, nameTxt, centerX, nameTopY, TBL.NameCache)
            d.NameBg.Position = V2(centerX - nameW * 0.5 - 4, nameTopY - 2)
            d.NameBg.Size = V2(nameW + 8, nameH + 4)
        end

        if TBL.isChinese ~= isChinese then
            TBL.isChinese = isChinese
            if TBL.fallbackLabel then
                TBL.fallbackLabel.Visible = isChinese
            end
        elseif isChinese and TBL.fallbackLabel then
            TBL.fallbackLabel.Visible = true
        end

        local Humanoid = TBL.humanoid
        if Humanoid then
            local hp = Humanoid.Health
            local maxHp = Humanoid.MaxHealth
            local ratio = maxHp > 0 and MathClamp(hp / maxHp, 0, 1) or 0

            local barW = w
            local barH = 4
            local barY = y + h + 3

            d.HealthBarBg.Visible = true
            d.HealthBarBg.Position = V2(x, barY)
            d.HealthBarBg.Size = V2(barW, barH)

            d.HealthBar.Visible = true
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
            d.HealthText.Visible = true
            placeTextCentered(d.HealthText, TBL.lastHpTxt, centerX, barY + barH + 2, TBL.HealthCache)
        end

        local dist = MathSqrt(distSq)
        local distInt = MathFloor(dist)
        if TBL.lastDistInt ~= distInt then
            TBL.lastDistInt = distInt
            TBL.lastDistTxt = "[" .. distInt .. " studs]"
        end
        d.Distance.Visible = true
        local distTopY = y + h + (Humanoid and 30 or 8)
        placeTextCentered(d.Distance, TBL.lastDistTxt, centerX, distTopY, TBL.DistCache)

        local infoY = y
        for i = 1, #TBL.infoDrawings do
            local item = TBL.infoDrawings[i]
            local v = item.Config
            local txt = tostring(GetVal(v.Text, Object) or "")
            local col = GetVal(v.Color, Object) or C3(220, 220, 220)
            local drawing = item.Drawing
            local isCN = hasNonASCII(txt)

            if isCN then
                drawing.Visible = false
                if not item.fallbackLabel then
                    item.fallbackLabel = createFallbackLabel()
                    item.fallbackLabel.AnchorPoint = Vector2.new(0, 0)
                    item.fallbackLabel.Size = UDim2.fromOffset(200, 14)
                end
                local lbl = item.fallbackLabel
                lbl.Text = txt
                lbl.TextColor3 = col
                lbl.Position = UDim2.fromOffset(x + w + 6, infoY)
                lbl.Visible = true
            else
                if item.fallbackLabel then
                    item.fallbackLabel.Visible = false
                end
                drawing.Visible = true
                drawing.Color = col
                drawing.Position = V2(x + w + 6, infoY)
                if item.lastText ~= txt then
                    item.lastText = txt
                    drawing.Text = txt
                end
            end

            item.isChinese = isCN
            infoY = infoY + 14
        end

        SetVisible(TBL, true)
    end
end)

return EspLib
