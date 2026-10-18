local client = client

RegisterNUICallback("appearance_get_locales", function(_, cb)
    cb(Locales[GetConvar("illenium-appearance:locale", "en")].UI)
end)

RegisterNUICallback("appearance_get_settings", function(_, cb)
    cb({ appearanceSettings = client.getAppearanceSettings() })
end)

RegisterNUICallback("appearance_get_data", function(_, cb)
    Wait(250)
    local appearanceData = client.getAppearance()
    if appearanceData.tattoos then
        client.setPedTattoos(cache.ped, appearanceData.tattoos)
    end
    local cash = 0
    local bank = 0
    if GetResourceState("qbx_core") == "started" and exports.qbx_core then
        local pData = exports.qbx_core:GetPlayerData()
        if pData and pData.money then
            cash = pData.money.cash or 0
            bank = pData.money.bank or 0
        end
    elseif GetResourceState("qb-core") == "started" then
        local QBCore = exports["qb-core"]:GetCoreObject()
        local pData = QBCore and QBCore.Functions.GetPlayerData()
        if pData and pData.money then
            cash = pData.money.cash or 0
            bank = pData.money.bank or 0
        end
    elseif GetResourceState("es_extended") == "started" then
        local ESX = exports["es_extended"]:getSharedObject()
        local pData = ESX and ESX.GetPlayerData()
        if pData and pData.accounts then
            for _, acc in ipairs(pData.accounts) do
                if acc.name == "money" or acc.name == "cash" then
                    cash = acc.money or 0
                elseif acc.name == "bank" then
                    bank = acc.money or 0
                end
            end
        end
    end
    cb({ config = client.getConfig(), appearanceData = appearanceData, appearanceSettings = client.getAppearanceSettings(), money = { cash = cash, bank = bank }, theme = Config.Theme })
end)

RegisterNUICallback("appearance_set_camera", function(camera, cb)
    cb(1)
    client.setCamera(camera)
end)

RegisterNUICallback("appearance_turn_around", function(_, cb)
    cb(1)
    client.pedTurn(cache.ped, 180.0)
end)

RegisterNUICallback("appearance_rotate_camera", function(direction, cb)
    cb(1)
    client.rotateCamera(direction)
end)

RegisterNUICallback("appearance_adjust_camera", function(data, cb)
    cb(1)
    if type(data) == "table" then
        if data.height then
            client.adjustCameraHeight(data.height)
        end
        if data.zoom then
            client.adjustCameraZoom(data.zoom)
        end
    elseif data == "up" then
        client.adjustCameraHeight(0.08)
    elseif data == "down" then
        client.adjustCameraHeight(-0.08)
    elseif data == "zoom_in" then
        client.adjustCameraZoom(-0.1)
    elseif data == "zoom_out" then
        client.adjustCameraZoom(0.1)
    end
end)

RegisterNUICallback("appearance_change_model", function(model, cb)
    local playerPed = client.setPlayerModel(model)

    SetEntityHeading(cache.ped, client.getHeading())
    SetEntityInvincible(playerPed, true)
    TaskStandStill(playerPed, -1)

    cb({
        appearanceSettings = client.getAppearanceSettings(),
        appearanceData = client.getPedAppearance(playerPed)
    })
end)

RegisterNUICallback("appearance_change_component", function(component, cb)
    client.setPedComponent(cache.ped, component)
    cb(client.getComponentSettings(cache.ped, component.component_id))
end)

RegisterNUICallback("appearance_change_prop", function(prop, cb)
    client.setPedProp(cache.ped, prop)
    cb(client.getPropSettings(cache.ped, prop.prop_id))
end)

RegisterNUICallback("appearance_change_head_blend", function(headBlend, cb)
    cb(1)
    client.setPedHeadBlend(cache.ped, headBlend)
end)

RegisterNUICallback("appearance_change_face_feature", function(faceFeatures, cb)
    cb(1)
    client.setPedFaceFeatures(cache.ped, faceFeatures)
end)

RegisterNUICallback("appearance_change_head_overlay", function(headOverlays, cb)
    cb(1)
    client.setPedHeadOverlays(cache.ped, headOverlays)
end)

RegisterNUICallback("appearance_change_hair", function(hair, cb)
    client.setPedHair(cache.ped, hair)
    cb(client.getHairSettings(cache.ped))
end)

