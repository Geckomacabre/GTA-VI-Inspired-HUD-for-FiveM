"""Runs the Lua test files against client/physics.lua, outside the game.

    python tests/run.py                 every *_test.lua
    python tests/run.py physics         just tests/physics_test.lua
    python tests/run.py makes           the make-percentage table (tests/makes.lua)

Needs lupa (pip install lupa). The physics file has no natives in it, which is
the whole point of keeping it separate: what is tested here is what the game runs.
"""
import pathlib
import sys

try:
    from lupa import lua54 as lupa
except ImportError:  # any 5.x will do, the file sticks to plain Lua
    import lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent


def runtime():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.ROOT = str(ROOT).replace('\\', '/')
    lua.execute('''
        BB = {}

        -- The one FiveM type the config uses. tests/fakegame.lua replaces it with
        -- one that can also be added and measured.
        function vec3(x, y, z) return { x = x + 0.0, y = y + 0.0, z = z + 0.0 } end
        vector3 = vec3
        function vec4(x, y, z, w) return { x = x + 0.0, y = y + 0.0, z = z + 0.0, w = w + 0.0 } end

        function load_file(rel)
            local f = assert(io.open(ROOT .. '/' .. rel, 'r'))
            local src = f:read('a')
            f:close()
            return assert(load(src, '@' .. rel))()
        end

        -- A file written for the game: `name` hash literals are FiveM's, and
        -- stock Lua won't parse them, so they become a number on the way in.
        function load_game(rel)
            local f = assert(io.open(ROOT .. '/' .. rel, 'r'))
            local src = f:read('a'):gsub('`[^`\\n]*`', '0')
            f:close()
            return assert(load(src, '@' .. rel))()
        end
    ''')
    lua.execute("load_file('client/physics.lua')")
    lua.execute("World = load_file('tests/world.lua')")
    return lua


def main():
    want = sys.argv[1:] or sorted(p.stem[:-5] for p in (ROOT / 'tests').glob('*_test.lua'))
    failed = 0

    for name in want:
        rel = f'tests/{name}_test.lua'
        if not (ROOT / rel).exists():
            rel = f'tests/{name}.lua'

        lua = runtime()
        lua.globals().ARGS = lua.table_from(sys.argv[2:])
        result = lua.execute(f"return load_file('{rel}')")
        failed += int(result or 0)

    print('\nFAILED: %d' % failed if failed else '\nall passed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
