local MIDIParser = {}
MIDIParser.__index = MIDIParser

local function readVarLength(stream, pos)
	if pos > #stream then return 0, pos end
	local value = 0
	local byte, count = nil, 0
	repeat
		count += 1
		if count > 4 then return value, pos end
		byte = string.byte(stream, pos)
		if not byte then return value, pos end
		pos += 1
		value = bit32.bor(bit32.lshift(value, 7), bit32.band(byte, 0x7F))
	until bit32.band(byte, 0x80) == 0
	return value, pos
end

local function readInt(stream, pos, length, bigEndian)
	if pos + length - 1 > #stream then return 0, pos end -- 容错
	local value = 0
	for i = 1, length do
		local byte = string.byte(stream, pos) or 0
		pos += 1
		if bigEndian then
			value = bit32.bor(bit32.lshift(value, 8), byte)
		else
			value = bit32.bor(value, bit32.lshift(byte, (i-1)*8))
		end
	end
	return value, pos
end

function MIDIParser.new(midiBinary)
	local self = setmetatable({}, MIDIParser)
	self.data = midiBinary
	self.pos = 1
	self.header = {ppq = 480, trackCount = 0}
	self.tracks = {}
	-- 容错：先校验文件是否有效
	if #self.data < 14 then error("无效的MIDI文件（长度过短）") end
	self:parseHeader()
	self:parseAllTracks()
	return self
end

function MIDIParser:parseHeader()
	local chunkType = string.sub(self.data, self.pos, self.pos+3)
	self.pos += 4
	if chunkType ~= "MThd" then
		warn("非标准MIDI文件头，尝试继续解析")
		self.pos = 1
		for i = 1, #self.data - 3 do
			if string.sub(self.data, i, i+3) == "MThd" then
				self.pos = i + 4
				break
			end
		end
	end

	local headerLen, newPos = readInt(self.data, self.pos, 4, true)
	self.pos = newPos
	headerLen = math.min(headerLen, 6)

	local fmt, pos1 = readInt(self.data, self.pos, 2, true)
	self.pos = pos1
	local trackCount, pos2 = readInt(self.data, self.pos, 2, true)
	self.pos = pos2
	local timeDiv, pos3 = readInt(self.data, self.pos, 2, true)
	self.pos = pos3

	self.header.formatType = fmt
	self.header.trackCount = trackCount
	if bit32.band(timeDiv, 0x8000) == 0 then
		self.header.ppq = timeDiv
	else
		self.header.ppq = 480
	end

	local extraHeaderBytes = headerLen - 6
	if extraHeaderBytes > 0 then
		self.pos = math.min(self.pos + extraHeaderBytes, #self.data)
	end
end

function MIDIParser:parseTrack()
	local track = {events = {}}
	local trackStartPos = self.pos

	if self.pos + 7 > #self.data then
		warn("轨道数据不足，跳过解析")
		table.insert(self.tracks, track)
		return track
	end

	local chunkType = string.sub(self.data, self.pos, self.pos+3)
	self.pos += 4

	if chunkType ~= "MTrk" then
		warn("轨道标识错误（非MTrk），尝试自动修复")
		local foundPos = -1
		for i = self.pos, #self.data - 3 do
			if string.sub(self.data, i, i+3) == "MTrk" then
				foundPos = i
				break
			end
		end
		if foundPos == -1 then
			table.insert(self.tracks, track)
			return track
		end
		self.pos = foundPos
		chunkType = string.sub(self.data, self.pos, self.pos+3)
		self.pos += 4
	end

	local trackLen, newPos = readInt(self.data, self.pos, 4, true)
	self.pos = newPos
	local trackEndPos = math.min(self.pos + trackLen, #self.data) -- 容错：避免越界

	local runningStatus = nil
	while self.pos < trackEndPos do
		local deltaTime, pos1 = readVarLength(self.data, self.pos)
		self.pos = pos1

		local eventType = string.byte(self.data, self.pos) or 0
		self.pos += 1

		if eventType < 0x80 then
			runningStatus = runningStatus or eventType
			self.pos -= 1
			eventType = runningStatus or 0
		else
			runningStatus = eventType
		end

		local event = {deltaTime = deltaTime, type = eventType}

		if bit32.band(eventType, 0xF0) == 0x80 or bit32.band(eventType, 0xF0) == 0x90 then
			event.channel = bit32.band(eventType, 0x0F)
			event.note = string.byte(self.data, self.pos) or 0
			self.pos += 1
			event.velocity = string.byte(self.data, self.pos) or 0
			self.pos += 1
			event.name = bit32.band(eventType, 0xF0) == 0x90 and "NOTE_ON" or "NOTE_OFF"
			table.insert(track.events, event)
		elseif eventType == 0xFF then
			local metaType = string.byte(self.data, self.pos) or 0
			self.pos += 1
			local metaLen, pos2 = readVarLength(self.data, self.pos)
			self.pos = pos2
			local metaData = string.sub(self.data, self.pos, self.pos + metaLen - 1) or ""
			self.pos += metaLen

			if metaType == 0x51 and metaLen == 3 then
				local mpqn = readInt(metaData, 1, 3, true)
				event.bpm = mpqn > 0 and 60000000 / mpqn or 120
				table.insert(track.events, event)
			elseif metaType == 0x2F then
				break
			end

		else
			local dataLen = bit32.band(eventType, 0xF0) >= 0xC0 and 1 or 2
			self.pos = math.min(self.pos + dataLen, trackEndPos)
		end
	end

	table.insert(self.tracks, track)
	return track
end

function MIDIParser:parseAllTracks()
	local targetTrackCount = self.header.trackCount or 1
	targetTrackCount = math.min(targetTrackCount, 16)
	for i = 1, targetTrackCount do
		if self.pos >= #self.data then break end
		self:parseTrack()
	end
	if #self.tracks == 0 then
		table.insert(self.tracks, {events = {}})
	end
end

return function(midiBinary)
	local success, parser = pcall(function()
		return MIDIParser.new(midiBinary)
	end)
	if not success then
		warn("MIDI解析失败：" .. parser)
		return {
			header = {ppq = 480, trackCount = 1},
			tracks = {{events = {}}}
		}
	end
	return {
		header = parser.header,
		tracks = parser.tracks
	}
end
