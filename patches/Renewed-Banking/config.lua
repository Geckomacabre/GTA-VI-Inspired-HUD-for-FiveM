lib.locale()
Config = {
    -- Framework automatically detected
    -- QB, QBX, and ESX preconfigured edit the framework.lua to add functionality to other frameworks
    renewedMultiJob = false, -- QBCORE ONLY! https://github.com/Renewed-Scripts/qb-phone  
    progressbar = 'circle', -- circle or rectangle (Anything other than circle will default to rectangle)
    currency = 'USD', -- USD, EUR, GBP ect.....
    atms = {
        `prop_atm_01`,
        `prop_atm_02`,
        `prop_atm_03`,
        `prop_fleeca_atm`
    },
    peds = {
        [1] = { -- Pacific Standard
            model = 'u_m_m_bankman',
            coords = vector4(241.44, 227.19, 106.29, 170.43),
            createAccounts = true
        },
        [2] = {
            model = 'ig_barry',
            coords = vector4(313.84, -280.58, 54.16, 338.31)
        },
        [3] = {
            model = 'ig_barry',
            coords = vector4(149.46, -1042.09, 29.37, 335.43)
        },
        [4] = {
            model = 'ig_barry',
            coords = vector4(-351.23, -51.28, 49.04, 341.73)
        },
        [5] = {
            model = 'ig_barry',
            coords = vector4(-1211.9, -331.9, 37.78, 20.07)
        },
        [6] = {
            model = 'ig_barry',
            coords = vector4(-2961.14, 483.09, 15.7, 83.84)
        },
        [7] = {
            model = 'ig_barry',
            coords = vector4(1174.8, 2708.2, 38.09, 178.52)
        },
        [8] = { -- paleto
            model = 'u_m_m_bankman',
            coords = vector4(-112.22, 6471.01, 31.63, 134.18),
            createAccounts = true
        }
    },

    -- BEGIN (added by GTA VI Resources: the BuckMe ATM)
    -- The BuckMe ATM (client/atm.lua, web/atm/). The cash machine's own screen turns into the BuckMe page and the
    -- camera pushes in on it, GTA VI style. 'dui' = that; 'nui' = the old full-screen popup at ATMs too. A model
    -- not listed under `screens` (or a DUI that fails) also gets the popup. Bank tellers always use the popup.
    atm = {
        mode = 'dui',
        limit = 15000,                 -- most you can move in one go at an ATM (shown on the amount screen)
        amounts = { 10, 20, 50, 100, 250, 500, 1000, 2500, 5000, 10000 }, -- the steps left/right walks through, below "Maximum"
        splashMs = 2600,               -- "Thank you for bucking with us" before the camera pulls back
        resolution = 1024,             -- DUI width in px; height follows each screen's own shape
        camera = {
            fov = 40.0,
            fill = 0.74,               -- how much of the view's height the ATM screen takes up
            easeIn = 1200,
            easeOut = 1000,
        },
        -- Each machine's screen, measured from the game's own models (the screen geometry in prop_atm_01.yft and
        -- prop_atm_02/03 / prop_fleeca_atm.ydr), in the prop's local space: x right, y toward the back, z up. The
        -- glass faces -y and leans back ~14 degrees; the corners sit a few mm in front of its bulge so the page is
        -- never buried in it. `stand` is where the player walks to before using it.
        screens = {
            [`prop_atm_01`] = {
                tl = vec3(-0.166, -0.123, 1.176), tr = vec3(0.058, -0.123, 1.176),
                bl = vec3(-0.166, -0.154, 0.996), br = vec3(0.058, -0.154, 0.996),
                stand = vec2(-0.054, -0.75),
            },
            [`prop_atm_02`] = {
                tl = vec3(-0.285, 0.119, 1.258), tr = vec3(0.042, 0.119, 1.258),
                bl = vec3(-0.285, 0.058, 1.022), br = vec3(0.042, 0.058, 1.022),
                stand = vec2(-0.121, -0.62),
            },
            [`prop_atm_03`] = {
                tl = vec3(-0.285, 0.102, 1.265), tr = vec3(0.042, 0.102, 1.265),
                bl = vec3(-0.285, 0.041, 1.029), br = vec3(0.042, 0.041, 1.029),
                stand = vec2(-0.121, -0.62),
            },
            [`prop_fleeca_atm`] = {
                tl = vec3(-0.285, 0.131, 1.279), tr = vec3(0.042, 0.131, 1.279),
                bl = vec3(-0.285, 0.065, 1.023), br = vec3(0.042, 0.065, 1.023),
                stand = vec2(-0.121, -0.62),
            },
        },
    },
    -- END
}
