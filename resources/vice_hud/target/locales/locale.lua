Locales = Locales or {}

local function activeLang()
  return (Config and Config.Locale) or 'en'
end

function Locale(key, ...)
  local lang = activeLang()
  local tbl = Locales[lang] or Locales['en'] or {}
  local str = tbl[key] or (Locales['en'] and Locales['en'][key]) or key
  if select('#', ...) > 0 then
    local ok, res = pcall(string.format, str, ...)
    if ok then return res end
  end
  return str
end

L = Locale
