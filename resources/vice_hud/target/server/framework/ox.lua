-- ox_core server framework adapter
if Bridge.Framework ~= 'ox' then return end

function Adapter.Notify(source, message, kind)
  TriggerClientEvent('osm-target:cl:notify', source, message, kind)
end

Bridge.Ready = true
