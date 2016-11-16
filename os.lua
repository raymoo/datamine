os = {}
os.yield = yield
yield = nil

function os.wait_event()
	return os.yield("wait_event")
end

-- Starts a new process with the given function.
function os.forkexec(prog)
	return os.yield("forkexec", prog)
end

-- Low-level text output function. Displays the given text on the console.
function os.display(text)
	return os.yield("display", text)
end

-- Digiline output function.
function os.send_digiline(channel, msg)
	return os.yield("send_digiline", { channel = channel, data = msg })
end

-- Stores 1000 characters
local text_buffer = ""
local function push_buffer(text)
	text_buffer = string.sub(text_buffer .. text, -1000)
end
local function display_buffer()
	os.display(text_buffer)
end

io = {}
function io.write(text)
	push_buffer(text)
end

function io.write_line(text)
	push_buffer(text .. "\n")
end

function io.flush()
	display_buffer()
end

io.write_line("Event OS v0.0.1")
io.flush()

-- Digiline Test
io.write_line("Seeking light sensor on channel \"light\"")
io.flush()

os.send_digiline("light", "GET")

-- Error Test
os.forkexec(function()
	-- Should get displayed by the error handler
	error("test")
end)
	
io.write_line("Starting event loop.")
io.flush()
-- Event loop
while true do
	io.write("> ")
	io.flush()
	local event = os.wait_event()
	if event[1] == "text" then
		io.write_line(event[2])
		io.write_line(event[2])
		io.flush()
	elseif event[1] == "digiline" then
		local msg = event[2]
		if msg.channel == "light" then
			io.write_line("Received light level: " .. msg.data)
			io.flush()
		end
	elseif event[1] == "err" then
		io.write_line("ERROR: " .. event[2])
		io.flush()
	end
end
	
	
