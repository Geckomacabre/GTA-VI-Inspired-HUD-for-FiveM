-- QBCore (qb-core) server framework adapter
if Bridge.Framework ~= 'qbcore' then return end

local QBCore = exports['qb-core']:GetCoreObject()

function Adapter.Notify(source, message, kind)
  QBCore.Functions.Notify(source, message, kind == 'inform' and 'primary' or kind)
end

Bridge.Ready = true
