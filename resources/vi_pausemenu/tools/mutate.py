"""mutate.py [fengari dir]: each mutation of the resource must make check.lua fail (run.js on a changed copy)."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
MUTATIONS = [
    ('client/main.lua', "    SendNUIMessage({ type = 'hide' })\n    SetNuiFocus(false, false)", "    SendNUIMessage({ type = 'hide' })"),
    ('client/main.lua', "            if not nativeOpen then\n                SetPauseMenuActive(false)", "            if true then\n                SetPauseMenuActive(false)"),
    ('client/main.lua', "and GetGameTimer() - closedAt > 300", "and GetGameTimer() - closedAt > 0"),
    ('client/main.lua', "(at - 1 + (dir < 0 and -1 or 1)) % #s.values + 1", "(at + (dir < 0 and -1 or 1)) % #s.values + 1"),
    ('client/main.lua', "        screen = 'map'\n        return cb(", "        return cb("),
    ('client/main.lua', "if sprite == 1 then", "if false then"),
    ('client/main.lua', "if sprite ~= 6 and sprite ~= 8 then", "if sprite ~= 6 then"),
    ('client/main.lua', "if MAP_DISPLAYS[GetBlipInfoIdDisplay(blip)] then", "if true then"),
    ('client/main.lua', "for _ = 1, 300 do", "for _ = 1, 400 do"),
    ('client/main.lua', "SetNewWaypoint(x + 0.0, y + 0.0)", "SetNewWaypoint(y + 0.0, x + 0.0)"),
    ('client/main.lua', "if open and not nativeOpen and screen == 'map' then", "if open and not nativeOpen then"),
    ('client/main.lua', "ipairs(onMap and PAD_MAP_BUTTONS or PAD_BUTTONS)", "ipairs(PAD_MAP_BUTTONS)"),
    ('client/main.lua', "if math.abs(x) <= MAP_STICK and math.abs(y) <= MAP_STICK then x, y = 0, 0 end", ""),
    ('client/main.lua', "if x == axes[1] and y == axes[2] and lt == axes[3] and rt == axes[4] then return end", ""),
    ('client/main.lua', "pcall(PauseMenuceptionTheKick)", "-- kick"),
    ('client/main.lua', "(Config.Discord or '') ~= ''", "true"),
    ('client/main.lua', "local usable = ResourceUp(tile.needs) and", "local usable = "),
    ('client/main.lua', "return not onFoot", "return onFoot"),
    ('client/main.lua', "if open and screen == 'players' then", "if false then"),
    ('client/main.lua', "if Recording() then", "if false then"),
    ('client/main.lua', "    if open then CloseMenu() end\n    LocalPlayer.state:set('pauseMenuOpen', false, false)\nend)", "end)"),
    ('client/main.lua', "fresh = fresh == true", "fresh = true"),
    ('client/main.lua', "return res[name](res, table.unpack(args, 1, args.n))", "return res[name](nil, table.unpack(args, 1, args.n))"),
    ('client/main.lua', "if subject ~= '' and text ~= '' then", "if true then"),
    ('client/main.lua', "SetTimeout(500, ApplyCrashCam)", "-- no"),
    ('server/main.lua', "if lastReport[src] and now - lastReport[src] < 60 then return end", ""),
    ('server/main.lua', "DropPlayer(source, 'You left the server.')", ""),
    ('client/main.lua', "    if LISTS[screen] then\n        SendNUIMessage({ type = 'list'", "    if false then\n        SendNUIMessage({ type = 'list'"),
    ('server/main.lua', "name = name:gsub('%^%d', '')", ""),
    ('client/main.lua', "(info.firstname or '') .. ' ' .. (info.lastname or '')", "(info.firstname or '')"),
    ('client/main.lua', "if open then SendNUIMessage({ type = 'title', title = Title() }) end", ""),
    ('client/main.lua', "    TriggerServerEvent('vi_pausemenu:server:requestPlayers')\nend)", "end)"),
    ('client/main.lua', "if (Config.Title or '') ~= '' then return Config.Title end", ""),
    ('client/main.lua', "and name ~= serverName then", "then"),
    ('client/main.lua', "        UnregisterPedheadshot(handle)\n        mugBusy = false", "        mugBusy = false"),
    ('client/main.lua', "while mugCopied == nil and GetGameTimer() < deadline do Wait(0) end", ""),
    ('client/main.lua', "    TakeMugshot()\n", ""),
    ('client/main.lua', "if IsPedheadshotReady(handle) and IsPedheadshotValid(handle) then", "if IsPedheadshotReady(handle) then"),
]

fengari = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SRC, '..', 'vice_hud', 'node_modules', 'fengari')
survived = 0
for i, (rel, old, new) in enumerate(MUTATIONS):
    tmp = tempfile.mkdtemp()
    dst = os.path.join(tmp, 'res')
    shutil.copytree(SRC, dst, ignore=shutil.ignore_patterns('html', 'tools'))
    path = os.path.join(dst, rel)
    text = open(path, encoding='utf-8').read()
    if old not in text:
        print(f'{i}: MUTATION TEXT NOT FOUND: {old[:60]!r}')
        survived += 1
        continue
    open(path, 'w', encoding='utf-8').write(text.replace(old, new, 1))
    r = subprocess.run(['node', os.path.join(HERE, 'run.js'), dst, fengari], capture_output=True, text=True)
    killed = r.returncode != 0
    if not killed:
        survived += 1
    print(f"{i}: {'killed' if killed else 'SURVIVED'}  {rel}: {old.splitlines()[-1].strip()[:70]}")
    shutil.rmtree(tmp, ignore_errors=True)
print('survived:', survived)
