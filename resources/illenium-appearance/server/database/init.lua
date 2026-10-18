-- Automatic Database Initializer & Schema Verifier for illenium-appearance

local function initializeDatabase()
    local tables = {
        playerskins = [[
            CREATE TABLE IF NOT EXISTS `playerskins` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `citizenid` varchar(255) NOT NULL,
              `model` varchar(255) NOT NULL,
              `skin` text NOT NULL,
              `active` tinyint(4) NOT NULL DEFAULT 1,
              PRIMARY KEY (`id`),
              KEY `citizenid` (`citizenid`),
              KEY `active` (`active`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        player_outfits = [[
            CREATE TABLE IF NOT EXISTS `player_outfits` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `citizenid` varchar(50) DEFAULT NULL,
              `outfitname` varchar(50) NOT NULL DEFAULT '0',
              `model` varchar(50) DEFAULT NULL,
              `props` varchar(1000) DEFAULT NULL,
              `components` varchar(1500) DEFAULT NULL,
              PRIMARY KEY (`id`),
              UNIQUE KEY `citizenid_outfitname_model` (`citizenid`,`outfitname`,`model`),
              KEY `citizenid` (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        player_outfit_codes = [[
            CREATE TABLE IF NOT EXISTS `player_outfit_codes` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `outfitid` int(11) NOT NULL,
              `code` varchar(50) NOT NULL DEFAULT '',
              PRIMARY KEY (`id`),
              KEY `FK_player_outfit_codes_player_outfits` (`outfitid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        management_outfits = [[
            CREATE TABLE IF NOT EXISTS `management_outfits` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `job_name` varchar(50) NOT NULL,
              `type` varchar(50) NOT NULL,
              `minrank` int(11) NOT NULL DEFAULT 0,
              `name` varchar(50) NOT NULL DEFAULT 'Cool Outfit',
              `gender` varchar(50) NOT NULL DEFAULT 'male',
              `model` varchar(50) DEFAULT NULL,
              `props` varchar(1000) DEFAULT NULL,
              `components` varchar(1500) DEFAULT NULL,
              PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]]
    }

    for tableName, query in pairs(tables) do
        MySQL.query(query, {}, function(result)
            if result then
                print(("^2[illenium-appearance]^7 Database table '^5%s^7' verified successfully."):format(tableName))
            end
        end)
    end
end

MySQL.ready(function()
    initializeDatabase()
end)
