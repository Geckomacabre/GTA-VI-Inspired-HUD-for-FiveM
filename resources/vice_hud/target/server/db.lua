DB = {}

local HISTORY_LIMIT = 20

local SCHEMA = {
  [[CREATE TABLE IF NOT EXISTS `osm_target_config` (
      `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `revision` INT UNSIGNED NOT NULL DEFAULT 1,
      `payload` LONGTEXT NOT NULL,
      `author` VARCHAR(64) NULL,
      `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`),
      KEY `idx_revision` (`revision`)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],
}

---Initialize database schema: create config table if not exists.
function DB.Init()
  for i = 1, #SCHEMA do
    MySQL.query.await(SCHEMA[i], {})
  end
  print('^2[osm-target] Database schema ready.^7')
end

---Load latest revision: fetch most recent configuration payload.
---@return table? payload, number revision
function DB.LoadLatest()
  local row = MySQL.single.await(
    'SELECT `revision`, `payload` FROM `osm_target_config` ORDER BY `id` DESC LIMIT 1', {})

  if not row then return nil, 0 end

  local ok, decoded = pcall(json.decode, row.payload)
  if not ok or type(decoded) ~= 'table' then return nil, row.revision or 0 end

  return decoded, row.revision or 0
end

---Save configuration revision: insert new configuration row and trim history.
---@param payload table
---@param author string?
---@return number revision
function DB.Save(payload, author)
  MySQL.query.await(
    'INSERT INTO `osm_target_config` (`revision`, `payload`, `author`) SELECT COALESCE(MAX(`revision`), 0) + 1, ?, ? FROM `osm_target_config`',
    { json.encode(payload), author })

  local row = MySQL.single.await(
    'SELECT `revision` FROM `osm_target_config` ORDER BY `id` DESC LIMIT 1', {})
  local revision = row and row.revision or 1

  MySQL.query('DELETE FROM `osm_target_config` WHERE `id` NOT IN (SELECT `id` FROM (SELECT `id` FROM `osm_target_config` ORDER BY `id` DESC LIMIT ?) AS keep)',
    { HISTORY_LIMIT })

  return revision
end

---Get revision history: fetch list of past revisions.
---@return { revision: number, author: string?, created_at: string }[]
function DB.History()
  return MySQL.query.await(
    'SELECT `revision`, `author`, `created_at` FROM `osm_target_config` ORDER BY `id` DESC LIMIT ?',
    { HISTORY_LIMIT }) or {}
end
