local AssetService = game:GetService("AssetService")

local ObjDecoder = {}

type Vertex = { x: number, y: number, z: number }
type TexCoord = { u: number, v: number }
type Normal = { x: number, y: number, z: number }
type FaceVertex = { v: number, vt: number?, vn: number? }

-- ============================================================
-- 解析 OBJ 文本
-- ============================================================
function ObjDecoder.parse(objText: string)
	local vertices: { Vertex } = {}
	local texCoords: { TexCoord } = {}
	local normals: { Normal } = {}
	local faces: { { FaceVertex } } = {}

	for line in objText:gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$")
		if line == "" or line:sub(1, 1) == "#" then
			continue
		end

		local prefix, rest = line:match("^(%S+)%s+(.+)$")
		if not prefix then continue end

		if prefix == "v" then
			local x, y, z = rest:match("([^%s]+)%s+([^%s]+)%s+([^%s]+)")
			if x and y and z then
				table.insert(vertices, {
					x = tonumber(x) or 0,
					y = tonumber(y) or 0,
					z = tonumber(z) or 0,
				})
			end
		elseif prefix == "vt" then
			local u, v = rest:match("([^%s]+)%s+([^%s]+)")
			if u and v then
				table.insert(texCoords, {
					u = tonumber(u) or 0,
					v = tonumber(v) or 0,
				})
			end
		elseif prefix == "vn" then
			local x, y, z = rest:match("([^%s]+)%s+([^%s]+)%s+([^%s]+)")
			if x and y and z then
				table.insert(normals, {
					x = tonumber(x) or 0,
					y = tonumber(y) or 0,
					z = tonumber(z) or 0,
				})
			end
		elseif prefix == "f" then
			local face: { FaceVertex } = {}
			for token in rest:gmatch("%S+") do
				local v, vt, vn = token:match("^(%d+)/(%d*)/(%d*)$")
				if not v then
					v, vt, vn = token:match("^(%d+)//(%d+)$")
				end
				if not v then
					v, vt, vn = token:match("^(%d+)/(%d+)$")
				end
				if not v then
					v = token:match("^(%d+)$")
				end

				if v then
					table.insert(face, {
						v = tonumber(v) or 1,
						vt = vt and tonumber(vt) or nil,
						vn = vn and tonumber(vn) or nil,
					})
				end
			end
			if #face >= 3 then
				table.insert(faces, face)
			end
		end
	end

	return {
		vertices = vertices,
		texCoords = texCoords,
		normals = normals,
		faces = faces,
	}
end
-- ============================================================
-- 三角形外扩
-- ============================================================
local function inflateTriangle(A, B, C, ratio)
	if ratio == 1.0 then return A, B, C end
	local cx = (A + B + C) / 3
	return
		cx + (A - cx) * ratio,
		cx + (B - cx) * ratio,
		cx + (C - cx) * ratio
end
-- ============================================================
-- 三角化
-- ============================================================
function ObjDecoder.triangulate(faces)
	local triangles = {}
	for _, face in ipairs(faces) do
		for i = 2, #face - 1 do
			table.insert(triangles, {
				face[1],
				face[i],
				face[i + 1],
			})
		end
	end
	return triangles
end

