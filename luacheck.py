import sys
from lupa import LuaRuntime
lua = LuaRuntime()
ok = True
for p in sys.argv[1:]:
    src = open(p, encoding='utf-8', errors='replace').read().replace('      line = line:gsub', '      local line2 = line:gsub')
    try:
        lua.eval('function(s, n) local f, e = load(s, n) if not f then error(e) end return true end')(src, '@' + p.split('\\')[-1])
        print('OK  ', p)
    except Exception as e:
        ok = False
        print('FAIL', p, e)
sys.exit(0 if ok else 1)

