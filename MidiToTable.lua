local MIDIParser = {}
MIDIParser.__index = MIDIParser

local function readVarLength(stream, pos)
	if pos > #stream then error("数据流越界") end
	local value = 0
	local byte, count = nil, 0
	repeat
		count += 1
		if count > 4 then error("可变长度整数超过4字节（无效MIDI）") end
		byte = string.byte(stream, pos)
		if not byte then error("数据流截断") end
		pos += 1
		value = bit32.bor(bit32.lshift(value, 7), bit32.band(byte, 0x7F))
	until bit32.band(byte, 0x80) == 0
	return value, pos
end

local function readInt(stream, pos, length, bigEndian)
	if pos + length - 1 > #stream then error("整数读取越界") end
	local value = 0
	for i = 1, length do
		local byte = string.byte(stream, pos)
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
	self.header = {ppq = 480}
	self.tracks = {}
	self:parseHeader()
	self:parseAllTracks()
	return self
end

function MIDIParser:parseHeader()
	local chunkType = string.sub(self.data, self.pos, self.pos+3)
	self.pos += 4
	if chunkType ~= "MThd" then error("非标准MIDI文件") end

	local headerLen = readInt(self.data, self.pos, 4, true)
	self.pos += 4
	if headerLen ~= 6 then warn("非标准MIDI头，强制按6字节解析") end

	self.header.formatType = readInt(self.data, self.pos, 2, true)
	self.pos += 2
	self.header.trackCount = readInt(self.data, self.pos, 2, true)
	self.pos += 2
	local timeDiv = readInt(self.data, self.pos, 2, true)
	self.pos += 2

	if bit32.band(timeDiv, 0x8000) == 0 then
		self.header.ppq = timeDiv
	else
		self.header.ppq = 480
	end
end

function MIDIParser:parseTrack()
	local track = {events = {}}
	local trackStartPos = self.pos

	local chunkType = string.sub(self.data, self.pos, self.pos+3)
	self.pos += 4
	if chunkType ~= "MTrk" then error("轨道标识错误") end

	local trackLen = readInt(self.data, self.pos, 4, true)
	self.pos += 4
	local trackEndPos = self.pos + trackLen

	local runningStatus = nil
	while self.pos < trackEndPos do
		local deltaTime, newPos = readVarLength(self.data, self.pos)
		self.pos = newPos

		local eventType = string.byte(self.data, self.pos)
		self.pos += 1

		if eventType < 0x80 then
			runningStatus = runningStatus or eventType
			self.pos -= 1
			eventType = runningStatus
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
			local metaLen, newPos = readVarLength(self.data, self.pos)
			self.pos = newPos
			local metaData = string.sub(self.data, self.pos, self.pos + metaLen - 1)
			self.pos += metaLen

			if metaType == 0x51 and metaLen == 3 then
				local mpqn = readInt(metaData, 1, 3, true)
				event.bpm = 60000000 / mpqn
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
	for i = 1, self.header.trackCount do
		self:parseTrack()
	end
end


return function(midiBinary)
	local parser = MIDIParser.new(midiBinary)
	return {
		header = parser.header,
		tracks = parser.tracks
	}
end
