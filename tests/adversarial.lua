-- Run in the real renderer/platform harness; only command execution is stubbed.
local base = assert(os.getenv('BOUNDARY_DIR'))
cooloo = {platform=native_platform, renderer=native_renderer, args={}, text_files={}, clipboard={}}
cooloo.platform.exedir, cooloo.platform.userdir = base, base .. '/user'
cooloo.safe_mode = os.getenv('BOUNDARY_SAFE') == '1'
package.preload['user.colors.summer'] = function() return 'EMBEDDED' end
package.preload['user.colors.fall'] = function() return 'FALLBACK' end
package.preload['core.command'] = function() return {perform=function() return true end} end
dofile('lua/platform/lite.lua')
local expected = cooloo.safe_mode and 'EMBEDDED' or assert(os.getenv('BOUNDARY_THEME'))
assert(require('user.colors.summer') == expected)
assert(require('user.colors.fall') == 'FALLBACK')
system.platform = 'macOS'
local keys = dofile('lua/editor/core/keymap.lua')
for _, pair in ipairs{{'left ctrl','left gui','ctrl'}, {'left ctrl','right ctrl','ctrl'},
                     {'left shift','right shift','shift'}} do
  for order=1,2 do
    keys.on_key_pressed(pair[1], false)
    keys.on_key_pressed(pair[1], false) -- auto-repeat must be idempotent
    keys.on_key_pressed(pair[2], false)
    keys.on_key_released(pair[order])
    assert(keys.modkeys[pair[3]], 'other physical modifier is still held')
    keys.on_key_released(pair[3-order])
    assert(not keys.modkeys[pair[3]])
  end
end
keys.on_key_pressed('left ctrl', false)
keys.on_key_pressed('right alt', false)
assert(keys.modkeys.altgr and not keys.modkeys.ctrl)
keys.on_key_pressed('left ctrl', false)
assert(not keys.modkeys.ctrl)
keys.on_key_released('right alt')
assert(keys.modkeys.ctrl and not keys.modkeys.altgr)
keys.on_key_released('left ctrl')
print('theme precedence, fallback/safe-mode, overlapping modifiers/repeats/IME suppression/AltGr: OK')
