-- Honor was the qbx_honor resource, and other scripts call it by that name:
-- exports.qbx_honor:AddHonor(...). An export is looked up through an event
-- named after the literal resource, which `provide 'qbx_honor'` does not
-- alias, so every honor export is registered twice: as vice_hud's, and under
-- the old name.
function HonorExport(name, fn)
    exports(name, fn)
    AddEventHandler(('__cfx_export_qbx_honor_%s'):format(name), function(setCB)
        setCB(fn)
    end)
end
