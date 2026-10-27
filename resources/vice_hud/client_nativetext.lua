--[[
    vice_hud — native text:  the game's own help messages, shown in vice_hud's
    help box instead of GTA V's black one, and subtitles that wait for the
    line to actually be spoken.

    Ported from FBICat's single-player GTA6Hud (its HelpText and Subtitles)
    on 2026-10-18. Neither draws anything new: help text goes through the
    existing ShowHelpText box, subtitles through the existing ShowSubtitle
    line, both exactly as the reference draws them.

    Its own chunk for the reason at the top of client_overlays.lua (Lua's
    200-top-level-locals limit). It talks to the rest of the resource only
    through vice_hud's own exports.
]]

-- =============================================================================
-- Native help text
-- =============================================================================
-- A script that shows help the native way (BEGIN_TEXT_COMMAND_DISPLAY_HELP)
-- gets GTA V's black box, top left -- the one thing on screen still in the
-- old style. The game has no way to read the current help text back, so,
-- like the single-player build, this identifies it: while a help message is
-- up, it asks "is it THIS label?" (BEGIN/END_TEXT_COMMAND_IS_THIS_HELP_
-- MESSAGE_BEING_DISPLAYED) of a list of labels, the most recently matched
-- first, the rest round-robin at `scanPerFrame` a frame. Once one answers,
-- the native box is hidden for as long as it stays up and the label's text
-- goes into vice_hud's help box, its ~INPUT_...~ buttons drawn as the help
-- box draws any button.
--
-- What it cannot do, and so leaves to the native box:
--   - help shown as a raw 'STRING' with the text pushed in as a component
--     (no label to ask about -- most FiveM scripts that use native help do
--     this; resources that use a label via AddTextEntry, as ESX's
--     esxHelpNotification does, are found);
--   - a label whose text has a ~a~ slot: the words that fill it are not
--     readable, and showing the line with a hole in it would be wrong.
--
-- The labels: Config.NativeHelp.labels first (a server's own), then
-- data/help_labels.txt, the single-player GTA6Hud's list of GTA V's (FBICat's).
do
local cfg = Config.NativeHelp or {}
if cfg.enable ~= false then
    -- ~INPUT_X~ -> control index, for the buttons the help box can draw.
    -- Anything not here is dropped from the line, as the original did.
    local INPUTS = {
        INPUT_CONTEXT = 51, INPUT_CONTEXT_SECONDARY = 52, INPUT_PICKUP = 38,
        INPUT_DETONATE = 47, INPUT_ENTER = 23, INPUT_ATTACK = 24, INPUT_AIM = 25,
        INPUT_SPRINT = 21, INPUT_JUMP = 22, INPUT_DUCK = 36, INPUT_COVER = 44,
        INPUT_RELOAD = 45, INPUT_TALK = 46, INPUT_SELECT_WEAPON = 37,
        INPUT_MULTIPLAYER_INFO = 20, INPUT_LOOK_BEHIND = 26, INPUT_SPECIAL_ABILITY = 28,
        INPUT_VEH_EXIT = 75, INPUT_VEH_HANDBRAKE = 76, INPUT_VEH_HEADLIGHT = 74,
        INPUT_VEH_HORN = 86, INPUT_VEH_ACCELERATE = 71, INPUT_VEH_BRAKE = 72,
        INPUT_VEH_DUCK = 73, INPUT_VEH_CIN_CAM = 80, INPUT_VEH_NEXT_RADIO = 81,
        INPUT_INTERACTION_MENU = 244, INPUT_FRONTEND_ACCEPT = 201,
        INPUT_FRONTEND_CANCEL = 202, INPUT_FRONTEND_PAUSE = 199,
        INPUT_FRONTEND_UP = 172, INPUT_FRONTEND_DOWN = 173,
        INPUT_FRONTEND_LEFT = 174, INPUT_FRONTEND_RIGHT = 175,
        INPUT_CELLPHONE_UP = 172, INPUT_CELLPHONE_DOWN = 173,
        INPUT_CELLPHONE_SELECT = 176, INPUT_CELLPHONE_CANCEL = 177,
    }

    --- GXT text -> the help box's own markup ([[n]] for a button) and the
    --- control list for it, or nil when the line cannot be shown faithfully.
    --- Global only so tools/nativetext.test.js can reach it; nothing else uses it.
    function ViceHelpConvert(raw)
        if type(raw) ~= 'string' or raw == '' or raw == 'NULL' then return nil end
        local out, keys, i = {}, {}, 1
        while i <= #raw do
            local a = raw:find('~', i, true)
            if not a then out[#out + 1] = raw:sub(i) break end
            out[#out + 1] = raw:sub(i, a - 1)
            local b = raw:find('~', a + 1, true)
            if not b then break end
            local tok = raw:sub(a + 1, b - 1)
            i = b + 1
            if tok == 'a' or tok == '1' then
                return nil                      -- a slot we cannot fill
            elseif tok == 'n' then
                out[#out + 1] = '\n'
            elseif INPUTS[tok] then
                keys[#keys + 1] = INPUTS[tok]
                out[#out + 1] = '[[' .. #keys .. ']]'
            end
            -- colours, ~h~, ~s~, blips and unknown inputs: dropped
        end
        local text = table.concat(out):gsub('[ \t]+', ' '):gsub(' ?\n ?', '\n')
        text = text:match('^%s*(.-)%s*$')
        if text == '' then return nil end
        return text, keys
    end

    local labels, seen = {}, {}
    local function add(label)
        label = type(label) == 'string' and label:match('^%s*(.-)%s*$') or ''
        if label ~= '' and not label:find('^[;#]') and not seen[label] then
            seen[label] = true
            labels[#labels + 1] = label
        end
    end
    for _, l in ipairs(cfg.labels or {}) do add(l) end
    local file = LoadResourceFile(GetCurrentResourceName(), 'data/help_labels.txt')
    if file then for line in file:gmatch('[^\r\n]+') do add(line) end end

    local perFrame = math.max(1, tonumber(cfg.scanPerFrame) or 40)
    local recentMax = math.max(1, tonumber(cfg.recent) or 24)
    local recent = {}          -- most recently matched first
    local cursor = 1
    local match = nil          -- the label on screen now
    local matchRaw = nil       -- its text when last read (ESX-style labels change)
    local showing = false      -- whether vice_hud's box is showing it
    local shownSerial = nil    -- HelpTextSerial right after we showed it
    local nextRead = 0

    local function displayed(label)
        BeginTextCommandIsThisHelpMessageBeingDisplayed(label)
        return EndTextCommandIsThisHelpMessageBeingDisplayed(0)
    end

    local function release()
        -- Only take the box down if nobody has put something else in it since.
        if showing and HelpTextSerial == shownSerial then
            exports.vice_hud:ShowHelpText(nil)
        end
        showing, shownSerial = false, nil
    end

    local function present(label)
        local raw = GetLabelText(label)
        matchRaw = raw
        local text, keys = ViceHelpConvert(raw)
        if not text then
            release()                         -- leave this one to the native box
            return
        end
        exports.vice_hud:ShowHelpText(text, 0, { keys = keys })
        showing, shownSerial = true, HelpTextSerial
    end

    local function accept(label)
        match = label
        for k = #recent, 1, -1 do if recent[k] == label then table.remove(recent, k) end end
        table.insert(recent, 1, label)
        while #recent > recentMax do table.remove(recent) end
        present(label)
        nextRead = GetGameTimer() + 250
    end

    CreateThread(function()
        while true do
            if #labels == 0 or not IsHelpMessageBeingDisplayed() then
                if match then match = nil; release() end
                Wait(100)
            else
                Wait(0)
                if match and displayed(match) then
                    -- Re-read now and then: a label set with AddTextEntry can
                    -- be given new words while it stays on screen.
                    if GetGameTimer() >= nextRead then
                        nextRead = GetGameTimer() + 250
                        if GetLabelText(match) ~= matchRaw then present(match) end
                    end
                else
                    if match then match = nil; release() end
                    for _, l in ipairs(recent) do
                        if displayed(l) then accept(l) break end
                    end
                    if not match then
                        for _ = 1, math.min(perFrame, #labels) do
                            local l = labels[cursor]
                            cursor = cursor % #labels + 1
                            if displayed(l) then accept(l) break end
                        end
                    end
                end
                if showing then HideHudComponentThisFrame(10) end
            end
        end
    end)
end
end

-- =============================================================================
-- Spoken subtitles
-- =============================================================================
-- From the single-player GTA6Hud's Subtitles: a subtitle that belongs to a
-- line of speech appears when the ped starts speaking and goes when they
-- stop, rather than on a timer that has nothing to do with the voice.
--
--   exports.vice_hud:ShowSpokenSubtitle(ped, text, opts)
--     opts.context  a speech context to play on the ped first (e.g.
--                   'GENERIC_HI'), with opts.params (default
--                   'SPEECH_PARAMS_FORCE_SHOUTED'). Leave out when the caller
--                   plays the speech itself.
--     opts.maxMs    longest it can stay up (default 8000)
--
-- Shown only once IS_ANY_SPEECH_PLAYING is true for that ped; dropped if the
-- ped has not started within 700 ms, or is more than 30 m away (someone that
-- far off is not who the player is listening to). Hidden 450 ms after the
-- speech stops. The words are the caller's: GTA picks a random recording for
-- a context, so the single-player build's stock lines per context were a
-- guess at what was said, and are not carried over.
do
local HEAR_RANGE = 30.0
local START_WITHIN_MS = 700
local SILENCE_MS = 450
local token = 0

exports('ShowSpokenSubtitle', function(ped, text, opts)
    opts = type(opts) == 'table' and opts or {}
    if not ped or ped == 0 or not DoesEntityExist(ped) or not text or text == '' then return end
    local me = cache.ped or PlayerPedId()
    if ped ~= me and #(GetEntityCoords(me) - GetEntityCoords(ped)) > HEAR_RANGE then return end

    if type(opts.context) == 'string' then
        PlayPedAmbientSpeechNative(ped, opts.context, opts.params or 'SPEECH_PARAMS_FORCE_SHOUTED')
    end

    token = token + 1
    local mine = token
    local maxMs = tonumber(opts.maxMs) or 8000
    CreateThread(function()
        local asked = GetGameTimer()
        while not IsAnySpeechPlaying(ped) do
            if mine ~= token or not DoesEntityExist(ped)
               or GetGameTimer() - asked > START_WITHIN_MS then return end
            Wait(0)
        end
        if mine ~= token then return end
        exports.vice_hud:ShowSubtitle(text, 0)
        local serial = SubtitleSerial
        local shown, silentSince = GetGameTimer(), nil
        while mine == token and SubtitleSerial == serial do
            Wait(50)
            local now = GetGameTimer()
            if DoesEntityExist(ped) and IsAnySpeechPlaying(ped) then
                silentSince = nil
            else
                silentSince = silentSince or now
            end
            if (silentSince and now - silentSince > SILENCE_MS) or now - shown > maxMs then
                if SubtitleSerial == serial then exports.vice_hud:ShowSubtitle(nil) end
                return
            end
        end
        -- Something else took over the line (a newer spoken subtitle, or any
        -- ShowSubtitle call); it is theirs now, so it is left alone.
    end)
end)
end
