fx_version 'cerulean'
game 'gta5'

author 'Botman64'
description 'Easy SQL Database Integration for FiveM'
version '1.0.0'

provide 'oxmysql'
provide 'mysql-async'
provide 'ghmattimysql'

lua54 'yes'
use_fxv2_oal 'yes'
server_script 'server.js'

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
