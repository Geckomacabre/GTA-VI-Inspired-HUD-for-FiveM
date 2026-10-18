--[[
    client/atm.lua
    The BuckMe ATM. Using a cash machine turns its own screen into the BuckMe page (web/atm/index.html, a DUI drawn as a
    flat quad over the machine's glass with DrawTexturedPoly) and the camera pushes in on it, the way GTA VI's ATMs work:
    Deposit / Withdraw / Transactions, the amount stepped with left/right, "Thank you for bucking with us", camera back out.

    The page only draws. Every bit of state lives here and goes to it whole, as one 'render' message, whenever it changes
    (and again every few hundred ms, so a page that loaded late catches up by itself). Input is the player's own keys or
    pad, read here (a DUI page takes no keyboard), and the hints for them are vice_hud's action prompts, bottom right.

    Why a quad and not AddReplaceTexture on the screen texture: that is global and would light up every ATM in range.
    Only the player using the machine sees the page; anyone watching sees the stock screen.

    BankATM.open(entity) returns false when it cannot take the machine (Config.atm.mode 'nui', a model with no measured
    screen, no DUI) and main.lua opens the old popup instead.
]]

BankATM = {}

local CFG = Config.atm
local RES = GetCurrentResourceName()

local MENU = { 'Deposit', 'Withdraw', 'Transactions' }
local HISTORY_LIMIT = 40

local pool = {}       -- 'WxH' -> { dui, txd, tex, w, h }, made on first use and kept for the session
local active = nil    -- the open session
local cam = nil

-------------------------------------------------------------------------------
-- The screen
-------------------------------------------------------------------------------
local function cross(a, b)
    return vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

--- The screen's corners in the world, its middle, which way the glass faces and how tall it is.
local function geometry(entity, screen)
    local function at(p) return GetOffsetFromEntityInWorldCoords(entity, p.x, p.y, p.z) end
    local tl, tr, br, bl = at(screen.tl), at(screen.tr), at(screen.br), at(screen.bl)
    local right, down = tr - tl, bl - tl
    local normal = cross(down, right)
    return {
        tl = tl, tr = tr, br = br, bl = bl,
        center = (tl + tr + br + bl) / 4,
        normal = normal / #normal,
        h = #down,
    }
end

--- One browser per screen shape, so the page is never stretched: 1024 wide, as tall as that machine's glass is.
local function ensureSlot(screen)
    local w = CFG.resolution or 1024
    local h = math.floor(w * #(screen.bl - screen.tl) / #(screen.tr - screen.tl) + 0.5)
    local key = ('%dx%d'):format(w, h)
    if pool[key] then return pool[key] end

    local dui = CreateDui(('https://cfx-nui-%s/web/atm/index.html?res=%s&slot=%s'):format(RES, RES, key), w, h)
    if not dui then return nil end

    local txdName = ('rb_atm_%s'):format(key)
    local txd = CreateRuntimeTxd(txdName)
    CreateRuntimeTextureFromDuiHandle(txd, 'screen', GetDuiHandle(dui))

    pool[key] = { dui = dui, txd = txdName, tex = 'screen', w = w, h = h }
    return pool[key]
end

local function toDui(slot, msg)
    if slot and slot.dui and IsDuiAvailable(slot.dui) then
        SendDuiMessage(slot.dui, json.encode(msg))
        return true
    end
    return false
end

-- The page says hello once it is listening; until then the heartbeat in BankATM.open keeps re-sending quickly.
RegisterNUICallback('atm_ready', function(data, cb)
    cb('ok')
    local slot = type(data) == 'table' and pool[data.slot]
    if slot then slot.ready = true end
end)

--- Only this player, only while it is open. Both windings, so whichever way the engine culls, the front shows the page.
local function drawScreen(g, slot)
    local tl, tr, br, bl, d, t = g.tl, g.tr, g.br, g.bl, slot.txd, slot.tex
    DrawTexturedPoly(tl.x, tl.y, tl.z, tr.x, tr.y, tr.z, br.x, br.y, br.z, 255, 255, 255, 255, d, t, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0)
    DrawTexturedPoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, bl.x, bl.y, bl.z, 255, 255, 255, 255, d, t, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0)
    DrawTexturedPoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, tr.x, tr.y, tr.z, 255, 255, 255, 255, d, t, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0)
    DrawTexturedPoly(tl.x, tl.y, tl.z, bl.x, bl.y, bl.z, br.x, br.y, br.z, 255, 255, 255, 255, d, t, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0)
