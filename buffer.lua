--[[
Functions:
	Buffer.new(): Creates a new, empty buffer.

Methods of Buffer
	Buffer:empty(): Returns true if buffer is empty, false otherwise.

	Buffer:nonempty(): The negation of empty.

	Buffer:enqueue(val): Add something to the buffer.

	Buffer:dequeue(): Remove something from the end of the buffer and return
	it. Errors if empty.

	Buffer:size(): Returns the number of elements in the buffer.

]]--

local Buffer = {}
Buffer.__index = Buffer

function Buffer.new()
	local queue = {
		starti = 0,
		endi = -1,
	}
	setmetatable(queue, Buffer)
	return queue
end

function Buffer:empty()
	return self.endi < self.starti
end

function Buffer:nonempty()
	return self.endi >= self.starti
end

function Buffer:enqueue(val)
	local new_endi = self.endi + 1
	self[new_endi] = val
	self.endi = new_endi
end

function Buffer:dequeue()
	local starti = self.starti
	if starti > self.endi then
		error("Tried to dequeue empty buffer")
	end
	local val = self[starti]
	self[starti] = nil
	self.starti = starti + 1

	return val
end

function Buffer:size()
	return self.endi - self.starti + 1
	end


return Buffer
