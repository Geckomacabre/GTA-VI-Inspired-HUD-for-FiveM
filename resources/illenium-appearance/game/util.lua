local hashesComputed = false
local PED_TATTOOS = {}
local pedModelsByHash = {}

local function tofloat(num)
    if not num then return 0.0 end
    return (tonumber(num) or 0) + 0.0
end

local function isPedFreemodeModel(ped)
    local model = GetEntityModel(ped)
    return model == `mp_m_freemode_01` or model == `mp_f_freemode_01`
end

local function computePedModelsByHash()
    for i = 1, #Config.Peds.pedConfig do
        local peds = Config.Peds.pedConfig[i].peds
        for j = 1, #peds do
            pedModelsByHash[joaat(peds[j])] = peds[j]
        end
    end
end

---@param ped number entity id
---@return string
--- Get the model name from an entity's model hash
local function getPedModel(ped)
    if not hashesComputed then
        computePedModelsByHash()
        hashesComputed = true
    end
    return pedModelsByHash[GetEntityModel(ped)]
end

---@param ped number entity id
---@return table<number, table<string, number>>
local function getPedComponents(ped)
    local size = #constants.PED_COMPONENTS_IDS
    local components = table.create(size, 0)

    for i = 1, size do
        local componentId = constants.PED_COMPONENTS_IDS[i]
        components[i] = {
            component_id = componentId,
            drawable = GetPedDrawableVariation(ped, componentId),
            texture = GetPedTextureVariation(ped, componentId),
        }
    end

    return components
end

---@param ped number entity id
---@return table<number, table<string, number>>
local function getPedProps(ped)
    local size = #constants.PED_PROPS_IDS
    local props = table.create(size, 0)

    for i = 1, size do
        local propId = constants.PED_PROPS_IDS[i]
        props[i] = {
            prop_id = propId,
            drawable = GetPedPropIndex(ped, propId),
            texture = GetPedPropTextureIndex(ped, propId),
        }
    end
    return props
end

local function round(number, decimalPlaces)
    return tonumber(string.format("%." .. (decimalPlaces or 0) .. "f", number))
end

---@param ped number entity id
---@return table <number, number>
---```
---{ shapeFirst, shapeSecond, shapeThird, skinFirst, skinSecond, skinThird, shapeMix, skinMix, thirdMix }
---```
local function getPedHeadBlend(ped)
    -- GET_PED_HEAD_BLEND_DATA
    local shapeFirst, shapeSecond, shapeThird, skinFirst, skinSecond, skinThird, shapeMix, skinMix, thirdMix = Citizen.InvokeNative(0x2746BD9D88C5C5D0, ped, Citizen.PointerValueIntInitialized(0), Citizen.PointerValueIntInitialized(0), Citizen.PointerValueIntInitialized(0), Citizen.PointerValueIntInitialized(0), Citizen.PointerValueIntInitialized(0), Citizen.PointerValueIntInitialized(0), Citizen.PointerValueFloatInitialized(0), Citizen.PointerValueFloatInitialized(0), Citizen.PointerValueFloatInitialized(0))

    shapeMix = round(shapeMix or 0, 2)
    if shapeMix > 1 then shapeMix = 1 end

    skinMix = round(skinMix or 0, 2)
    if skinMix > 1 then skinMix = 1 end

    thirdMix = round(thirdMix or 0, 2)
    if thirdMix > 1 then thirdMix = 1 end


    if isPedFreemodeModel(ped) and (shapeFirst == 0 and shapeSecond == 0) then
        shapeFirst = 21
        shapeSecond = 0
        skinFirst = 21
        skinSecond = 0
    end

    return {
        shapeFirst = shapeFirst,
        shapeSecond = shapeSecond,
        shapeThird = shapeThird,
        skinFirst = skinFirst,
        skinSecond = skinSecond,
        skinThird = skinThird,
        shapeMix = shapeMix,
        skinMix = skinMix,
        thirdMix = thirdMix
    }
end

---@param ped number entity id
---@return table<number, table<string, number>>
local function getPedFaceFeatures(ped)
    local size = #constants.FACE_FEATURES
    local faceFeatures = table.create(0, size)

    for i = 1, size do
        local feature = constants.FACE_FEATURES[i]
        faceFeatures[feature] = round(GetPedFaceFeature(ped, i-1), 1)
    end

    return faceFeatures
end

