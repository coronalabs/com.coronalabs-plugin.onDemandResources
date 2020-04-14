local Library = require "CoronaLibrary"

-- Create stub library for simulator
local lib = Library:new{ name='plugin.onDemandResources', publisherId='com.coronalabs' }

-- Default implementations
local function defaultFunction()
	print( "WARNING: The '" .. lib.name .. "' library is not available on this platform." )
end

lib.setEventListener = defaultFunction
lib.request = defaultFunction
lib.progress = defaultFunction
lib.pause = defaultFunction
lib.resume = defaultFunction
lib.cancel = defaultFunction
lib.getDownloadPriority = defaultFunction
lib.setDownloadPriority = defaultFunction
lib.getPreservationPriority = defaultFunction
lib.setPreservationPriority = defaultFunction
lib.path = defaultFunction


-- Return an instance
return lib
