fx_version 'cerulean'
game 'gta5'

name 'ezsql'
author 'Botman64'
description 'Easy SQL Database Integration for FiveM'
version '1.0.0'

-- Define that this resource provides oxmysql and other database bridges
provides {
    'oxmysql',
    'mysql-async',
    'ghmattimysql'
}

lua54 'yes'
use_fxv2_oal 'yes'

server_scripts {
    'server.js',
    'lib/MySQL.lua'
}

files {
    'lib/MySQL.lua'
}

server_exports {
    'Query',
    'Transaction',
    'PreparedStatement',
    'Initialize',
    'AddEntry',
    'UpdateEntry',
    'DeleteEntry',
    'GetAllEntries',
    'GetAllEntriesByData',
    'GetFirstEntryByData'
}