end

-------------------------------------------------------------------------------
-- What the page is told
-------------------------------------------------------------------------------
local function account(a) return a.accounts[a.acc] or a.accounts[1] end
local function balanceOf(acc) return math.floor(tonumber(acc and acc.amount) or 0) end
-- Cash is the character's whichever account is picked; the personal account (always first) carries it.
local function cashOnHand(a) return math.floor(tonumber(a.accounts[1] and a.accounts[1].cash) or 0) end

local function amountMax(a, verb)
    local have = verb == 'deposit' and cashOnHand(a) or balanceOf(account(a))
    return math.max(0, math.min(have, CFG.limit or have))
end

--- The amounts left/right steps through: every configured step under the maximum, then the maximum itself.
local function steps(max)
    local list = {}
    for _, v in ipairs(CFG.amounts or {}) do
        if v < max then list[#list + 1] = v end
    end
    if max > 0 then list[#list + 1] = max end
    return list
end

local function historyItems(acc)
    local out = {}
    for i, t in ipairs(acc and acc.transactions or {}) do
        if i > HISTORY_LIMIT then break end
        out[i] = {
            amount = tonumber(t.amount) or 0,
            kind = t.trans_type,
            time = tonumber(t.time),
            text = t.message or t.title or '',
        }
    end
    return out
end

local function payload(a)
    local acc = account(a)
    local p = {
        action = 'render',
        screen = a.view,
        busy = a.busy or nil,
        balance = balanceOf(acc),
        limit = CFG.limit,
        title = a.acc == 1 and 'Your Account' or (acc.name or 'Account'),
    }

    if a.view == 'welcome' then
        p.name = (a.accounts[1].name or ''):match('^(%S+)')
    elseif a.view == 'menu' then
        p.items, p.focus = MENU, a.menu
        if #a.accounts > 1 then p.account = { index = a.acc, count = #a.accounts } end
    elseif a.view == 'amount' then
        local m = a.amt
        p.title = m.verb == 'deposit' and 'Deposit' or 'Withdraw'
        p.verb, p.value, p.max, p.focus, p.error = m.verb, m.value, m.max, m.focus, m.error
        p.label = (m.max > 0 and m.value == m.max) and 'Maximum' or (m.custom and 'Custom' or nil)
        p.canDown = m.list[1] ~= nil and m.list[1] < m.value
        p.canUp = m.value < m.max
    elseif a.view == 'history' then
        p.title = 'Transactions'
        p.items, p.focus = a.hist.items, a.hist.focus
    end

    return p
end

-------------------------------------------------------------------------------
-- Prompts (vice_hud's, bottom right -- the same SELECT / EXIT / ADJUST column the reference shows)
-------------------------------------------------------------------------------
local shown, shownSig, textUi = {}, nil, false

local function usingPad()
    local ok, kbm = pcall(IsUsingKeyboard, 2)
    return ok and kbm == false
end

local function hud(fn, ...)
    local args = { ... }
    return pcall(function() return exports.vice_hud[fn](exports.vice_hud, table.unpack(args)) end)
end

local function promptList(a)
    if a.busy or a.closing or a.typing or a.view == 'welcome' or a.view == 'splash' then return {} end

    local pad = usingPad()
    local select = { id = 'rb_atm_select', label = 'SELECT', key = 191, name = 'ENTER' }
    local back = { id = 'rb_atm_back', label = 'BACK', key = 194, name = 'BACKSPACE' }

    if a.view == 'menu' then
        local list = { select }
        if #a.accounts > 1 then list[#list + 1] = { id = 'rb_atm_account', label = 'ACCOUNT', key = 206, name = 'E' } end
        back.label = 'EXIT'
        list[#list + 1] = back
        return list
    end

    if a.view == 'amount' then
        local m = a.amt
        local all = {
            id = 'rb_atm_all', label = m.verb == 'deposit' and 'DEPOSIT ALL' or 'WITHDRAW ALL', key = 203, name = 'SPACE',
            off = m.max == 0 or m.value == m.max,
        }
        if m.focus == 'box' then
            local list = { { id = 'rb_atm_adjust', label = 'ADJUST', key = pad and 'DPAD_X' or 'A/D', name = 'A/D', off = m.max == 0 }, all }
            -- Typing needs a keyboard; on a pad the steps are the way.
            if not pad then list[#list + 1] = { id = 'rb_atm_type', label = 'TYPE AMOUNT', key = 204, name = 'TAB', off = m.max == 0 } end
            list[#list + 1] = back
            return list
        end
        return { all, select, back }
    end

    if a.view == 'history' then
        local list = {}
        if #a.hist.items > 1 then
            list[1] = { id = 'rb_atm_scroll', label = 'SCROLL', key = pad and 'DPAD_Y' or 'W/S', name = 'W/S' }
        end
        list[#list + 1] = back
        return list
    end

    return {}
end

--- Shows exactly `list`, in order. A row whose id is already up is updated where it stands; the column is only
--- rebuilt when the set of rows changes (vice_hud buzzes the pad for every new prompt, so not on every key press).
local function setPrompts(list)
    local parts = {}
    for i = 1, #list do
        local p = list[i]
        parts[i] = ('%s|%s|%s|%s'):format(p.id, p.label, tostring(p.key), p.off and 1 or 0)
    end
    local sig = table.concat(parts, ';')
    if sig == shownSig then return end
    shownSig = sig

    if GetResourceState('vice_hud') ~= 'started' then
        local text = {}
        for i = 1, #list do
            if not list[i].off then text[#text + 1] = ('[%s] %s'):format(list[i].name, list[i].label) end
        end
        if #text > 0 then
            lib.showTextUI(table.concat(text, '   '), { position = 'bottom-center' })
            textUi = true
        elseif textUi then
            lib.hideTextUI()
            textUi = false
        end
        return
    end

    local same = #list == #shown
    if same then
        for i = 1, #list do
            if list[i].id ~= shown[i] then same = false; break end
        end
    end
    if not same then
        for i = 1, #shown do hud('HideActionPrompt', shown[i]) end
        shown = {}
    end
    for i = 1, #list do
        local p = list[i]
        hud('ShowActionPrompt', p.id, p.label, p.key, { off = p.off })
        shown[i] = p.id
    end
end

local function clearPrompts()
    setPrompts({})
    if textUi then lib.hideTextUI(); textUi = false end
    shownSig = nil
end

local function render()
    local a = active
    if not a then return end
    toDui(a.slot, payload(a))
    setPrompts(promptList(a))
end

-------------------------------------------------------------------------------
-- Ending it
-------------------------------------------------------------------------------
local savedInvBusy

--- Nothing else gets the player's hands while they are at the machine: no targeting prompts (osm-target answers
--- ox_target's disableTargeting), no inventory, and vice_hud shows the cash / BuckMe rows while `atmOpen` is set.
local function lock(on)
    pcall(function() exports.ox_target:disableTargeting(on) end)
    local state = LocalPlayer.state
    if on then
        savedInvBusy = state.invBusy
        state:set('invBusy', true, false)
    else
        state:set('invBusy', savedInvBusy == true, false)
    end
    state:set('atmOpen', on, false)
end

--- Camera back out (the page keeps showing while it does, as the reference does), the ATM scenario's own exit, and
--- the machine goes back to its stock screen. `now` skips the ease (dead, knocked over, walked off).
function BankATM.close(now)
    local a = active
    if not a or a.closing then return end
    a.closing, a.closedAt, a.busy = true, GetGameTimer(), false
    clearPrompts()

    local ease = now and 0 or CFG.camera.easeOut
    if cam then RenderScriptCams(false, ease > 0, ease, true, false) end
    ClearPedTasks(cache.ped)

    SetTimeout(ease, function()
        if active == a then active = nil end
        if cam and not active then
            DestroyCam(cam, false)
            cam = nil
        end
        lock(false)
        toDui(a.slot, { action = 'render', screen = 'off' })
    end)
end

-------------------------------------------------------------------------------
-- Doing things
-------------------------------------------------------------------------------
local function openAmount(a, verb)
    local max = amountMax(a, verb)
    local list = steps(max)
    a.amt = { verb = verb, max = max, list = list, idx = #list, value = list[#list] or 0, focus = 'box' }
    a.view = 'amount'
end

local function setStep(m, idx)
    m.idx = math.max(1, math.min(#m.list, idx))
    m.value = m.list[m.idx] or 0
    m.custom, m.error = false, nil
end

--- Left/right. From a typed amount it lands on the nearest step that way.
local function nudge(m, dir)
    if #m.list == 0 then return end
    if m.custom then
        if dir < 0 then
            for i = #m.list, 1, -1 do
                if m.list[i] < m.value then return setStep(m, i) end
            end
            return setStep(m, 1)
        end
        for i = 1, #m.list do
            if m.list[i] > m.value then return setStep(m, i) end
        end
        return setStep(m, #m.list)
    end
    setStep(m, m.idx + dir)
end

--- A DUI page takes no keystrokes, so an exact amount is typed into a normal input dialog.
local function typeAmount(a)
    local m = a.amt
    if a.typing or m.max <= 0 then return end
    a.typing = true
    render()

    CreateThread(function()
        local answer = lib.inputDialog(m.verb == 'deposit' and 'Deposit' or 'Withdraw', {
            { type = 'number', label = ('Amount (up to $%d)'):format(m.max), min = 1, max = m.max, default = m.value, required = true },
        })
        if active ~= a or a.amt ~= m then return end
        a.typing = false

        local v = answer and tonumber(answer[1])
        if v then
            v = math.floor(math.max(1, math.min(m.max, v)))
            m.value, m.error = v, nil
            m.custom = v ~= m.max
            if not m.custom then m.idx = #m.list end
            m.focus = 'confirm'
        end
        render()
    end)
end

local function submit(a)
    local m = a.amt
    if a.busy then return end
    if m.max <= 0 or m.value < 1 then
        m.error = m.verb == 'deposit' and "You don't have any cash on you" or 'There is nothing to withdraw'
        return render()
    end

    a.busy = true
    render()

    CreateThread(function()
        local acc = account(a)
        local res = lib.callback.await('Renewed-Banking:server:' .. m.verb, false, { fromAccount = acc.id, amount = m.value, comment = '' })
        if active ~= a or a.closing then return end
        a.busy = false

        if type(res) == 'table' and res[1] then
            a.accounts = res
            if a.acc > #res then a.acc = 1 end
            a.view = 'splash'
            render()
            Wait(CFG.splashMs or 2600)
            if active == a then BankATM.close() end
        else
            m.error = m.verb == 'deposit' and "You don't have that much cash" or 'Insufficient funds'
            render()
        end
    end)
end

local function back(a)
    if a.busy then return end
    if a.view == 'menu' or a.view == 'welcome' then return BankATM.close() end
    if a.view == 'amount' or a.view == 'history' then
        a.view, a.amt, a.hist = 'menu', nil, nil
        render()
    end
end

-------------------------------------------------------------------------------
-- Input
-------------------------------------------------------------------------------
-- Arrows and the pad's d-pad / stick through the frontend controls, WASD as well, Enter / A, Backspace / Esc / B.
local K = {
    up = { 172, 188, 32 }, down = { 173, 187, 33 }, left = { 174, 189, 34 }, right = { 175, 190, 35 },
    select = { 191, 201, 176 }, back = { 194, 202, 177, 200 },
    all = { 203 }, type = { 204 }, prev = { 205 }, next = { 206 },
}

local function hit(name)
    local list = K[name]
    for i = 1, #list do
        if IsDisabledControlJustPressed(0, list[i]) then return true end
    end
    return false
end

local function handleInput(a)
    if hit('back') then return back(a) end
    if a.busy then return end

    if a.view == 'menu' then
        if hit('up') then
            a.menu = (a.menu - 2) % #MENU + 1
        elseif hit('down') then
            a.menu = a.menu % #MENU + 1
        elseif #a.accounts > 1 and hit('next') then
            a.acc = a.acc % #a.accounts + 1
        elseif #a.accounts > 1 and hit('prev') then
            a.acc = (a.acc - 2) % #a.accounts + 1
        elseif hit('select') then
            local item = MENU[a.menu]
            if item == 'Transactions' then
                a.hist = { items = historyItems(account(a)), focus = 1 }
                a.view = 'history'
            else
                openAmount(a, item:lower())
            end
        else
            return
        end
        return render()
    end

    if a.view == 'amount' then
        local m = a.amt
        if hit('all') then
            if m.max > 0 then setStep(m, #m.list) end
        elseif m.focus == 'box' then
            if hit('left') then nudge(m, -1)
            elseif hit('right') then nudge(m, 1)
            elseif hit('down') or hit('select') then m.focus = 'confirm'
            elseif hit('type') and not usingPad() then return typeAmount(a)
            else return end
        elseif m.focus == 'confirm' then
            if hit('up') then m.focus = 'box'
            elseif hit('left') then m.focus = 'back'
            elseif hit('select') then return submit(a)
            else return end
        else -- the Back button
            if hit('up') then m.focus = 'box'
            elseif hit('right') then m.focus = 'confirm'
            elseif hit('select') then return back(a)
            else return end
        end
        return render()
    end

    if a.view == 'history' then
        local h = a.hist
        if hit('up') and h.focus > 1 then h.focus = h.focus - 1
        elseif hit('down') and h.focus < #h.items then h.focus = h.focus + 1
        else return end
        return render()
    end
end

local function frameLoop(a)
    local lastPad, nextCheck = nil, 0

    while active == a do
        local ped = cache.ped
        local now = GetGameTimer()
        drawScreen(a.g, a.slot)

        -- The camera ends up where the player's head is, so the ped is hidden once it is most of the way in, and
        -- shown again a little way into the pull back.
        if a.camAt and ((not a.closing and now - a.camAt > CFG.camera.easeIn * 0.45)
            or (a.closing and now - a.closedAt < CFG.camera.easeOut * 0.35)) then
            SetEntityLocallyInvisible(ped)
        end

        if not a.closing and not a.typing then
            DisableAllControlActions(0)
            DisableControlAction(0, 199, true)   -- P / Esc would open the pause menu; Esc is "back" here
            DisableControlAction(0, 200, true)

            if IsEntityDead(ped) or IsPedRagdoll(ped) or #(GetEntityCoords(ped) - a.g.center) > 3.0 then
                BankATM.close(true)
            else
                handleInput(a)
                if now >= nextCheck then
                    nextCheck = now + 250
                    local pad = usingPad()
                    if pad ~= lastPad then
                        lastPad = pad
                        setPrompts(promptList(a))
                    end
                end
            end
        end

        Wait(0)
    end
end

-------------------------------------------------------------------------------
-- Starting one
-------------------------------------------------------------------------------
--- Up to the machine, square on to it.
local function walkUp(ped, entity, screen, a)
    local spot = GetOffsetFromEntityInWorldCoords(entity, screen.stand.x, screen.stand.y, 0.0)
    local heading = GetEntityHeading(entity)   -- the glass faces the prop's back (-y), so the user faces its heading
    local here = GetEntityCoords(ped)

    if #(vec2(here.x, here.y) - vec2(spot.x, spot.y)) > 0.3 then
        TaskGoStraightToCoord(ped, spot.x, spot.y, here.z, 1.0, 3000, heading, 0.1)
        local deadline = GetGameTimer() + 3000
        while active == a and GetGameTimer() < deadline do
            Wait(50)
            local p = GetEntityCoords(ped)
            if #(vec2(p.x, p.y) - vec2(spot.x, spot.y)) < 0.25 then break end
        end
    end

    if active ~= a then return end
    TaskAchieveHeading(ped, heading, 700)
    Wait(700)
end

--- Straight on to the glass, close enough that it fills Config.atm.camera.fill of the view's height.
local function startCamera(g)
    local fov = CFG.camera.fov
    local dist = (g.h / 2) / math.tan(math.rad(fov) / 2) / CFG.camera.fill
    local pos = g.center + g.normal * dist

    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, fov, false, 2)
    PointCamAtCoord(cam, g.center.x, g.center.y, g.center.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, CFG.camera.easeIn, true, false)
end

--- @return boolean true if the ATM screen took it, false if the caller should open the popup
function BankATM.open(entity)
    if not CFG or CFG.mode ~= 'dui' then return false end
    if active then return true end
    if type(entity) ~= 'number' or entity == 0 or not DoesEntityExist(entity) then return false end

    local screen = CFG.screens[GetEntityModel(entity)]
    if not screen then return false end

    local slot = ensureSlot(screen)
    if not slot then return false end

    local waited = 0
    while not IsDuiAvailable(slot.dui) and waited < 3000 do
        Wait(50)
        waited = waited + 50
    end
    if not IsDuiAvailable(slot.dui) then return false end

    local accounts = lib.callback.await('renewed-banking:server:initalizeBanking', false)
    if type(accounts) ~= 'table' or not accounts[1] then
        lib.notify({ title = locale('bank_name'), description = locale('loading_failed'), type = 'error' })
        return true
    end
    if active then return true end

    local ped = cache.ped
    local a = {
        entity = entity, screen = screen, slot = slot, g = geometry(entity, screen),
        accounts = accounts, acc = 1, view = 'welcome', menu = 1,
    }
    active = a
    lock(true)
    render()

    CreateThread(function() frameLoop(a) end)
    CreateThread(function()
        -- Heartbeat: the page drops a render identical to the last, so this only matters to a page that loaded late.
        while active == a do
            Wait(a.slot.ready and 1000 or 150)
            if active == a then toDui(a.slot, payload(a)) end
        end
    end)

    walkUp(ped, entity, screen, a)
    if active ~= a or a.closing then return true end

    TaskStartScenarioInPlace(ped, 'PROP_HUMAN_ATM', 0, true)
    startCamera(a.g)
    a.camAt = GetGameTimer()

    Wait(CFG.camera.easeIn + 250)
    if active == a and not a.closing and a.view == 'welcome' then
        a.view = 'menu'
        render()
    end
    return true
end

function BankATM.isOpen() return active ~= nil end

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    if active then
        RenderScriptCams(false, false, 0, true, false)
        if cam then DestroyCam(cam, false) end
        ClearPedTasks(cache.ped)
        clearPrompts()
        lock(false)
        active = nil
    end
    for _, s in pairs(pool) do
        if s.dui then DestroyDui(s.dui) end
    end
end)
