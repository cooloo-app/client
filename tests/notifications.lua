-- Exercise production native bindings in an isolated SDL window. This is a
-- runtime smoke test, not visual acceptance of Explorer/Dock presentation.
assert(type(native_platform.focus())=='boolean')
native_platform.set_unread(3,true)
native_platform.set_unread(1,false)
native_platform.set_unread(0,false)
assert(not pcall(native_platform.set_unread,'invalid',false))
print('notifications: native badge/attention/set/clear bindings passed')
