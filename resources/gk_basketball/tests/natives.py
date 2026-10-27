"""Static check of every native call in the resource against the native database.

    python tests/natives.py [resource_dir]

For every `Name(...)` call in client/, server/ and shared/:
  - Name must be a FiveM native, a function the resource defines, or part of the
    Lua / FiveM / ox_lib runtime;
  - the number of arguments must be one the native can take (fewer is reported
    separately: FiveM passes zero for the rest, which is only sometimes right);
  - a client file must not call a server-only native, or the other way round.

The database is the devtools kit's copy of FiveM's native JSON. Set DEVTOOLS_PATH
if the kit isn't at ~/OneDrive/Desktop/devkit/_devtools.

Same method as the Skate 3 board's devtools_native_check.py.
"""
import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent

DEVTOOLS = os.environ.get('DEVTOOLS_PATH') or os.path.join(
    os.path.expanduser('~'), 'OneDrive', 'Desktop', 'devkit', '_devtools')
SRC = os.path.join(DEVTOOLS, '_tools', 'nativedb_src')

RUNTIME = set('''assert error ipairs next pairs pcall xpcall select tonumber tostring type rawget rawset rawequal
rawlen setmetatable getmetatable load require print unpack CreateThread Wait SetTimeout RegisterNetEvent
AddEventHandler RemoveEventHandler TriggerEvent TriggerServerEvent TriggerClientEvent TriggerLatentServerEvent
RegisterCommand RegisterKeyMapping RegisterNUICallback SendNUIMessage vector2 vector3 vector4 vec2 vec3 vec4 quat
joaat exports GetHashKey source Player Entity GlobalState LocalPlayer AddStateBagChangeHandler GetPlayers
GetGamePool NetworkGetEntityFromNetworkId'''.split())


def lua_name(native):
    name = native.lstrip('_')
    if name.startswith('0x'):
        return 'N_' + name
    return ''.join(('_' if p[:1].isdigit() else '') + p[:1].upper() + p[1:].lower() for p in name.split('_'))


def load_db():
    table = {}
    for fn in ('fivem_natives.json', 'fivem_natives_cfx.json'):
        data = json.load(open(os.path.join(SRC, fn), encoding='utf-8'))
        for ns, natives in data.items():
            for n in natives.values():
                name = n.get('name') or ''
                if not name:
                    continue
                entry = {'params': n.get('params') or [], 'apiset': n.get('apiset') or 'client'}
                table.setdefault(lua_name(name), []).append(entry)
                for alias in n.get('aliases') or []:
                    table.setdefault(lua_name(alias), []).append(entry)
    return table


def strip(src):
    """Comments and string contents blanked, same length, so line numbers hold."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('--[[', i):
            j = src.find(']]', i)
            j = n if j < 0 else j + 2
            out.append(re.sub(r'[^\n]', ' ', src[i:j]))
            i = j
        elif src.startswith('--', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i))
            i = j
        elif c in '\'"`':
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == '\\' else 1
            out.append('"' + 's' * max(0, j - i - 1) + '"')
            i = j + 1
        elif src.startswith('[[', i):
            j = src.find(']]', i)
            j = n if j < 0 else j + 2
            out.append('"' + re.sub(r'[^\n]', 's', src[i + 1:j - 1]) + '"')
            i = j
        else:
            out.append(c)
            i += 1
    return ''.join(out)


OPEN, CLOSE = {'function', 'do', 'if', 'repeat'}, {'end', 'until'}


def count_args(code, start):
    depth, block, i, args, seen = 0, 0, start, 0, False
    while i < len(code):
        c = code[i]
        if c.isalpha() or c == '_':
            j = i
            while j < len(code) and (code[j].isalnum() or code[j] == '_'):
                j += 1
            word = code[i:j]
            block += 1 if word in OPEN else (-1 if word in CLOSE else 0)
            seen, i = True, j
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                return args + (1 if seen else 0)
        elif c == ',' and depth == 1 and block == 0:
            args += 1
        elif depth >= 1 and not c.isspace():
            seen = True
        i += 1
    return None


def lua_params(params):
    def passed(p):
        t = str(p.get('type', ''))
        return not t.endswith('*') or t.startswith(('char', 'const char'))
    return [p for p in params if passed(p)]


def main():
    db = load_db()
    files = [p for d in ('client', 'server', 'shared') for p in sorted((ROOT / d).glob('*.lua'))]
    stripped = {f: strip(f.read_text(encoding='utf-8')) for f in files}

    defined = set()
    for code in stripped.values():
        defined |= set(re.findall(r'\bfunction\s+([A-Za-z_][\w.:]*)', code))
        defined |= set(re.findall(r'\b([A-Za-z_]\w*)\s*=\s*function\b', code))
        for grp in re.findall(r'\blocal\s+([A-Za-z_][\w\s,]*?)\s*(?:=|\n)', code):
            defined |= {m for m in re.split(r'[\s,]+', grp) if m}
    defined |= {d.split('.')[-1].split(':')[-1] for d in defined}

    calls = 0
    used, unknown, wrong_side, mismatch, fewer = {}, {}, [], [], []

    for f, code in stripped.items():
        rel = f.relative_to(ROOT).as_posix()
        side = f.parent.name    # client | server | shared

        for m in re.finditer(r'(?<![\w.:])([A-Z][A-Za-z0-9_]*)\s*\(', code):
            name = m.group(1)
            line = code.count('\n', 0, m.start()) + 1

            if re.search(r'function\s+$', code[max(0, m.start() - 12):m.start()]):
                continue

            if name in RUNTIME:
                continue

            if name in db:
                calls += 1
                used[name] = used.get(name, 0) + 1
                n = count_args(code, m.end() - 1)
                entries = db[name]
                want = sorted({k for e in entries for k in range(len(lua_params(e['params'])), len(e['params']) + 1)})
                api = {e['apiset'] for e in entries}

                if side == 'client' and api == {'server'} or side == 'server' and api == {'client'}:
                    wrong_side.append(f'{rel}:{line} {name} is a {"/".join(api)} native, called on the {side}')

                if n not in want:
                    params = ', '.join(f"{p.get('type', '?')} {p.get('name', '?')}" for p in lua_params(entries[0]['params']))
                    (fewer if n is not None and n < min(want) else mismatch).append(
                        f'{rel}:{line} {name} called with {n}, takes {want[0]} ({params})')
            elif name not in defined:
                unknown.setdefault(name, []).append(f'{rel}:{line}')

    print(f'{len(files)} Lua files, {calls} native calls, {len(used)} different natives')

    for title, rows in (('wrong argument count', mismatch),
                        ('fewer arguments than parameters (FiveM passes zero for the rest)', fewer),
                        ('wrong side', wrong_side)):
        print(f"{'OK  ' if not rows else ('NOTE' if rows is fewer else 'BAD ')}{title}: {len(rows)}")
        for r in rows:
            print('      ' + r)

    print(f"{'BAD ' if unknown else 'OK  '}calls to names that are neither natives nor defined here: {len(unknown)}")
    for name, where in sorted(unknown.items()):
        print(f"      {name}: {', '.join(where[:6])}")

    ok = not mismatch and not wrong_side and not unknown
    print('ALL OK' if ok else 'CHECK THE LINES ABOVE')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
