local LIB_PATH = "preempter.so"

local insecure_env = minetest.request_insecure_environment()
if not insecure_env then
   local err = "[cloud] This mod requires an insecure environment to run.\n"
   err = err .. "Please add this mod as a trusted mod, or disable mod security."
   error(err)
end

local modpath = minetest.get_modpath(minetest.get_current_modname()) .. "/"

local sandboxed_create = insecure_env.package.loadlib(modpath .. LIB_PATH, "sandboxed_create")
local sandboxed_resume = insecure_env.package.loadlib(modpath .. LIB_PATH, "sandboxed_resume")
