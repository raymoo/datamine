local BUFFER_SIZE = 50

--[[
Functions:
	`Computer.new(env, capabilities, init)`: Returns a new computer.
	`env`: The environment that processes will operate in
	`capabilities`: The physical specs of the computer. It is a table with
	fields:
	- `cpu`: The number of instructions the computer will be allowed to run
	per tick.
	- `memory`: The max memory of the computer, in kilobytes.
	`init`: The program that the computer should start running. It should
	take the form of a function that takes no arguments.

	`Computer.register_syscall("call_name", func(Computer, arg, pid, pos))`:
	Registers a new kind of system call.

Methods:
	`Computer:run(pos)`: Runs the computer as based in the physical
	unit at the specified position.

	`Computer:interrupt(id[, data])`: Sends an interrupt with the string id
	`id` to the computer, with `data` as extra info. Predefined interrupt ids
	are
	- `"shutdown"`: Tell the computer to shutdown. If `data` is `true`, force
	the computer off without running any handlers.
	- `"restart"`: Same as `"shutdown"`, but turns the computer back on after
	shutting down.
	- "`text`": Report console input. `data` is the input.
	- "`digiline`": Report a digiline message. `data` is a table of the
	format `{ channel = "channel", data = "whatever (any type)" }`
	- "`error`": Signal an error. `data` is an error message.

Fields:
	`state`: "on" or "off".
	`capabilities`: The capabilities of the computer (see `Computer.new`).

Internal Fields:
p	`env`: The environment processes are run in.
	`init`: The start program. Used for restarting.
	`mem_used`: How much memory is in use (estimated with collectgarbage).
	`process_count`: Number of current processes
	`processes`: A map from pids to processes.
	`ready_queue`: Buffer of pids ready to be resumed.
	`input_queues`: Map from event types to Buffers of pids waiting on
	the event.
	`input_buffers`: Map from event types to Buffers of event data.
	`fresh_num`: A unique number for this run.
]]--

local Buffer = dofile(datamine.modpath .. "buffer.lua")
local Process = dofile(datamine.modpath .. "process.lua")

local Computer = {}
Computer.__index = Computer

function Computer.new(env, capabilities, init)
	local init_process = Process.new(env, init)
	local processes = { init_process }
	local ready_queue = Buffer.new()
	ready_queue:enqueue(1)
	local computer = {
		state = "on",
		capabilities = capabilities,
		env = env,
		init = init,
		mem_used = 0,
		process_count = 1,
		processes = processes,
		ready_queue = ready_queue,
		input_queues = {
			text = Buffer.new(),
			digiline = Buffer.new(),
			shutdown = Buffer.new(),
			err = Buffer.new(),
		},
		input_buffers = {
			text = Buffer.new(),
			digiline = Buffer.new(),
			err = Buffer.new(),
		},
		fresh_num = 2,
	}
	setmetatable(computer, Computer)

	return computer
end

local syscalls = {}
function Computer.register_syscall(call_name, handler)
	if syscalls[call_name] then
		error("Syscall already registered: " .. call_name)
	end

	syscalls[call_name] = handler
end

function Computer:fresh()
	local res = self.fresh_num
	self.fresh_num = self.fresh_num + 1

	return res
end

function Computer:dequeue_process(buffer)
	local processes = self.processes
	local pid
	local process
	while buffer:nonempty() and not process do
		pid = buffer:dequeue()
		process = processes[pid]
	end

	if process then
		return pid, process
	else
		return nil, nil
	end
end

function Computer:kill_process(pid)
	local process = self.processes[pid]
	if process then
		self.processes[pid] = nil
		self.process_count = self.process_count - 1
	end
end

function Computer:error(errstr, violating_pid)
	self:kill_process(violating_pid)
	self:interrupt("error", errstr)
end

-- Returns fuel units consumed by the syscall
function Computer:handle_syscall(syscall_name, arg, pid, pos)
	local handler = syscalls[syscall_name]
	if handler then
		return handler(self, arg, pid, pos)
	else
		self:error("Bad syscall type: " .. tostring(syscall_name), pid)
		return 1
	end
end

function Computer:run_helper(pos, elapsed_units)
	if self.state ~= "on" then
		error("Can't run computer that is off")
	end

	local timestep = self.capabilities.cpu % 10
	local fuel = 10
	while fuel > 0 and self.state == "on" do
		local pid, process = self:dequeue_process(self.ready_queue)
		if not pid then break end
		
		local units_elapsed, syscall_name, syscall_arg =
			process:run(timestep, fuel)
		if units_elapsed then
			local more_elapsed =
				self:handle_syscall(syscall_name, syscall_arg, pid, pos) or 0
			fuel = fuel - units_elapsed - more_elapsed - 1
		else
			self:error(syscall_name, pid)
			fuel = 0
		end

		if self.process_count == 0 then
			self:die()
		end
	end