---@param ped number entity id
---@return table<number, table<string, number>>
local function getPedHeadOverlays(ped)
    local size = #constants.HEAD_OVERLAYS
    local headOverlays = table.create(0, size)

    for i = 1, size do
        local overlay = constants.HEAD_OVERLAYS[i]
        local _, value, _, firstColor, secondColor, opacity = GetPedHeadOverlayData(ped, i-1)

        if value ~= 255 then
            opacity = round(opacity, 1)
        else
            value = 0
            opacity = 0
        end

        headOverlays[overlay] = {style = value, opacity = opacity, color = firstColor, secondColor = secondColor}
    end

    return headOverlays
end

---@param ped number entity id
---@return table<string, number>
local function getPedHair(ped)
    return {
        style = GetPedDrawableVariation(ped, 2),
        color = GetPedHairColor(ped),
        highlight = GetPedHairHighlightColor(ped),
        texture = GetPedTextureVariation(ped, 2)
    }
end

local function getPedDecorationType()
    local pedModel = GetEntityModel(cache.ped)
    local decorationType

    if pedModel == `mp_m_freemode_01` then
        decorationType = "male"
    elseif pedModel == `mp_f_freemode_01` then
        decorationType = "female"
    else
        decorationType = IsPedMale(cache.ped) and "male" or "female"
    end

    return decorationType
end

local function getPedAppearance(ped)
    local eyeColor = GetPedEyeColor(ped)

    return {
        model = getPedModel(ped) or "mp_m_freemode_01",
        headBlend = getPedHeadBlend(ped),
        faceFeatures = getPedFaceFeatures(ped),
        headOverlays = getPedHeadOverlays(ped),
        components = getPedComponents(ped),
        props = getPedProps(ped),
        hair = getPedHair(ped),
        tattoos = client.getPedTattoos(),
        eyeColor = eyeColor < #constants.EYE_COLORS and eyeColor or 0
    }
end

local function setPlayerModel(model)
    if type(model) == "string" then model = joaat(model) end

    if IsModelInCdimage(model) then
        RequestModel(model)
        while not HasModelLoaded(model) do Wait(0) end

        SetPlayerModel(PlayerId(), model)
        local ped = PlayerPedId()

        if isPedFreemodeModel(ped) then
            SetPedDefaultComponentVariation(ped)
            SetPedHeadBlendData(ped, 21, 0, 0, 21, 0, 0, 0.5, 0.5, 0, false)
        end

        SetModelAsNoLongerNeeded(model)

        PED_TATTOOS = {}
        return ped
    end

    return PlayerPedId()
end

local function setPedHeadBlend(ped, headBlend)
    if headBlend and isPedFreemodeModel(ped) then
        local shapeFirst = headBlend.shapeFirst or 21
        local shapeSecond = headBlend.shapeSecond or 0
        local shapeThird = headBlend.shapeThird or 0
        local skinFirst = headBlend.skinFirst or 21
        local skinSecond = headBlend.skinSecond or 0
        local skinThird = headBlend.skinThird or 0
        local shapeMix = tofloat(headBlend.shapeMix or 0.5)
        local skinMix = tofloat(headBlend.skinMix or 0.5)
        local thirdMix = tofloat(headBlend.thirdMix or 0)
        SetPedHeadBlendData(ped, shapeFirst, shapeSecond, shapeThird, skinFirst, skinSecond, skinThird, shapeMix, skinMix, thirdMix, false)
    end
end

local function setPedFaceFeatures(ped, faceFeatures)
    if faceFeatures then
        if type(faceFeatures) == "table" and faceFeatures.key and faceFeatures.value ~= nil then
            for k, v in ipairs(constants.FACE_FEATURES) do
                if v == faceFeatures.key then
                    SetPedFaceFeature(ped, k - 1, tofloat(faceFeatures.value))
                    break
                end
            end
        elseif type(faceFeatures) == "table" then
            for k, v in ipairs(constants.FACE_FEATURES) do
                if faceFeatures[v] ~= nil then
                    SetPedFaceFeature(ped, k - 1, tofloat(faceFeatures[v]))
                end
            end
        end
    end
end

