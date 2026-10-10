-- Standalone client framework adapter
if Bridge.Framework ~= 'standalone' then return end

function Adapter.GetGroups() return {} end
function Adapter.GetGangs() return {} end
function Adapter.GetCitizenId() return nil end
function Adapter.GetItemCount(_name) return nil end
function Adapter.GetGroupLabel(_name) return nil end
function Adapter.GetItemLabel(_name) return nil end

function Adapter.Notify(message, _kind)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(message)
  EndTextCommandThefeedPostTicker(false, true)
end

AddEventHandler('ox_inventory:itemCount', function() Bridge.InvalidatePlayerState() end)

Bridge.Ready = true
