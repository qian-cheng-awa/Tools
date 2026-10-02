--[[
    LuaSyntaxHighlighter (CodeFrame 版本提取)
    
    功能：
      - 将 Lua 源码文本按行高亮
      - 支持关键字、内置函数、字符串、注释（含跨行）、数字、运算符、
        函数调用、方法调用、属性访问等
      - 输出 RichText 字符串（<font color="rgb(...)">...</font>）
    
    API：
      local HL = require(module)
      local hl = HL.new({ Colors = {...} })   -- 可选，覆盖默认配色
      hl:SetText(source)                       -- 设置源码（自动分行）
      hl:GetText()                             -- 取回源码
      hl:HighlightLine(lineIndex)              -- 返回该行的 { [列号] = 类型编号 }
      hl:GetRichLine(lineIndex)                -- 返回该行的 RichText 字符串（整行，无滚动裁剪）
      hl:GetRichLines()                        -- 返回所有行的 RichText 数组
      hl:ApplyTheme(colors)                    -- 更新配色
]]

local Highlighter = {}

--============================================================
-- 常量 / 类型映射
--============================================================

local typeMap = {
	[1]  = "String",
	[2]  = "String",
	[3]  = "String",        -- 长字符串 [[ ]]
	[4]  = "Comment",
	[5]  = "Operator",
	[6]  = "Number",
	[7]  = "Keyword",
	[8]  = "BuiltIn",
	[9]  = "LocalMethod",
	[10] = "LocalProperty",
	[11] = "Nil",
	[12] = "Bool",
	[13] = "Function",
	[14] = "Local",
	[15] = "Self",
	[16] = "FunctionName",
	[17] = "Bracket",
}

local specialKeywordsTypes = {
	["nil"]      = 11,
	["true"]     = 12,
	["false"]    = 12,
	["function"] = 13,
	["local"]    = 14,
	["self"]     = 15,
}