local function setPedHeadOverlays(ped, headOverlays)
    if headOverlays then
        if type(headOverlays) == "table" and headOverlays.key then
            local kKey = headOverlays.key
            for k, v in ipairs(constants.HEAD_OVERLAYS) do
                if v == kKey then
                    SetPedHeadOverlay(ped, k-1, headOverlays.style or 0, tofloat(headOverlays.opacity or 1.0))
                    if headOverlays.color ~= nil then
                        local colorType = 1
                        if kKey == "blush" or kKey == "lipstick" or kKey == "makeUp" then
                            colorType = 2
                        end
                        SetPedHeadOverlayColor(ped, k-1, colorType, headOverlays.color or 0, headOverlays.secondColor or 0)
                    end
                    break
                end
            end
            return
        end

        for k, v in ipairs(constants.HEAD_OVERLAYS) do
            local headOverlay = headOverlays[v]
            if headOverlay and type(headOverlay) == "table" then
                SetPedHeadOverlay(ped, k-1, headOverlay.style or 0, tofloat(headOverlay.opacity or 1.0))

                if headOverlay.color then
                    local colorType = 1
                    if v == "blush" or v == "lipstick" or v == "makeUp" then
                        colorType = 2
                    end

                    SetPedHeadOverlayColor(ped, k-1, colorType, headOverlay.color or 0, headOverlay.secondColor or 0)
                end
            end
        end
    end
end

local function applyAutomaticFade(ped, style)
    local gender = getPedDecorationType()
    local hairDecoration = constants.HAIR_DECORATIONS[gender][style]

    if(hairDecoration) then
        AddPedDecorationFromHashes(ped, hairDecoration[1], hairDecoration[2])
    end
end

local function setTattoos(ped, tattoos, style)
    local isMale = client.getPedDecorationType() == "male"
    ClearPedDecorations(ped)
    if Config.AutomaticFade then
        tattoos["ZONE_HAIR"] = {}
        PED_TATTOOS["ZONE_HAIR"] = {}
        applyAutomaticFade(ped, style or GetPedDrawableVariation(ped, 2))
    end
    for k in pairs(tattoos) do
        for i = 1, #tattoos[k] do
            local tattoo = tattoos[k][i]
            local tattooGender = isMale and tattoo.hashMale or tattoo.hashFemale
            for _ = 1, (tattoo.opacity or 0.1) * 10 do
                AddPedDecorationFromHashes(ped, joaat(tattoo.collection), joaat(tattooGender))
            end
        end
    end
    if Config.RCoreTattoosCompatibility then
        TriggerEvent("rcore_tattoos:applyOwnedTattoos")
    end
end

local function setPedHair(ped, hair, tattoos)
    if hair then
        SetPedComponentVariation(ped, 2, hair.style, hair.texture, 0)
        SetPedHairColor(ped, hair.color, hair.highlight)
        if isPedFreemodeModel(ped) then
            setTattoos(ped, tattoos or PED_TATTOOS, hair.style)
        end
    end
end

local function setPedEyeColor(ped, eyeColor)
    if eyeColor then
        SetPedEyeColor(ped, eyeColor)
    end
end

local function setPedComponent(ped, component)
    if component then
        if isPedFreemodeModel(ped) and (component.component_id == 0 or component.component_id == 2) then
            return
        end

        SetPedComponentVariation(ped, component.component_id, component.drawable, component.texture, 0)
    end
end

local function setPedComponents(ped, components)
    if components then
        for _, v in pairs(components) do
            setPedComponent(ped, v)
        end
    end
end

local function setPedProp(ped, prop)
    if prop then
        if prop.drawable == -1 then
            ClearPedProp(ped, prop.prop_id)
        else
            SetPedPropIndex(ped, prop.prop_id, prop.drawable, prop.texture, false)
        end
    end
end

local function setPedProps(ped, props)
    if props then
        for _, v in pairs(props) do
            setPedProp(ped, v)
        end
    end
end

local function setPedTattoos(ped, tattoos)
    PED_TATTOOS = tattoos
    setTattoos(ped, tattoos)
end

local function getPedTattoos()
    return PED_TATTOOS
end

local function addPedTattoo(ped, tattoos)
    setTattoos(ped, tattoos)
end

local function removePedTattoo(ped, tattoos)
    setTattoos(ped, tattoos)
end

