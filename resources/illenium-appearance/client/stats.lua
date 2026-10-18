local stats = nil

function BackupPlayerStats()
    stats = {
        health = GetEntityHealth(cache.ped),
        armour = GetPedArmour(cache.ped)
    }
end

function RestorePlayerStats()
    if stats then
        SetEntityMaxHealth(cache.ped, 200)
        Wait(1000) -- Safety Delay
        SetEntityHealth(cache.ped, stats.health)
        SetPedArmour(cache.ped, stats.armour)
        -- [Upstate Mafia] Used to call ResetRechargeMultipliers() here, which
        -- despite the name set SetPlayerHealthRechargeMultiplier/-Limit to
        -- 0.0 -- permanently killing native passive health regen from that
        -- point on, every single time this ran. This is BackupPlayerStats'
        -- counterpart and runs on every outfit change / mirror exit /
        -- character creation, not just once, so one visit to any clothing
        -- menu was enough to silently disable regen for the rest of the
        -- session. Nothing else in this codebase ever sets those natives
        -- back to a real value, and vice_hud's own hunger/thirst system
        -- (client_vitals.lua's enforceCap) is built entirely around passive
        -- regen actually happening and gating it -- this call was fighting
        -- that, not supporting it. Just don't touch the recharge natives at
        -- all; leave GTA's own default alone.
        stats = nil
        return
    end

    -- If no stats are backed up, restore from the framework
    Framework.RestorePlayerArmour()
end
