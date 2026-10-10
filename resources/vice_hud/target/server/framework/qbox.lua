-- Qbox (qbx_core) server framework adapter
if Bridge.Framework ~= 'qbox' then return end

function Adapter.Notify(source, message, kind)
  exports.qbx_core:Notify(source, message, kind or 'inform')
end

Bridge.Ready = true
