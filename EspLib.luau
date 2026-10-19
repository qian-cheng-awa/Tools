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

local function GetVal(val, ...)
    if typeof(val) == "function" then
        return val(...)
    end
    return val
end

local function colorToHex(c)
    return string.format("#%02X%02X%02X",
        MathFloor(c.R * 255 + 0.5),
        MathFloor(c.G * 255 + 0.5),
        MathFloor(c.B * 255 + 0.5))
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

-- 整行：背景 + 富文本，宽度自动
local function createRowLabel()
    local label = Instance.new("TextLabel")
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Font = Enum.Font.SourceSans
    label.TextSize = 14
    label.TextColor3 = C3(255, 255, 255)
    label.TextStrokeTransparency = 0
    label.TextStrokeColor3 = C3(0, 0, 0)
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.RichText = true
    label.BackgroundTransparency = 0.4
    label.BackgroundColor3 = C3(20, 20, 25)
    label.AutomaticSize = Enum.AutomaticSize.X
    label.Size = UDim2.fromOffset(0, 20)
    label.Text = ""
    label.Visible = false
    label.Parent = fallbackGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = label

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = label

    return label
end

-- ===== Drawing 创建（只保留方框、血条、射线） =====

local function CreateDrawings()
    local d = {}

    d.Box = Drawing.new("Square")
    d.Box.Filled = false
    d.Box.Thickness = 1
    d.Box.Color = C3(255, 255, 255)
    d.Box.Transparency = 1

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

-- ===== 可见性 =====

local function SetVisible(tbl, visible)
    if tbl.visibleState == visible then return end
    tbl.visibleState = visible
    local d = tbl.Drawings

    d.Box.Visible = visible and tbl.showBox
    d.Ray.Visible = visible and EspLib.Ray.Enabled

    if not visible then
        if tbl.humanoid then
            d.HealthBarBg.Visible = false
            d.HealthBar.Visible = false
        end
        if tbl.rowLabel then tbl.rowLabel.Visible = false end
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
    local rowLabel = createRowLabel()

    local TBL = {
        Drawings = d,
        Cache = { corners = nil },
        visibleState = nil,
        showBox = ShowBox,
        renderDistSq = RenderDistance * RenderDistance,
        humanoid = nil,
        boxColor = C3(255, 255, 255),
        textColorFunc = nil,
        boxColorFunc = nil,
        DisplayText = DisplayText,
        rowLabel = rowLabel,
        Connections = {},
        lastRowText = nil,
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

    if obj.rowLabel then obj.rowLabel:Destroy() end

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

        -- 名字颜色
        local nameTxt
        local displayText = TBL.DisplayText
        if displayText then
            nameTxt = typeof(displayText) == "function" and displayText(Object) or tostring(displayText)
        else
            nameTxt = Object.Name
        end
        nameTxt = tostring(nameTxt or "")

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

        -- RichText 拼接
        local parts = {}
        if Humanoid then
            local hpInt = MathFloor(Humanoid.Health)
            parts[#parts + 1] = '<font color="' .. colorToHex(C3(80, 220, 120)) .. '">♥' .. hpInt .. '</font>'
        end
        parts[#parts + 1] = '<font color="' .. colorToHex(nameColor) .. '">' .. nameTxt .. '</font>'
        local distStr = MathFloor(MathSqrt(distSq)) .. "m"
        parts[#parts + 1] = '<font color="' .. colorToHex(C3(160, 160, 170)) .. '">' .. distStr .. '</font>'

        local rowText = table.concat(parts, " ")

        local lbl = TBL.rowLabel
        if TBL.lastRowText ~= rowText then
            TBL.lastRowText = rowText
            lbl.Text = rowText
        end
        lbl.Visible = true
        lbl.Position = UDim2.fromOffset(centerX, y - 4)

        SetVisible(TBL, true)
    end
end)

return EspLib
