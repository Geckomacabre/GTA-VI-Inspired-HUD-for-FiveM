-- ESX (es_extended) server framework adapter
if Bridge.Framework ~= 'esx' then return end

local ESX = exports.es_extended:getSharedObject()

function Adapter.Notify(source, message, kind)
  local player = ESX.GetPlayerFromId(source)
  if player and player.showNotification then
    player.showNotification(message, kind)
    return
  end
  TriggerClientEvent('osm-target:cl:notify', source, message, kind)
end

Bridge.Ready = true
