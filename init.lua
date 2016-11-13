local LIB_PATH = "preempter.so"
local MAX_FILE_SIZE = 100000
local MAX_MEMORY = 1024

datamine = {}
local modpath = minetest.get_modpath(minetest.get_current_modname()) .. "/"
datamine.modpath = modpath

local insecure_env = minetest.request_insecure_environment()
if not insecure_env then
	local err = "[datamine] This mod requires an insecure environment to run.\n"
	err = err .. "Please add this mod as a trusted mod, or disable mod security."
	error(err)
end
datamine.sandboxed_resume =
	assert(insecure_env.package.loadlib(modpath .. LIB_PATH, "sandboxed_resume"))

local Computer = dofile(modpath .. "computer.lua")
local Buffer = dofile(modpath .. "buffer.lua")

local os_file = assert(io.open(modpath .. "os.lua", "r"))
local os_source = os_file:read("*all")
os_file:close()

local function env()
	return {
		yield = coroutine.yield,
		table = {
			concat = table.concat,
			insert = table.insert,
		},
		Buffer = Buffer,
		ipairs = ipairs,
		pairs = pairs,
		string = {
			sub = string.sub
		},
		tostring = tostring,
		error = error,
	}
end

local function caps(cpu, mem)
	return { cpu = cpu, memory = mem }
end

local function os_program()
	local program = assert(loadstring(os_source))
	setfenv(program, env())
	return program
end

-- Screen formspecs
function datamine.screen_formspec(display)
	local everything = {}
	everything[1] = "size[8,8]textarea[0,0;8,7;output;;"
	everything[2] = minetest.formspec_escape(display)
	everything[3] = "]field[0,7;6,1;input;;]button[7,7;1,1;submit;>]"

	return table.concat(everything)
end

local hash_pos = minetest.hash_node_position
local unhash_pos = minetest.get_position_from_hash

-- Map from position hashes to computers
local active_computers = {}
local function run_computers()
	local remove_these = {}
	for poshash, computer in pairs(active_computers) do
		local pos = unhash_pos(poshash)
		local node = minetest.get_node_or_nil(pos)
		if node and node.name == "datamine:computer" then
			computer:run(pos)
			if computer.state ~= "on" then
				table.insert(remove_these, poshash)
			end
		else
			table.insert(remove_these, poshash)
		end
	end

	for i, poshash in ipairs(remove_these) do
		active_computers[poshash] = nil
	end
end
minetest.register_globalstep(run_computers)

local function add_computer(pos, computer)
	active_computers[hash_pos(pos)] = computer
end

local function start_computer(pos, meta)
	local computer = Computer.new(env(), caps(1000, MAX_MEMORY), os_program())
	add_computer(pos, computer)

	return computer
end

function datamine.get_computer(pos)
	return active_computers[hash_pos(pos)]
end

-- Computer Nodes
minetest.register_node("datamine:computer", {
	description = "Computer",
	groups = { cracky = 3 },
	drawtype = "normal",
	tiles = { "datamine_computer.png" },
	after_place_node = function(pos, placer, itemstack, pointed_thing)
		local p_name = placer and placer:get_player_name() or ""
		local meta = minetest.get_meta(pos)
		meta:set_string("owner", p_name)
		meta:set_string("formspec", datamine.screen_formspec(""))
		meta:set_string("used_space", 0)
		meta:set_string("max_space", MAX_FILE_SIZE)
		start_computer(pos, meta)
	end,
	on_receive_fields = function(pos, formname, fields, sender)
		local computer = datamine.get_computer(pos)
		if not computer then
			computer = start_computer(pos, minetest.get_meta(pos))
		elseif fields.submit and fields.input then
			for s in string.gmatch(fields.input, "([^\n]+)\n?") do
				computer:interrupt("text", s)
			end
			local meta = minetest.get_meta(pos)
			meta:set_string("formspec", datamine.screen_formspec(fields.output or ""))
		end
	end,
	digiline = {
		receptor = {},
		effector = {
			action = function(pos, node, channel, msg)
				local computer = datamine.get_computer(pos)
				if computer then
					computer:interrupt("digiline", {
						channel = channel,
						data = msg,
					})
				end
			end,
		},
	}
})
