-- Spray can colour picker (paint room). The upgrade menu callbacks are in client/menu.lua.
RegisterNUICallback('CustomPaint', function(data, cb)
    Config.Pilox['custom'] = {data.r,data.g,data.b}
    cb(true)
end)

RegisterNUICallback('CustomPaintDone', function(data, cb)
    custompaint = true
    SetNuiFocus(false,false)
    cb(true)
end)
