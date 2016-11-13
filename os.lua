os = {}
os.yield = yield
yield = nil

-- Waits until a shutdown request, then returns whether it is a restart (false
-- for ordinary shutdowns).
function os.wait_shutdown()
	return os.yield("wait_shutdown")
end

-- Low-level text input function. Blocks until a line of text is read, then
-- returns a line.
function os.wait_text()
	return os.yield("wait_text")
end

-- Low-level digiline input function. Blocks until a line of text is read, then
-- returns a line.
function os.wait_digiline()
	return os.yield("wait_digiline")
end

-- Waits until a process errors, then returns an error message.
function os.wait_err()
	return os.yield("wait_err")
end

-- Starts a new process with the given function.
function os.forkexec(prog)
	return os.yield("forkexec", prog)
end

-- Low-level text output function. Displays the given text on the console.
function os.display(text)
	return os.yield("display", text)
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
	display_buffer()
end

function io.write_line(text)
	push_buffer(text .. "\n")
	display_buffer()
end

function io.read_line()
	return os.wait_text()
end

io.write_line("Echo OS v0.0.1")

io.write("Starting error handler...")
-- Error handler
os.forkexec(function()
	while true do
		local errmsg = os.wait_err()
		io.write_line("ERROR: " .. errmsg)
	end
	
end)
io.write_line("Started!")

io.write_line("Starting echo loop.")
-- Echo loop
while true do
	io.write("> ")
	local msg = io.read_line()
	io.write_line(msg)
	io.write_line(msg)
end
	
	