local function setPreviewTattoo(ped, tattoos, tattoo)
    local isMale = client.getPedDecorationType() == "male"
    local tattooGender = isMale and tattoo.hashMale or tattoo.hashFemale

    ClearPedDecorations(ped)
    for _ = 1, (tattoo.opacity or 0.1) * 10 do
        AddPedDecorationFromHashes(ped, joaat(tattoo.collection), tattooGender)
    end
    for k in pairs(tattoos) do
        for i = 1, #tattoos[k] do
            local aTattoo = tattoos[k][i]
            if aTattoo.name ~= tattoo.name then
                local aTattooGender = isMale and aTattoo.hashMale or aTattoo.hashFemale
                for _ = 1, (aTattoo.opacity or 0.1) * 10 do
                    AddPedDecorationFromHashes(ped, joaat(aTattoo.collection), joaat(aTattooGender))
                end
            end
        end
    end
    if Config.AutomaticFade then
        applyAutomaticFade(ped, GetPedDrawableVariation(ped, 2))
    end
end

local function setPedAppearance(ped, appearance)
    if appearance then
        local targetPed = (ped and DoesEntityExist(ped)) and ped or PlayerPedId()

        if isPedFreemodeModel(targetPed) then
            SetPedDefaultComponentVariation(targetPed)
        end

        if appearance.headBlend and isPedFreemodeModel(targetPed) then
            setPedHeadBlend(targetPed, appearance.headBlend)
        elseif isPedFreemodeModel(targetPed) then
            SetPedHeadBlendData(targetPed, 21, 0, 0, 21, 0, 0, 0.5, 0.5, 0, false)
        end

        if appearance.faceFeatures then setPedFaceFeatures(targetPed, appearance.faceFeatures) end
        if appearance.headOverlays then setPedHeadOverlays(targetPed, appearance.headOverlays) end
        if appearance.components then setPedComponents(targetPed, appearance.components) end
        if appearance.props then setPedProps(targetPed, appearance.props) end
        if appearance.hair then setPedHair(targetPed, appearance.hair, appearance.tattoos) end
        if appearance.eyeColor then setPedEyeColor(targetPed, appearance.eyeColor) end
        if appearance.tattoos then setPedTattoos(targetPed, appearance.tattoos) end
    end
end

local function setPlayerAppearance(appearance)
    if appearance then
        setPlayerModel(appearance.model)
        local ped = PlayerPedId()
        setPedAppearance(ped, appearance)
    end
end

exports("getPedModel", getPedModel)
exports("getPedComponents", getPedComponents)
exports("getPedProps", getPedProps)
exports("getPedHeadBlend", getPedHeadBlend)
exports("getPedFaceFeatures", getPedFaceFeatures)
exports("getPedHeadOverlays", getPedHeadOverlays)
exports("getPedHair", getPedHair)
exports("getPedAppearance", getPedAppearance)

exports("setPlayerModel", setPlayerModel)
exports("setPedHeadBlend", setPedHeadBlend)
exports("setPedFaceFeatures", setPedFaceFeatures)
exports("setPedHeadOverlays", setPedHeadOverlays)
exports("setPedHair", setPedHair)
exports("setPedEyeColor", setPedEyeColor)
exports("setPedComponent", setPedComponent)
exports("setPedComponents", setPedComponents)
exports("setPedProp", setPedProp)
exports("setPedProps", setPedProps)
exports("setPlayerAppearance", setPlayerAppearance)
exports("setPedAppearance", setPedAppearance)
exports("setPedTattoos", setPedTattoos)

client = {
    getPedAppearance = getPedAppearance,
    setPlayerModel = setPlayerModel,
    setPedHeadBlend = setPedHeadBlend,
    setPedFaceFeatures = setPedFaceFeatures,
    setPedHair = setPedHair,
    setPedHeadOverlays = setPedHeadOverlays,
    setPedEyeColor = setPedEyeColor,
    setPedComponent = setPedComponent,
    setPedProp = setPedProp,
    setPlayerAppearance = setPlayerAppearance,
    setPedAppearance = setPedAppearance,
    getPedDecorationType = getPedDecorationType,
    isPedFreemodeModel = isPedFreemodeModel,
    setPreviewTattoo = setPreviewTattoo,
    setPedTattoos = setPedTattoos,
    getPedTattoos = getPedTattoos,
    addPedTattoo = addPedTattoo,
    removePedTattoo = removePedTattoo,
    getPedModel = getPedModel,
    setPedComponents = setPedComponents,
    setPedProps = setPedProps,
    getPedComponents = getPedComponents,
    getPedProps = getPedProps
}
