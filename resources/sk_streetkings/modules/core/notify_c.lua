-- SKNotify shim.
--
-- StreetKings routed notifications through its own NUI toast component
-- (modules/notify/notify_c.lua). Ported modules call SKNotify(...) in a lot of
-- places, so the signature is kept and forwarded to ox_lib, which means every
-- notification inherits the server's ox_lib theme.

local TYPE_MAP = {
    info    = 'inform',
    inform  = 'inform',
    success = 'success',
    error   = 'error',
    warning = 'warning',
    warn    = 'warning',
}

---@param options { title: string, description: string?, type: string?, duration: integer? }
function SKNotify(options)
    if type(options) ~= 'table' then return end
    lib.notify({
        title       = options.title,
        description = options.description,
        type        = TYPE_MAP[options.type or 'info'] or 'inform',
        duration    = options.duration or 3000,
        position    = options.position,
    })
end

exports('ShowNotification', SKNotify)
