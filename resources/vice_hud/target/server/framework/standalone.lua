-- Standalone server framework adapter: route notifications to client NUI stack
if Bridge.Framework ~= 'standalone' then return end

function Adapter.Notify(source, message, kind)
  TriggerClientEvent('osm-target:cl:notify', source, message, kind)
end

Bridge.Ready = true
