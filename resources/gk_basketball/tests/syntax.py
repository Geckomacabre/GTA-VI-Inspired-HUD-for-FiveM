"""Parses every Lua file in the resource without running it.

    python tests/syntax.py

FiveM's Lua has one thing in these files that stock Lua doesn't: `name` hash
literals. They are swapped for a number so the stock parser can read the file;
everything else is plain Lua 5.4.
"""
import pathlib
import re
import sys

try:
    from lupa import lua54 as lupa
except ImportError:
    import lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent
HASH = re.compile('`[^`\n]*`')

lua = lupa.LuaRuntime()
check = lua.eval('function(src, name) local f, err = load(src, name); return err end')

bad = 0

for path in sorted(ROOT.rglob('*.lua')):
    if 'tests' in path.parts:
        continue

    src = HASH.sub('0', path.read_text(encoding='utf-8'))
    err = check(src, '@' + path.relative_to(ROOT).as_posix())

    if err:
        bad += 1
        print('SYNTAX', err)

print('%d files with syntax errors' % bad if bad else 'syntax ok')
sys.exit(1 if bad else 0)
