-- Rampage start points, carried over from StreetKings' data/events.lua (the
-- entries with type = EventType.RAMPAGE). The rest of that file is race and
-- delivery events, which this resource covers with data/races.lua instead.
--
-- `duration` is the time limit in seconds. Omit it and Config.Rampage.durationSec
-- is used; the values below are the ones upstream shipped these locations with.

SKRampages = {
    rampage_del_perro = {
        id       = 'rampage_del_perro',
        name     = 'Del Perro Rampage',
        start    = vector4(-1841.7855, -1226.3541, 12.5109, 312.9970),
        duration = 150,
    },

    rampage_terminal = {
        id       = 'rampage_terminal',
        name     = 'Terminal Rampage',
        start    = vector4(-1821.2888, -2808.8928, 13.3479, 147.3008),
        duration = 150,
    },

    rampage_mirror_park = {
        id       = 'rampage_mirror_park',
        name     = 'Mirror Park Madness',
        start    = vector4(1383.8683, -600.1317, 73.7403, 53.8033),
        duration = 150,
    },

    rampage_downtown = {
        id       = 'rampage_downtown',
        name     = 'Downtown Disaster',
        start    = vector4(298.8658, 196.4773, 103.7166, 158.6516),
        duration = 150,
    },

    rampage_stab_city = {
        id       = 'rampage_stab_city',
        name     = 'Stab City Mayhem',
        start    = vector4(82.0353, 3753.0422, 39.1527, 176.8056),
        duration = 150,
    },
}