-- ============================================================
-- 统计三角形数量
-- ============================================================
function ObjDecoder.countTriangles(parsed)
	local triangleCount = 0
	for _, face in ipairs(parsed.faces) do
		triangleCount += math.max(0, #face - 2)
	end

	return {
		vertexCount   = #parsed.vertices,
		faceCount     = #parsed.faces,
		triangleCount = triangleCount,
	}
end

-- ============================================================
-- 计算包围盒
-- ============================================================
function ObjDecoder.getBounds(parsed, scale)
	scale = scale or 1

	if #parsed.vertices == 0 then
		return {
			min    = Vector3.zero,
			max    = Vector3.zero,
			center = Vector3.zero,
			size   = Vector3.zero,
			offset = Vector3.zero,
		}
	end

	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

	for _, v in ipairs(parsed.vertices) do
		local x, y, z = v.x * scale, v.y * scale, v.z * scale
		if x < minX then minX = x end
		if y < minY then minY = y end
		if z < minZ then minZ = z end
		if x > maxX then maxX = x end
		if y > maxY then maxY = y end
		if z > maxZ then maxZ = z end
	end

	local minV = Vector3.new(minX, minY, minZ)
	local maxV = Vector3.new(maxX, maxY, maxZ)
	local center = (minV + maxV) * 0.5
	local size = maxV - minV

	return {
		min    = minV,
		max    = maxV,
		center = center,
		size   = size,
		offset = -center,
	}
end

-- ============================================================
-- 获取世界坐标三角形
-- ============================================================
function ObjDecoder.getTrianglesWorld(parsed, scale, recenter, applyOffset)
	scale = scale or 1
	recenter = recenter or false
	applyOffset = applyOffset or Vector3.zero

	local bounds = ObjDecoder.getBounds(parsed, scale)
	local originOffset = recenter and bounds.offset or Vector3.zero
	local totalOffset = originOffset + applyOffset

	local worldVerts = table.create(#parsed.vertices)
	for i, v in ipairs(parsed.vertices) do
		worldVerts[i] = Vector3.new(
			v.x * scale,
			v.y * scale,
			v.z * scale
		) + totalOffset
	end

	local triangles = {}
	for _, face in ipairs(parsed.faces) do
		for i = 2, #face - 1 do
			local a = worldVerts[face[1].v]
			local b = worldVerts[face[i].v]
			local c = worldVerts[face[i + 1].v]
			if a and b and c then
				table.insert(triangles, { a, b, c })
			end
		end
	end

	return {
		triangles = triangles,
		info = {
			count  = #triangles,
			bounds = bounds,
		},
	}
end

-- ============================================================
-- 计算单个三角形的 2-Wedge 数据
-- 返回 { data1, data2 }（可能为空）
-- ============================================================
local function computeTwoWedges(A, B, C, thickness)
	local ab2 = (B - A).Magnitude ^ 2
	local bc2 = (C - B).Magnitude ^ 2
	local ca2 = (A - C).Magnitude ^ 2

	local apex, p1, p2
	if bc2 >= ab2 and bc2 >= ca2 then
		apex, p1, p2 = A, B, C
	elseif ca2 >= ab2 then
		apex, p1, p2 = B, C, A
	else
		apex, p1, p2 = C, A, B
	end

	local baseDir = p2 - p1
	local baseLen = baseDir.Magnitude
	if baseLen < 1e-6 then return {} end
	local uBase = baseDir / baseLen

	local t = (apex - p1):Dot(uBase)
	local D = p1 + uBase * t
	local h = (apex - D).Magnitude
	if h < 1e-6 then return {} end

	local N = (B - A):Cross(C - A)
	if N.Magnitude < 1e-9 then return {} end
	N = N.Unit

	local lenP1 = (p1 - D).Magnitude
	local lenP2 = (p2 - D).Magnitude
	if lenP1 < 1e-6 or lenP2 < 1e-6 then return {} end

	local uApex = (apex - D) / h
	local uP1 = (p1 - D) / lenP1
	local uP2 = (p2 - D) / lenP2

	local function buildData(ea, La, eb, Lb)
		local z = ea:Cross(eb)
		if z:Dot(N) < 0 then
			ea, eb = eb, ea
			La, Lb = Lb, La
			z = ea:Cross(eb)
		end

		local center = D
			+ ea * (La * 0.5)
			+ eb * (Lb * 0.5)
			+ z  * (thickness * 0.5)

		local cframe = CFrame.fromMatrix(center, z, ea, eb)
			* CFrame.Angles(0, math.rad(180), 0)

		return {
			cframe   = cframe,
			position = center,
			size     = Vector3.new(thickness, La, Lb),
			rotation = cframe.Rotation,
		}
	end

	return {
		buildData(uApex, h, uP1, lenP1),
		buildData(uP2, lenP2, uApex, h),
	}
end

-- ============================================================
-- 返回所有 Wedge 的 CFrame / Size
--
-- options:
--   scale        : number
--   thickness    : number
--   inflate      : number
--   recenter     : bool
--   maxTriangles : number
--   stride       : number
--
-- 返回：
--   {
--     parts = { { cframe, position, size, rotation }, ... },
--     info  = { count, bounds, originOffset }
--   }
-- ============================================================
function ObjDecoder.getWedgeData(parsed, options)
	options = options or {}
	local scale        = options.scale or 1
	local thickness    = options.thickness or 0
	local inflate      = options.inflate or 1
	local recenter     = options.recenter or false
	local maxTriangles = options.maxTriangles or math.huge
	local stride       = math.max(1, options.stride or 1)

	local bounds = ObjDecoder.getBounds(parsed, scale)
	local originOffset = recenter and bounds.offset or Vector3.zero

	local worldVerts = table.create(#parsed.vertices)
	for i, v in ipairs(parsed.vertices) do
		worldVerts[i] = Vector3.new(v.x * scale, v.y * scale, v.z * scale) + originOffset
	end

	local function inflateTri(A, B, C)
		if inflate == 1.0 then return A, B, C end
		local cx = (A + B + C) / 3
		return
			cx + (A - cx) * inflate,
			cx + (B - cx) * inflate,
			cx + (C - cx) * inflate
	end

	local result = {}
	local faceIndex = 0
	local reachedLimit = false

	for _, face in ipairs(parsed.faces) do
		if reachedLimit then break end
		for i = 2, #face - 1 do
			faceIndex += 1
			if (faceIndex - 1) % stride == 0 then
				local a = worldVerts[face[1].v]
				local b = worldVerts[face[i].v]
				local c = worldVerts[face[i + 1].v]
				if a and b and c then
					local a2, b2, c2 = inflateTri(a, b, c)

					local list = computeTwoWedges(a2, b2, c2, thickness)
					for _, d in ipairs(list) do
						table.insert(result, d)
						if #result >= maxTriangles * 2 then
							reachedLimit = true
							break
						end
					end
				end
			end
		end
	end

	return {
		parts = result,
		info = {
			count        = #result,
			bounds       = bounds,
			originOffset = originOffset,
		},
	}
end
function ObjDecoder.createPreciseWedgeParts(parsed, options)
	options = options or {}
	local parent     = options.parent or workspace
	local batchSize  = options.batchSize or 50
	local onProgress = options.onProgress
	local onComplete = options.onComplete

	local decimate = options.decimate
	if decimate == nil then decimate = true end
	if decimate then
		parsed = ObjDecoder.decimate(parsed, { resolution = options.resolution or 64 })
	end

	local opts = table.clone(options)
	opts.precise = true
	local data = ObjDecoder.getWedgeData(parsed, opts)
	local parts = data.parts

	local model = Instance.new("Model")
	model.Name = "PreciseWedgeModel"

	local total = #parts
	local created = 0

	task.spawn(function()
		for i, d in ipairs(parts) do
			local part = Instance.new("Part")
			part.Shape = Enum.PartType.Wedge
			part.CFrame = d.cframe
			part.Size = d.size
			part.Anchored = true
			part.CanCollide = true
			part.CanQuery = false
			part.CanTouch = false
			part.Material = Enum.Material.SmoothPlastic
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Parent = model
			created += 1

			if i % batchSize == 0 then
				task.wait()
				if onProgress then onProgress(i, total) end
			end
		end
		model.Parent = parent
		if onComplete then onComplete(model, total, created) end
	end)

	return model
end

-- ============================================================
-- 顶点聚类减面
-- ============================================================
function ObjDecoder.decimate(parsed, options)
	options = options or {}
	local resolution = options.resolution or 64

	local verts = parsed.vertices
	if #verts == 0 then return parsed end

	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, v in ipairs(verts) do
		if v.x < minX then minX = v.x end
		if v.y < minY then minY = v.y end
		if v.z < minZ then minZ = v.z end
		if v.x > maxX then maxX = v.x end
		if v.y > maxY then maxY = v.y end
		if v.z > maxZ then maxZ = v.z end
	end

	local sizeX = math.max(maxX - minX, 1e-6)
	local sizeY = math.max(maxY - minY, 1e-6)
	local sizeZ = math.max(maxZ - minZ, 1e-6)
	local scaleX = resolution / sizeX
	local scaleY = resolution / sizeY
	local scaleZ = resolution / sizeZ

	local cellMap = {}
	local vertMap = table.create(#verts)
	local newVertices = {}

	for i, v in ipairs(verts) do
		local ix = math.clamp(math.floor((v.x - minX) * scaleX), 0, resolution - 1)
		local iy = math.clamp(math.floor((v.y - minY) * scaleY), 0, resolution - 1)
		local iz = math.clamp(math.floor((v.z - minZ) * scaleZ), 0, resolution - 1)
		local key = (ix * resolution + iy) * resolution + iz

		local cell = cellMap[key]
		if not cell then
			local newIdx = #newVertices + 1
			cell = { idx = newIdx, sx = v.x, sy = v.y, sz = v.z, n = 1 }
			cellMap[key] = cell
			newVertices[newIdx] = { x = v.x, y = v.y, z = v.z }
		else
			cell.sx += v.x
			cell.sy += v.y
			cell.sz += v.z
			cell.n += 1
		end
		vertMap[i] = cell.idx
	end

	for _, cell in pairs(cellMap) do
		local t = newVertices[cell.idx]
		t.x = cell.sx / cell.n
		t.y = cell.sy / cell.n
		t.z = cell.sz / cell.n
	end

	local newFaces = {}
	for _, face in ipairs(parsed.faces) do
		local cleaned = {}
		local lastIdx = nil
		for _, fv in ipairs(face) do
			local ni = vertMap[fv.v]
			if ni and ni ~= lastIdx then
				table.insert(cleaned, { v = ni, vt = fv.vt, vn = fv.vn })
				lastIdx = ni
			end
		end
		if #cleaned >= 2 and cleaned[1].v == cleaned[#cleaned].v then
			table.remove(cleaned)
		end
		if #cleaned >= 3 then
			table.insert(newFaces, cleaned)
		end
	end

	return {
		vertices = newVertices,
		texCoords = parsed.texCoords,
		normals = parsed.normals,
		faces = newFaces,
	}
end

-- ============================================================
-- 拆分三角形
-- ============================================================
local function makeTwoWedges(A, B, C, thickness)
	local ab2 = (B - A).Magnitude ^ 2
	local bc2 = (C - B).Magnitude ^ 2
	local ca2 = (A - C).Magnitude ^ 2

	local apex, p1, p2
	if bc2 >= ab2 and bc2 >= ca2 then
		apex, p1, p2 = A, B, C
	elseif ca2 >= ab2 then
		apex, p1, p2 = B, C, A
	else
		apex, p1, p2 = C, A, B
	end

	local baseDir = p2 - p1
	local baseLen = baseDir.Magnitude
	if baseLen < 1e-6 then return nil, nil end
	local uBase = baseDir / baseLen

	local t = (apex - p1):Dot(uBase)
	local D = p1 + uBase * t
	local h = (apex - D).Magnitude
	if h < 1e-6 then return nil, nil end

	local N = (B - A):Cross(C - A)
	if N.Magnitude < 1e-9 then return nil, nil end
	N = N.Unit

	local lenP1 = (p1 - D).Magnitude
	local lenP2 = (p2 - D).Magnitude
	if lenP1 < 1e-6 or lenP2 < 1e-6 then return nil, nil end

	local uApex = (apex - D) / h
	local uP1 = (p1 - D) / lenP1
	local uP2 = (p2 - D) / lenP2
	
	local function buildWedge(ea, La, eb, Lb)
		local z = ea:Cross(eb)
		if z:Dot(N) < 0 then
			ea, eb = eb, ea
			La, Lb = Lb, La
			z = ea:Cross(eb)
		end

		local center = D
			+ ea * (La * 0.5)
			+ eb * (Lb * 0.5)
			+ z  * (thickness * 0.5)

		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Wedge
		part.Size = Vector3.new(thickness, La, Lb)
		part.CFrame = CFrame.fromMatrix(center, z, ea, eb)
			* CFrame.Angles(0, math.rad(180), 0)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		return part
	end

	local w1 = buildWedge(uApex, h, uP1, lenP1)
	local w2 = buildWedge(uP2, lenP2, uApex, h)

	return w1, w2
end

return ObjDecoder
