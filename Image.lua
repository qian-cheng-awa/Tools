local Module = {}

Module.NewImage = function(Image)
	if isfile and isfile(Image) then
		Image = getcustomasset(Image)
	end

	local NewImage = game:GetService("AssetService"):CreateEditableImageAsync(Content.fromUri(Image))

	return NewImage
end

Module.GetPixel = function(Image,X,Y)
	local a = Image:ReadPixelsBuffer(Vector2.new(X-1,Y-1),Vector2.new(1,1))
	return Color3.fromRGB(buffer.readu8(a,0),buffer.readu8(a,1),buffer.readu8(a,2)),1-(buffer.readu8(a,3)/255)
end

return Module