local keywords = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
	["elseif"] = true, ["end"] = true, ["const"] = true, ["false"] = true,
	["for"] = true, ["function"] = true, ["if"] = true, ["in"] = true,
	["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
	["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
	["until"] = true, ["while"] = true, ["plugin"] = true,
}

-- 内置函数/库（静态部分，后面会动态补全环境里的表）
local builtIns = {
	-- 基础函数
	["delay"] = true, ["elapsedTime"] = true, ["require"] = true, ["spawn"] = true,
	["tick"] = true, ["time"] = true, ["typeof"] = true, ["UserSettings"] = true,
	["wait"] = true, ["warn"] = true, ["game"] = true, ["shared"] = true,
	["script"] = true, ["workspace"] = true, ["assert"] = true, ["collectgarbage"] = true,
	["error"] = true, ["getfenv"] = true, ["getmetatable"] = true, ["ipairs"] = true,
	["loadstring"] = true, ["newproxy"] = true, ["next"] = true, ["pairs"] = true,
	["pcall"] = true, ["print"] = true, ["rawequal"] = true, ["rawget"] = true,
	["rawset"] = true, ["select"] = true, ["setfenv"] = true, ["setmetatable"] = true,
	["tonumber"] = true, ["tostring"] = true, ["type"] = true, ["unpack"] = true,
	["xpcall"] = true, ["_G"] = true, ["_VERSION"] = true,
	-- 库
	["coroutine"] = true, ["debug"] = true, ["math"] = true, ["os"] = true,
	["string"] = true, ["table"] = true, ["bit32"] = true, ["utf8"] = true,
	-- Roblox 数据类型
	["Axes"] = true, ["BrickColor"] = true, ["CFrame"] = true, ["Color3"] = true,
	["ColorSequence"] = true, ["ColorSequenceKeypoint"] = true, ["DockWidgetPluginGuiInfo"] = true,
	["Enum"] = true, ["Faces"] = true, ["Instance"] = true, ["NumberRange"] = true,
	["NumberSequence"] = true, ["NumberSequenceKeypoint"] = true, ["PathWaypoint"] = true,
	["PhysicalProperties"] = true, ["Random"] = true, ["Ray"] = true, ["Rect"] = true,
	["Region3"] = true, ["Region3int16"] = true, ["TweenInfo"] = true, ["UDim"] = true,
	["UDim2"] = true, ["Vector2"] = true, ["Vector2int16"] = true, ["Vector3"] = true,
	["Vector3int16"] = true,
	-- 执行器函数
	["getgenv"] = true, ["getrenv"] = true, ["getsenv"] = true, ["getgc"] = true,
	["getreg"] = true, ["filtergc"] = true, ["saveinstave"] = true, ["decompile"] = true,
	["syn"] = true, ["getupvalue"] = true, ["getupvalues"] = true, ["setupvalue"] = true,
	["getstack"] = true, ["setstack"] = true, ["getconstants"] = true, ["getconstant"] = true,
	["setconstant"] = true, ["getproto"] = true, ["getprotos"] = true, ["checkcaller"] = true,
	["clonefunction"] = true, ["cloneref"] = true, ["getfunctionhash"] = true, ["gethwid"] = true,
	["hookfunction"] = true, ["hookmetamethod"] = true, ["iscclosure"] = true, ["islclosure"] = true,
	["newcclosure"] = true, ["isexecutorclosure"] = true, ["restorefunction"] = true, ["crypt"] = true,
	["Drawing"] = true,
}

local builtInInited = false

-- RichText 转义
local richReplace = {
	["'"] = "&apos;",
	['"'] = "&quot;",
	["<"] = "&lt;",
	[">"] = "&gt;",
	["&"] = "&amp;",
}

-- Tab 处理用特殊占位符（保持与原版一致的逻辑）
local tabSub = "\205"
local tabReplacement = (" %s%s "):format(tabSub, tabSub)

local tabJumps = {
	[("[^%s] %s"):format(tabSub, tabSub)] = 0,
	[(" %s%s"):format(tabSub, tabSub)] = -1,
	[("%s%s "):format(tabSub, tabSub)] = 2,
	[("%s [^%s]"):format(tabSub, tabSub)] = 1,
}

--============================================================
-- 默认配色（与原版一致）
--============================================================

local DEFAULT_COLORS = {
	Text           = Color3.fromRGB(204, 204, 204),
	Background     = Color3.fromRGB(36, 36, 36),
	Selection      = Color3.fromRGB(255, 255, 255),
	SelectionBack  = Color3.fromRGB(11, 90, 175),
	Operator       = Color3.fromRGB(204, 204, 204),
	Number         = Color3.fromRGB(255, 198, 0),
	String         = Color3.fromRGB(173, 241, 149),
	Comment        = Color3.fromRGB(102, 102, 102),
	Keyword        = Color3.fromRGB(248, 109, 124),
	Error          = Color3.fromRGB(255, 0, 0),
	FindBackground = Color3.fromRGB(141, 118, 0),
	MatchingWord   = Color3.fromRGB(85, 85, 85),
	BuiltIn        = Color3.fromRGB(132, 214, 247),
	CurrentLine    = Color3.fromRGB(45, 50, 65),
	LocalMethod    = Color3.fromRGB(253, 251, 172),
	LocalProperty  = Color3.fromRGB(97, 161, 241),
	Nil            = Color3.fromRGB(255, 198, 0),
	Bool           = Color3.fromRGB(255, 198, 0),
	Function       = Color3.fromRGB(248, 109, 124),
	Local          = Color3.fromRGB(248, 109, 124),
	Self           = Color3.fromRGB(248, 109, 124),
	FunctionName   = Color3.fromRGB(253, 251, 172),
	Bracket        = Color3.fromRGB(204, 204, 204),
}

--============================================================
-- 初始化内置表
--============================================================

local function initBuiltIn()
	local env = getfenv and getfenv() or _G
	for name in next, builtIns do
		local envVal = env[name]
		if type(envVal) == "table" then
			local items = {}
			for i, v in next, envVal do
				items[i] = true
			end
			builtIns[name] = items
		end
	end

	-- 将 Enum 全部枚举名加入
	local ok, enums = pcall(function() return Enum:GetEnums() end)
	if ok and enums then
		local enumEntries = {}
		for i = 1, #enums do
			enumEntries[tostring(enums[i])] = true
		end
		builtIns["Enum"] = enumEntries
	end

	builtInInited = true
end

--============================================================
-- 元表 / 方法
--============================================================

local funcs = {}
local mt = { __index = funcs }

--===== 内部：分行 =====
function funcs._splitLines(self, text)
	local lines = {}
	local count = 1
	-- 兼容 \r\n
	text = text:gsub("\r\n", "\n")
	for line in text:gmatch("([^\n]*)\n?") do
		lines[count] = line
		count = count + 1
	end
	-- gmatch 可能多出一行空串，去掉末尾多余
	if #lines > 1 and lines[#lines] == "" and text:sub(-1) == "\n" then
		lines[#lines] = nil
	end
	return lines
end

--===== 内部：构造 RichText 模板 =====
function funcs.MakeRichTemplates(self)
	local floor = math.floor
	local templates = {}
	for name, color in pairs(self.Colors) do
		templates[name] = ('<font color="rgb(%s,%s,%s)">'):format(
			floor(color.r * 255), floor(color.g * 255), floor(color.b * 255))
	end
	self.RichTemplates = templates
end

--===== 内部：Tab 调整（让 Tab 视觉宽度对齐）=====
function funcs.TabAdjust(self, x, y)
	local line = self.Lines[y + 1]
	x = x + 1
	if line then
		local left   = line:sub(x - 1, x - 1)
		local middle = line:sub(x, x)
		local right  = line:sub(x + 1, x + 1)
		local selRange = (#left > 0 and left or " ")
			.. (#middle > 0 and middle or " ")
			.. (#right > 0 and right or " ")
		for i, v in pairs(tabJumps) do
			if selRange:find(i) then
				return v
			end
		end
	end
	return 0
end

--===== 内部：建立换行索引 =====
function funcs._mapNewLines(self)
	local newLines = {}
	local count = 1
	local text = self.Text
	local find = string.find
	local init = 1
	local pos = find(text, "\n", init, true)
	while pos do
		newLines[count] = pos
		count = count + 1
		init = pos + 1
		pos = find(text, "\n", init, true)
	end
	self.NewLines = newLines
end

--===== 预处理：跨行字符串/注释 =====
function funcs.PreHighlight(self)
	local text = self.Text:gsub("\\\\", "  ")
	local textLen = #text
	local found, foundMap, extras = {}, {}, {}
	local find = string.find
	local sub = string.sub
	self.ColoredLines = {}

	local function findAll(str, pattern, typ, raw)
		local count = #found + 1
		local init = 1
		local x, y, extra = find(str, pattern, init, raw)
		while x do
			found[count] = x
			foundMap[x] = typ
			if extra then extras[x] = extra end
			count = count + 1
			init = y + 1
			x, y, extra = find(str, pattern, init, raw)
		end
	end

	-- 1 = " 双引号字符串   2 = ' 单引号字符串   3 = [[长串   4 = -- 注释
	findAll(text, '"', 1, true)
	findAll(text, "'", 2, true)
	findAll(text, "%[(=*)%[", 3)
	findAll(text, "--", 4, true)
	table.sort(found)

	local newLines = self.NewLines
	local curLine = 0
	local lineEnd = 0
	local lastEnding = 0
	local foundHighlights = {}

	for i = 1, #found do
		local pos = found[i]
		if pos <= lastEnding then continue end

		local ending = pos
		local typ = foundMap[pos]

		if typ == 1 then
			ending = find(text, '"', pos + 1, true)
			while ending and sub(text, ending - 1, ending - 1) == "\\" do
				ending = find(text, '"', ending + 1, true)
			end
			if not ending then ending = textLen end
		elseif typ == 2 then
			ending = find(text, "'", pos + 1, true)
			while ending and sub(text, ending - 1, ending - 1) == "\\" do
				ending = find(text, "'", ending + 1, true)
			end
			if not ending then ending = textLen end
		elseif typ == 3 then
			_, ending = find(text, "]" .. extras[pos] .. "]", pos + 1, true)
			if not ending then ending = textLen end
		elseif typ == 4 then
			local ahead = foundMap[pos + 2]
			if ahead == 3 then
				_, ending = find(text, "]" .. extras[pos + 2] .. "]", pos + 1, true)
				if not ending then ending = textLen end
			else
				ending = find(text, "\n", pos + 1, true) or textLen
			end
		end

		while pos > lineEnd do
			curLine = curLine + 1
			lineEnd = newLines[curLine] or textLen + 1
		end

		while true do
			local lineTable = foundHighlights[curLine]
			if not lineTable then lineTable = {} foundHighlights[curLine] = lineTable end
			lineTable[pos] = {typ, ending}

			if ending > lineEnd then
				curLine = curLine + 1
				lineEnd = newLines[curLine] or textLen + 1
			else
				break
			end
		end

		lastEnding = ending
	end

	self.PreHighlights = foundHighlights
end

--===== 单行高亮：返回 { [col] = typeNum } =====
function funcs.HighlightLine(self, line)
	local cached = self.ColoredLines[line]
	if cached then return cached end

	local sub   = string.sub
	local find  = string.find
	local match = string.match
	local highlights = {}
	local preHighlights = self.PreHighlights[line] or {}
	local lineText = self.Lines[line] or ""
	local lastEnding = 0
	local currentType = 0
	local lastWord = nil
	local wordBeginsDotted = false
	local funcStatus = 0
	local lineStart = self.NewLines[line - 1] or 0

	local preHighlightMap = {}
	for pos, data in next, preHighlights do
		local relativePos = pos - lineStart
		if relativePos < 1 then
			currentType = data[1]
			lastEnding = data[2] - lineStart
		else
			preHighlightMap[relativePos] = {data[1], data[2] - lineStart}
		end
	end

	for col = 1, #lineText do
		if col <= lastEnding then
			highlights[col] = currentType
			continue
		end

		local pre = preHighlightMap[col]
		if pre then
			currentType = pre[1]
			lastEnding = pre[2]
			highlights[col] = currentType
			wordBeginsDotted = false
			lastWord = nil
			funcStatus = 0
		else
			local char = sub(lineText, col, col)
			if find(char, "[%a_]") then
				local word = match(lineText, "[%a%d_]+", col)
				local wordType = (keywords[word] and 7) or (builtIns[word] and 8)

				lastEnding = col + #word - 1

				if wordType ~= 7 then
					if wordBeginsDotted then
						local prevBuiltIn = lastWord and builtIns[lastWord]
						wordType = (prevBuiltIn and type(prevBuiltIn) == "table"
							and prevBuiltIn[word] and 8) or 10
					end

					if wordType ~= 8 then
						local x, y, br = find(lineText, "^%s*([%({\"'])", lastEnding + 1)
						if x then
							wordType = (funcStatus > 0 and br == "(" and 16) or 9
							funcStatus = 0
						end
					end
				else
					wordType = specialKeywordsTypes[word] or wordType
					funcStatus = (word == "function" and 1 or 0)
				end

				lastWord = word
				wordBeginsDotted = false
				if funcStatus > 0 then funcStatus = 1 end

				if wordType then
					currentType = wordType
					highlights[col] = currentType
				else
					currentType = nil
				end
			elseif find(char, "%p") then
				local isDot = (char == ".")
				local isNum = isDot and find(sub(lineText, col + 1, col + 1), "%d")
				highlights[col] = (isNum and 6 or 5)

				if not isNum then
					local dotStr = isDot and match(lineText, "%.%.?%.?", col)
					if dotStr and #dotStr > 1 then
						currentType = 5
						lastEnding = col + #dotStr - 1
						wordBeginsDotted = false
						lastWord = nil
						funcStatus = 0
					else
						if isDot then
							if wordBeginsDotted then
								lastWord = nil
							else
								wordBeginsDotted = true
							end
						else
							wordBeginsDotted = false
							lastWord = nil
						end
						funcStatus = ((isDot or char == ":") and funcStatus == 1 and 2) or 0
					end
				end
			elseif find(char, "%d") then
				local _, endPos = find(lineText, "%x+", col)
				local endPart = sub(lineText, endPos, endPos + 1)
				if (endPart == "e+" or endPart == "e-")
					and find(sub(lineText, endPos + 2, endPos + 2), "%d") then
					endPos = endPos + 1
				end
				currentType = 6
				lastEnding = endPos
				highlights[col] = 6
				wordBeginsDotted = false
				lastWord = nil
				funcStatus = 0
			else
				highlights[col] = currentType
				local _, endPos = find(lineText, "%s+", col)
				if endPos then lastEnding = endPos end
			end
		end
	end

	self.ColoredLines[line] = highlights
	return highlights
end

--===== 公开：取某行 RichText（整行，无滚动裁剪）=====
function funcs.GetRichLine(self, lineIndex)
	local lineText = self.Lines[lineIndex] or ""
	if #lineText == 0 then return "" end

	local highlights = self:HighlightLine(lineIndex)
	local gsub = string.gsub
	local sub  = string.sub
	local richTemplates = self.RichTemplates
	local textTemplate = richTemplates.Text

	local resText = ""
	local colStart = 1
	local curType = highlights[1]
	local curTemplate = richTemplates[typeMap[curType]] or textTemplate

	for col = 2, #lineText do
		local posType = highlights[col]
		if posType ~= curType then
			local template = richTemplates[typeMap[posType]] or textTemplate
			if template ~= curTemplate then
				local nextText = gsub(sub(lineText, colStart, col - 1), "['\"<>&]", richReplace)
				resText = resText .. (curTemplate ~= textTemplate and (curTemplate .. nextText .. "</font>") or nextText)
				colStart = col
				curTemplate = template
			end
			curType = posType
		end
	end

	local lastText = gsub(sub(lineText, colStart, #lineText), "['\"<>&]", richReplace)
	if #lastText > 0 then
		resText = resText
			.. (curTemplate ~= textTemplate and (curTemplate .. lastText .. "</font>") or lastText)
	end

	return resText
end

--===== 公开：取所有行 RichText =====
function funcs.GetRichLines(self)
	local out = {}
	for i = 1, #self.Lines do
		out[i] = self:GetRichLine(i)
	end
	return out
end

--===== 公开：设置文本 =====
function funcs.SetText(self, txt)
	txt = txt:gsub("\r\n", "\n")
	self.Text = txt
	self.Lines = self:_splitLines(txt)
	if #self.Lines == 0 then self.Lines = {""} end
	self:_mapNewLines()
	self:PreHighlight()
end

--===== 公开：取回文本 =====
function funcs.GetText(self)
	return table.concat(self.Lines, "\n")
end

--===== 公开：更新配色 =====
function funcs.ApplyTheme(self, colors)
	if colors then
		for k, v in pairs(colors) do
			self.Colors[k] = v
		end
	end
	self:MakeRichTemplates()
end

--===== 公开：重新分析（文本已改变后调用）=====
function funcs.Refresh(self)
	self.ColoredLines = {}
	self:_mapNewLines()
	self:PreHighlight()
end

--============================================================
-- 构造器
--============================================================

function Highlighter.new(opts)
	opts = opts or {}
	if not builtInInited then initBuiltIn() end

	local self = setmetatable({}, mt)
	self.Colors = {}
	for k, v in pairs(DEFAULT_COLORS) do
		self.Colors[k] = v
	end
	if opts.Colors then
		for k, v in pairs(opts.Colors) do
			self.Colors[k] = v
		end
	end

	self.Lines = {""}
	self.Text = ""
	self.NewLines = {}
	self.ColoredLines = {}
	self.PreHighlights = {}
	self.RichTemplates = {}

	self:MakeRichTemplates()
	return self
end

Highlighter.typeMap = typeMap
Highlighter.keywords = keywords
Highlighter.builtIns = builtIns
Highlighter.DEFAULT_COLORS = DEFAULT_COLORS

return Highlighter
