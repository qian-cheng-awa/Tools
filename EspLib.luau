local Player = game:GetService("Players").LocalPlayer
local EspLib = {
	Objects = {},
}

local GuiMain = Player.PlayerGui
if gethui then
	GuiMain = gethui()
elseif game.CoreGui then
	GuiMain = game.CoreGui
end

local EspFolder = GuiMain:FindFirstChild("ESP") or Instance.new("Folder",GuiMain)
EspFolder.Name = "Bi_Xie Esp"
EspFolder:ClearAllChildren()

local function GetVal(val,...)
	if typeof(val) == "function" then
		return val(...)
	end
	return val
end


local Main = Instance.new("BillboardGui")
Main.LightInfluence = 1
Main.Name = "Main"
Main.Active = true
Main.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Main.AlwaysOnTop = true
Main.Size = UDim2.new(4, 300, 5, 200)

local Box = Instance.new("Frame")
Box.BorderColor3 = Color3.fromRGB(0, 0, 0)
Box.AnchorPoint = Vector2.new(0.5, 0.5)
Box.Parent = Main
Box.BackgroundTransparency = 1
Box.Position = UDim2.fromScale(0.5, 0.5)
Box.Name = "Box"
Box.Size = UDim2.new(1, -300, 1, -200)
Box.BorderSizePixel = 0
Box.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(255, 255, 255)
UIStroke.Parent = Box

local HealthBar = Instance.new("Frame")
HealthBar.AnchorPoint = Vector2.new(0.5, 0)
HealthBar.Parent = Box
HealthBar.Name = "HealthBar"
HealthBar.Position = UDim2.fromScale(0.5, 0)
HealthBar.BorderColor3 = Color3.fromRGB(0, 0, 0)
HealthBar.Size = UDim2.fromOffset(100, 5)
HealthBar.BorderSizePixel = 0
HealthBar.BackgroundColor3 = Color3.fromRGB(54, 22, 4)

local UICorner = Instance.new("UICorner")
UICorner.Parent = HealthBar
UICorner.CornerRadius = UDim.new(1, 0)

local Frame = Instance.new("Frame")
Frame.Parent = HealthBar
Frame.BorderColor3 = Color3.fromRGB(0, 0, 0)
Frame.Size = UDim2.fromScale(1, 1)
Frame.BorderSizePixel = 0
Frame.BackgroundColor3 = Color3.fromRGB(79, 214, 59)

local UICorner = Instance.new("UICorner")
UICorner.Parent = Frame
UICorner.CornerRadius = UDim.new(1, 0)

local HealthDisplay = Instance.new("TextLabel")
HealthDisplay.Parent = Box
HealthDisplay.TextWrapped = true
HealthDisplay.Name = "HealthDisplay"
HealthDisplay.TextColor3 = Color3.fromRGB(255, 255, 255)
HealthDisplay.BorderColor3 = Color3.fromRGB(0, 0, 0)
HealthDisplay.Text = "100/100"
HealthDisplay.TextSize = 14
HealthDisplay.Size = UDim2.fromOffset(300, 25)
HealthDisplay.AnchorPoint = Vector2.new(0.5, 0)
HealthDisplay.Font = Enum.Font.SourceSans
HealthDisplay.BackgroundTransparency = 1
HealthDisplay.Position = UDim2.fromScale(0.5, 0)
HealthDisplay.BorderSizePixel = 0
HealthDisplay.ZIndex = 2
HealthDisplay.TextScaled = true
HealthDisplay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

local UIStroke = Instance.new("UIStroke")
UIStroke.Parent = HealthDisplay

local Display = Instance.new("TextLabel")
Display.TextWrapped = true
Display.Parent = Box
Display.TextColor3 = Color3.fromRGB(255, 255, 255)
Display.BorderColor3 = Color3.fromRGB(0, 0, 0)
Display.Text = "Obi_xieO(@ZJW9901)"
Display.Name = "Display"
Display.Size = UDim2.fromOffset(300, 25)
Display.AnchorPoint = Vector2.new(0.5, 0.8999999761581421)
Display.Font = Enum.Font.SourceSans
Display.BackgroundTransparency = 1
Display.Position = UDim2.fromScale(0.5, 0)
Display.BorderSizePixel = 0
Display.TextSize = 14
Display.TextScaled = true
Display.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

local UIStroke = Instance.new("UIStroke")
UIStroke.Parent = Display

local Infos = Instance.new("Frame")
Infos.BorderColor3 = Color3.fromRGB(0, 0, 0)
Infos.AnchorPoint = Vector2.new(1, 0)
Infos.Parent = Box
Infos.BackgroundTransparency = 1
Infos.Position = UDim2.fromOffset(0, 25)
Infos.Name = "Infos"
Infos.Size = UDim2.fromOffset(100, 100)
Infos.BorderSizePixel = 0
Infos.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Parent = Infos
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder

local Template = Instance.new("TextLabel")
Template.TextWrapped = true
Template.Parent = UIListLayout
Template.TextColor3 = Color3.fromRGB(255, 255, 255)
Template.BorderColor3 = Color3.fromRGB(0, 0, 0)
Template.Text = ""
Template.Name = "Template"
Template.Size = UDim2.fromScale(1, 0.20000000298023224)
Template.AnchorPoint = Vector2.new(0.5, 0)
Template.Font = Enum.Font.SourceSans
Template.BackgroundTransparency = 1
Template.Position = UDim2.fromScale(0.5, 0)
Template.BorderSizePixel = 0
Template.TextSize = 14
Template.TextScaled = true
Template.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

