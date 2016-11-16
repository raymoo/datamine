#include <stdio.h>
#include <stdlib.h>

#include "lua.h"
#include "lauxlib.h"

lua_Hook old_hook;
int old_mask;
int old_count;
int unit_count;
int curr_count;

void yield_hook(lua_State *L, lua_Debug *ar) {
  curr_count++;
  if (curr_count >= unit_count) {
    lua_pushstring(L, "_preempt");
    lua_yield(L, 1);
  }
}

void activate_preempt(lua_State *L, int interval) {
  old_hook = lua_gethook(L);
  old_mask = lua_gethookmask(L);
  old_count = lua_gethookcount(L);
  lua_sethook(L, yield_hook, LUA_MASKCOUNT, interval);
}

void disable_preempt(lua_State *L) {
  lua_sethook(L, old_hook, old_mask, old_count);
}

// Arguments: unit size, unit count, thread, other arguments.
// Returns: Number of units elapsed and yielded values, or else false and error
// message.
// SHOULD NOT be called from inside the thread.
// Resuming another coroutine with coroutine.resume inside this thread can
// defeat preemption. If you want to provide coroutine facilities in the thread's
// environment, wrap coroutine.resume in a version that will pass through
// preemption yields (the first yielded value is "_preempt").
int sandboxed_resume(lua_State *L) {
  luaL_checktype(L, 1, LUA_TNUMBER);
  luaL_checktype(L, 2, LUA_TNUMBER);
  luaL_checktype(L, 3, LUA_TTHREAD);
  
  int total_args = lua_gettop(L);
  int resume_args = total_args - 3;
  int unit_size = lua_tointeger(L, 1);
  unit_count = lua_tointeger(L, 2);
  curr_count = 0;

  // Push args onto the thread stack
  lua_State *thread_state = lua_tothread(L, 3);
  lua_xmove(L, thread_state, resume_args);

  // Run with preemption
  activate_preempt(thread_state, unit_size);
  int res = lua_resume(thread_state, resume_args);
  disable_preempt(thread_state);

  // Success
  if (res == LUA_YIELD || res == 0) {
    lua_pushinteger(L, curr_count);
    int resnum = lua_gettop(thread_state);
    lua_xmove(thread_state, L, resnum);
    return 1 + resnum;
  } else { // Error
    lua_pushboolean(L, 0);
    lua_xmove(thread_state, L, 1);

    return 2;
  }
}