RegisterNUICallback("appearance_change_eye_color", function(eyeColor, cb)
    cb(1)
    client.setPedEyeColor(cache.ped, eyeColor)
end)

RegisterNUICallback("appearance_apply_tattoo", function(data, cb)
    local paid = not data.tattoo or not Config.ChargePerTattoo or lib.callback.await("illenium-appearance:server:payForTattoo", false, data.tattoo)
    if paid then
        client.addPedTattoo(cache.ped, data.updatedTattoos or data)
    end
    cb(paid)
end)

RegisterNUICallback("appearance_preview_tattoo", function(previewTattoo, cb)
    cb(1)
    client.setPreviewTattoo(cache.ped, previewTattoo.data, previewTattoo.tattoo)
end)

RegisterNUICallback("appearance_delete_tattoo", function(data, cb)
    cb(1)
    client.removePedTattoo(cache.ped, data)
end)

RegisterNUICallback("appearance_wear_clothes", function(dataWearClothes, cb)
    cb(1)
    client.wearClothes(dataWearClothes.data, dataWearClothes.key)
end)

RegisterNUICallback("appearance_remove_clothes", function(clothes, cb)
    cb(1)
    client.removeClothes(clothes)
end)

RegisterNUICallback("appearance_save", function(data, cb)
    cb(1)
    local appearance = client.getPedAppearance(cache.ped)
    if type(data) == "table" then
        appearance.paymentMethod = data.paymentMethod
        appearance.cost = data.cost
    end
    client.exitPlayerCustomization(appearance)
end)

RegisterNUICallback("appearance_exit", function(_, cb)
    cb(1)
    client.exitPlayerCustomization()
end)

RegisterNUICallback("rotate_left", function(_, cb)
    cb(1)
    client.pedTurn(cache.ped, 10.0)
end)

RegisterNUICallback("rotate_right", function(_, cb)
    cb(1)
    client.pedTurn(cache.ped, -10.0)
end)

RegisterNUICallback("get_theme_configuration", function(_, cb)
    cb(Config.Theme)
end)

RegisterNUICallback("appearance_get_outfits", function(_, cb)
    lib.callback("illenium-appearance:server:getOutfits", false, function(outfits)
        cb(outfits or {})
    end)
end)

RegisterNUICallback("appearance_save_outfit", function(data, cb)
    local outfitName = data and data.name
    if not outfitName or outfitName == "" then
        cb({ error = "Name required" })
        return
    end
    local pedModel = client.getPedModel(cache.ped)
    local pedComponents = client.getPedComponents(cache.ped)
    local pedProps = client.getPedProps(cache.ped)
    TriggerServerEvent("illenium-appearance:server:saveOutfit", outfitName, pedModel, pedComponents, pedProps)

    Wait(300)
    lib.callback("illenium-appearance:server:getOutfits", false, function(outfits)
        cb(outfits or {})
    end)
end)

RegisterNUICallback("appearance_load_outfit", function(data, cb)
    cb(1)
    if data then
        if data.components then
            client.setPedComponents(cache.ped, data.components)
        end
        if data.props then
            client.setPedProps(cache.ped, data.props)
        end
    end
end)

RegisterNUICallback("appearance_delete_outfit", function(id, cb)
    TriggerServerEvent("illenium-appearance:server:deleteOutfit", id)
    Wait(300)
    lib.callback("illenium-appearance:server:getOutfits", false, function(outfits)
        cb(outfits or {})
    end)
end)

RegisterNUICallback("appearance_generate_outfit_code", function(id, cb)
    lib.callback("illenium-appearance:server:generateOutfitCode", false, function(code)
        cb(code or "")
    end, id)
end)

RegisterNUICallback("appearance_import_outfit_code", function(data, cb)
    if not data or not data.name or not data.code then
        cb({ success = false, message = "Missing fields" })
        return
    end
    lib.callback("illenium-appearance:server:importOutfitCode", false, function(success)
        if success then
            Wait(300)
            lib.callback("illenium-appearance:server:getOutfits", false, function(outfits)
                cb({ success = true, outfits = outfits or {} })
            end)
        else
            cb({ success = false, message = "Invalid code or duplicate" })
        end
    end, data.name, data.code)
end)