function EspLib:WrapObject(Args)
	Args.Configs = Args.Configs or {}
	if not Args.Object then return end
	Args = {
		Object = Args.Object,
		DisplayText = Args.DisplayText,
		Configs = {
			HealthBar = Args.Configs.HealthBar or true,
			Box = Args.Configs.Box or true,
		},
		RenderDistance = Args.RenderDistance or math.huge,
		Color = {
			Text = Args.Color.Text or Color3.fromRGB(255, 255, 255),
			Box = Args.Color.Box or Color3.fromRGB(255, 255, 255),
		},
		Infos = Args.Infos or {},
	}
	
	local NewUi = Main:Clone()
	
	NewUi.Box.UIStroke.Enabled = Args.Configs.Box
	
	local Object = Args.Object
	
	if Object:IsA("Model") then
		local Position,Size = Object:GetBoundingBox()
		NewUi.Size = UDim2.new(math.max(Size.X,Size.Z),300,Size.Y,200)
		
		if not Object:FindFirstChild("Humanoid") or not Args.Configs.HealthBar then
			NewUi.Box.HealthBar:Destroy()
			NewUi.Box.HealthDisplay:Destroy()
		else
			local Humanoid = Object:FindFirstChild("Humanoid")
			
			local HealthBar = NewUi.Box.HealthBar
			local HealthDisplay = NewUi.Box.HealthDisplay

			local function Update()
				local Health = Humanoid.Health
				local MaxHealth = Humanoid.MaxHealth

				HealthDisplay.Text = `{math.floor(Health*10)/10}/{math.floor(MaxHealth*10)/10}`
				HealthBar.Frame.Size = UDim2.fromScale(1,Health/MaxHealth)
			end

			Update()

			Humanoid:GetPropertyChangedSignal("Health"):Connect(Update)
			Humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(Update)
		end
	elseif Object:IsA("BasePart") then
		NewUi.Size = UDim2.new(math.max(Object.Size.X,Object.Size.Z),300,Object.Size.Y,200)
	end
	
	local TBL = {Ui = NewUi,Connections = {}}
	
	EspLib.Objects[Object] = TBL
	
	if Args.DisplayText then
		if typeof(Args.DisplayText) == "function" then
			TBL.TextConnect = game:GetService("RunService").RenderStepped:Connect(function()
				local Text = Args.DisplayText(Object)
				if Text then
					NewUi.Box.Display.Text = Text
				end
			end)
		else
			NewUi.Box.Display.Text = tostring(Args.DisplayText)
		end
	else
		NewUi.Box.Display.Text = Object.Name
	end
	
	local function ChangeColor(Obj,Color)
		if Obj:lower() == "text" then
			local function Update(Color)
				NewUi.Box.Display.TextColor3 = Color
				if NewUi.Box:FindFirstChild("HealthDisplay") then
					NewUi.Box.HealthDisplay.TextColor3 = Color
				end
			end
			
			if typeof(Color) == "function" then
				if TBL.TextColorConnect then
					TBL.TextColorConnect:Disconnect()
				end
				
				TBL.TextColorConnect = game:GetService("RunService").RenderStepped:Connect(function()
					Update(Color(Object))
				end)
			else
				Update(Color)
			end
		elseif Obj:lower() == "box" then
			local function Update(Color)
				NewUi.Box.UIStroke.Color = Color
			end
			
			if typeof(Color) == "function" then
				if TBL.BoxColorConnect then
					TBL.BoxColorConnect:Disconnect()
				end
				
				TBL.BoxColorConnect = game:GetService("RunService").RenderStepped:Connect(function()
					Update(Color(Object))
				end)
			else
				Update(Color)
			end
		end	
	end
	
	for i,v in pairs(Args.Infos) do
		local NewInfo = NewUi.Box.Infos.UIListLayout.Template:Clone()
		
		local function Update(Text,Color)
			NewInfo.Text = Text or ""
			NewInfo.TextColor3 = Color or Color3.new(1,1,1)
		end
		
		if typeof(v.Text) == "function" or typeof(v.Color) == "function" then
			table.insert(TBL.Connections,game:GetService("RunService").RenderStepped:Connect(function()
				Update(GetVal(v.Text,Object),GetVal(v.Color,Object))
			end))
		else
			Update(v.Text,v.Color)
		end
		
		NewInfo.Name = tostring(i)
	end
	
	ChangeColor("Text",Args.Color.Text)
	ChangeColor("Box",Args.Color.Box)
	
	Object.Destroying:Connect(function()
		EspLib:UnwrapObject(Object)
	end)
	
	NewUi.Parent = EspFolder
	NewUi.Adornee = Object
	
	return {
		ChangeColor = ChangeColor,
	}
end

function EspLib:UnwrapObject(Object)
	if not Object then return end
	
	local Obj = EspLib.Objects[Object]
	if not Obj then return end
	
	Obj.Ui:Destroy()
	
	if Obj.TextConnect then
		Obj.TextConnect:Disconnect()
	end
	if Obj.BoxColorConnect then
		Obj.BoxColorConnect:Disconnect()
	end
	
	if Obj.TextColorConnect then
		Obj.TextColorConnect:Disconnect()
	end
	
	for i,v in pairs(Obj.Connections) do
		v:Disconnect()
	end
	
	EspLib.Objects[Object] = nil
end

return EspLib
