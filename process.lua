--[[
Functions:
	Process.new(env, func, arg): Returns a new process, ready to run the
	program `func` in the environment `env`. The argument arg is passed as
	an argument to the function.

Methods:
	Process:run(unit, num_units): Runs the process. `unit`
	is a number specifying how many instructions a "unit" of time should be.
	`units` is how many time units to run for.
	If no errors occur, returns the number of units elapsed as the first
	value. If the process was preempted (ran out of instructions), the second
	value will be `"_preempt"`. If the process finished, the second value will
	be `"exit". If the process made a system call, the second value will be
	some string code identifying the type of syscall. Additionally, the
	argument to the syscall will be the third return value.
	If the process suffered an error, the first return value will be `false`
	and the second will be an error message. Errors if the thread is not
	ready.

	Process:respond(response): If the process is suspended due to making a
	syscall, gives it the result and makes it ready. Errors if the process is
	not waiting on a response.

Fields:
	Process.status: One of:
	"ready": The process is ready to run.
	"waiting": The process is waiting for input from the system.
	"finished": The process has exited gracefully.
	"errored": The process has exited abnormally.

Internal Fields:
	- Process.thread: The execution state of the process, represented by a
	Lua coroutine.
	- Process.response: The latest response from the OS.
]]--

local function prepare_program(prog)
	if minetest.global_exists("jit") then
		jit.off(prog, true)
	end
end

local Process = {}
Process.__index = Process

function Process.new(env, prog, arg)
	-- Don't let the process modify the passed environment
	local inner_env = {}
	setmetatable(inner_env, { __index = env })
	
	prepare_program(prog)
	local thread = coroutine.create(prog)
	local process = {
		status = "ready",
		thread = thread,
		response = arg,
	}
	setmetatable(process, Process)

	return process
end

function Process:run(unit, num_units)
	if self.status ~= "ready" then
		error("Process is " .. self.status .. ", not ready")
	end
	
	local thread = self.thread
	local units_elapsed, request, request_arg  =
		datamine.sandboxed_resume(unit, num_units, thread, self.response)
	if not units_elapsed then
		self.status = "errored"
		return false, request
	else
		local real_status = coroutine.status(thread)
		if real_status == "dead" then
			self.status = "finished"
			return units_elapsed, "exit"
		elseif request == "_preempt" then
			return units_elapsed, "_preempt"
		elseif type(request) ~= "string" then
			self.status = "errored"
			return false, "Bad syscall id"
		else
			self.status = "waiting"
			return units_elapsed, request, request_arg
		end
	end
end

function Process:respond(response)
	if self.status ~= "waiting" then
		error("Not waiting on a response")
	end

	self.response = response
	self.status = "ready"
end


return Process