end

local function log_mem(pos)
	minetest.log("warning",
		"[datamine] Out of memory killed: " .. minetest.pos_to_string(pos))
end

function Computer:run(pos)
	local used_mem = self.mem_used
	local max_mem = self.capabilities.memory
	
	local mem_before = collectgarbage("count")
	self:run_helper(pos)
	local mem_delta = collectgarbage("count") - mem_before

	local new_used_mem = used_mem + mem_delta
	if new_used_mem > max_mem then
		-- TBD: Display some kind of error.
		self:die()
	else
		self.mem_used = new_used_mem
	end
end

function Computer:fill_input(name, data, contingency)
	local queue = self.input_queues[name]
	local buffer = self.input_buffers[name]

	if queue then
		local pid, process = self:dequeue_process(queue)
		if pid then
			process:respond(data)
			self.ready_queue:enqueue(pid)
		elseif buffer then
			buffer:enqueue(data)
		elseif contingency then
			contingency(self, data)
		end
	end
end

function Computer:die()
	self.processes = {}
	self.state = "off"
end

function Computer:restart()
	-- TBD
	self:die()
end

function Computer:interrupt(id, data)
	if id == "text" then
		assert(type(data) == "string")
		self:fill_input("text", data)
	elseif id == "digiline" then
		assert(type(data) == "table")
		self:fill_input("digiline", data)
	elseif id == "shutdown" then
		if data then
			self:die()
		else
			self:fill_input("shutdown", false, Computer.die)
		end
	elseif id == "restart" then
		if data then
			self:restart()
		else
			self:fill_input("shutdown", true, Computer.restart)
		end
	elseif id == "error" then
		assert(type(data) == "string")
		self:fill_input("err", data)
	end
end

-- System Calls
Computer.register_syscall("_preempt", function(self, text, pid)
	self.ready_queue:enqueue(pid)
end)

Computer.register_syscall("shutdown", function(self, arg, pid, pos)
	local process = self.processes[pid]
	process:respond()
	self.ready_queue:enqueue(pid)
	if arg then
		self:interrupt("restart")
	else
		self:interrupt("shutdown")
	end
end)

Computer.register_syscall("shutdown_force", function(self, arg, pid, pos)
	local process = self.processes[pid]
	process:respond()
	self.ready_queue:enqueue(pid)
	if arg then
		self:interrupt("restart", true)
	else
		self:interrupt("shutdown", true)
	end
end)

Computer.register_syscall("exit", function(self, arg, pid)
	self:kill_process(pid)
end)

function Computer:wait_on_queue(pid, name)
	local queue = self.input_buffers[name]
	if queue:nonempty() then
		local data = queue:dequeue()
		local process = self.processes[pid]
		process:respond(data)
		self.ready_queue:enqueue(pid)
	else
		self.input_queues[name]:enqueue(pid)
	end
end

local function register_queue_syscall(name, queue_name)
	Computer.register_syscall(name, function(self, arg, pid)
		self:wait_on_queue(pid, queue_name)
	end)
end

register_queue_syscall("wait_shutdown", "shutdown")
register_queue_syscall("wait_text", "text")
register_queue_syscall("wait_digiline", "digiline")
register_queue_syscall("wait_err", "err")

function Computer:spawn_process(program)
	local pid = self:fresh()
	local process = Process.new(self.env, program)
	self.processes[pid] = process
	self.ready_queue:enqueue(pid)
	self.process_count = self.process_count + 1

	return pid
end

Computer.register_syscall("forkexec", function(self, arg, pid)
	if type(arg) ~= "function" then
		self:error("Non-function passed to forkexec", pid)
	else
		self:spawn_process(arg)
		self.processes[pid]:respond(pid)
		self.ready_queue:enqueue(pid)
	end
end)

local function display_at_pos(pos, text)
	local meta = minetest.get_meta(pos)
	meta:set_string("formspec", datamine.screen_formspec(text))
end

Computer.register_syscall("display", function(self, text, pid, pos)
	if type(text) ~= "string" then
		self:error("Non-string passed to display", pid)
	elseif #text > 80 * 60 then
		self:error("String passed to display was too big", pid)
	else
		display_at_pos(pos, text)
		self.processes[pid]:respond()
		self.ready_queue:enqueue(pid)
		return 10
	end
end)

Computer.register_syscall("send_digiline", function(self, data, pid, pos)
	if type(data) ~= "table" then
		self:error("Non-table passed to send_digiline", pid)
	elseif type(data.channel) ~= "string" then
		self:error("Bad channel in send_digiline", pid)
	else
		digiline:receptor_send(pos, digiline.rules.default, data.channel,
			data.data)
		self.processes[pid]:respond()
		self.ready_queue:enqueue(pid)
		return 10
	end
end)

return Computer
