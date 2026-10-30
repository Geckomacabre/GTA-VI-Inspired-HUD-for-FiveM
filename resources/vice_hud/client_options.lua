--[[
    vice_hud — the player's own switches

    The rows of HUD OPTIONS (hold V, from vi_extras; and vi_pausemenu's
    Settings) that are this resource's features, as single player's HUD
    OPTIONS has them. Each is defined beside its feature:

      CROSSHAIR, KILL MARKS        client_overlays.lua
      VI WANTED STARS, WANTED BOX  client.lua, the wanted block
      POLICE LIGHTS                client.lua: the police editor's Size row,
                                   kept with the rest of that panel's settings
      GREET / ANTAGONIZE           honor/client/conduct.lua, which keeps its own
                                   (honor also runs on its own, as qbx_honor)

    A switch is the server's Config value until the player changes it, then
    the player's: kept in this resource's KVP, so it is there again on the
    next join, with or without vi_extras. A change takes at once: the feature
    reads its switch where it runs, and what has to come off the screen there
    and then is done by the onChange its file hands in.

    First in the manifest, so every client file after it can define switches.
]]

ViceOptions = {}

--- A switch the player keeps, ViceOptions[name] at run time. Registers the
--- exports Get<name>() -> bool and Set<name>(bool), saved under `key` as
--- 'on' / 'off'. `default` is the server's Config value; `onChange(on)` runs
--- after every Set, for what the feature has to do at once (take down what
--- it drew, give back what it took over from GTA).
function ViceOption(name, key, default, onChange)
    local saved = GetResourceKvpString(key)
    if saved == 'on' then ViceOptions[name] = true
    elseif saved == 'off' then ViceOptions[name] = false
    else ViceOptions[name] = default and true or false end

    exports('Get' .. name, function() return ViceOptions[name] end)
    exports('Set' .. name, function(on)
        on = on == true
        ViceOptions[name] = on
        SetResourceKvp(key, on and 'on' or 'off')
        if onChange then onChange(on) end
    end)
end
