
local odr = require "plugin.onDemandResources"
local json = require "json"

print("---=== Initiating ODR Request ===---")

odr.request("dlc", function( event )
	print("---=== Response ===---")
	print(json.prettify(event))

	local path = odr.path("Readme.markdown")
	print("---=== Path: '" , path , "' ===---")
	
	local t = "ODR Request failed with error " .. tostring( event.errorCode )

	if path then
		local f = io.open( path )
		print("---=== Contents: ===---")
		local contents = f:read( "*all" )
		t = "ODR request succeeded. Contents of downloaded file:\n\n" .. contents
		print(contents)
		f:close()
		print("---=== End ===---")
	end
	display.newText{
		text = t,
		x = display.contentCenterX,
		y = display.contentCenterY,
		width = display.contentWidth - 100,
		fontSize = 16,
		align = "center",
	}

end)

