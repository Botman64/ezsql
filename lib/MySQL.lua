local function validateQuery(query)
    local blacklist = {
        "DROP DATABASE",
        "DELETE FROM.*WHERE.*=.*1.*=.*1",
        "INSERT INTO users.*VALUES.*admin",
        "EXEC ",
        "EXECUTE ",
        "xp_",
        "sp_",
        "UNION SELECT",
        "INFORMATION_SCHEMA",
        "BENCHMARK",
        "SLEEP",
        "WAITFOR DELAY"
    }

    local normalizedQuery = query:lower():gsub("%s+", " ")

    for _, pattern in ipairs(blacklist) do
        if normalizedQuery:match(pattern:lower()) then
            TriggerEvent('ezsql:securityAlert', {
                query = query,
                pattern = pattern,
                source = GetInvokingResource() or "unknown"
            })
        end
    end

    return query
end

local function createFunction(handler)
    local fn = function(query, params, cb)

        if type(params) == 'function' then
            cb = params
            params = {}
        end
        params = params or {}

        query = validateQuery(query)

        if cb then
            CreateThread(function()
                local result
                local success, err = pcall(function()
                    result = exports.ezsql:Query(query, params)
                end)

                if success then
                    cb(handler(result))
                else
                    print("^1SQL Error: " .. (err or "Unknown error") .. "^7")
                    cb(nil)
                end
            end)
            return
        end

        local result
        local success, err = pcall(function()
            result = exports.ezsql:Query(query, params)
        end)

        if not success then
            print("^1SQL Error: " .. (err or "Unknown error") .. "^7")
            return nil
        end

        return handler(result)
    end

    local awaitFn = function(query, params)
        if not params then params = {} end

        query = validateQuery(query)

        local p = promise.new()
        local success, result = pcall(function()
            return handler(exports.ezsql:Query(query, params))
        end)

        if success then
            p:resolve(result)
        else
            print("^1SQL Error in await: " .. (result or "Unknown error") .. "^7")
            p:reject(result)
        end

        return Citizen.Await(p)
    end

    local tbl = setmetatable({
        await = awaitFn
    }, {
        __call = function(t, ...)
            return fn(...)
        end
    })

    return tbl
end

MySQL = {
    Sync = {},
    Async = {}
}

local function queryHandler(result)
    return result or {}
end

local function insertHandler(result)
    return result and result.insertId or 0
end

local function updateHandler(result)
    return result and result.affectedRows or 0
end

local function scalarHandler(result)
    if result and #result > 0 then
        for k, v in pairs(result[1]) do
            return v
        end
    end
    return nil
end

local function singleHandler(result)
    return result and result[1] or nil
end

local function executeHandler(result)
    return result and result.affectedRows or 0
end

-- Define all MySQL functions with the handlers
MySQL.insert = createFunction(insertHandler)
MySQL.update = createFunction(updateHandler)
MySQL.query = createFunction(queryHandler)
MySQL.scalar = createFunction(scalarHandler)
MySQL.single = createFunction(singleHandler)
MySQL.execute = createFunction(executeHandler)
MySQL.rawExecute = createFunction(executeHandler)

MySQL.transaction = setmetatable({
    await = function(queries, params)
        if not params then params = {} end
        local p = promise.new()

        -- Validate that queries is an array
        print(queries)
        if type(queries) ~= 'table' or #queries == 0 then
            print("^1SQL Transaction Error: Queries parameter must be a non-empty array.^7")
            p:reject("Queries parameter must be a non-empty array.")
            return Citizen.Await(p)
        end

        for i, query in ipairs(queries) do
            queries[i] = validateQuery(query)
        end

        local success, result = pcall(function()
            -- Call Transaction directly as a method with "." instead of ":"
            return exports.ezsql.Transaction(queries, params)
        end)

        if success then
            p:resolve(result)
        else
            print("^1SQL Transaction Error: " .. (result or "Unknown error") .. "^7")
            p:reject(result)
        end

        return Citizen.Await(p)
    end
}, {
    __call = function(t, queries, params, cb)
        if type(params) == 'function' then
            cb = params
            params = {}
        end
        params = params or {}

        if type(queries) ~= 'table' or #queries == 0 then
            print("^1SQL Transaction Error: Queries parameter must be a non-empty array.^7")
            if cb then cb(false) end
            return false
        end

        for i, query in ipairs(queries) do
            queries[i] = validateQuery(query)
        end

        local result
        local success, err = pcall(function()
            result = exports.ezsql.Transaction(queries, params)
        end)

        if not success then
            print("^1SQL Transaction Error: " .. (err or "Unknown error") .. "^7")
            if cb then cb(false) end
            return false
        end

        if cb then cb(result) end
        return result
    end
})

MySQL.prepare = setmetatable({
    await = function(query, params)
        if not params then params = {} end
        local p = promise.new()

        query = validateQuery(query)

        local success, result = pcall(function()
            return exports.ezsql.PreparedStatement(query, params)
        end)

        if success then
            p:resolve(result)
        else
            print("^1SQL Prepare Error: " .. (result or "Unknown error") .. "^7")
            p:reject(result)
        end

        return Citizen.Await(p)
    end
}, {
    __call = function(t, query, params, cb)
        if type(params) == 'function' then
            cb = params
            params = {}
        end
        params = params or {}

        query = validateQuery(query)

        local result
        local success, err = pcall(function()
            result = exports.ezsql.PreparedStatement(query, params)
        end)

        if not success then
            print("^1SQL Prepare Error: " .. (err or "Unknown error") .. "^7")
            if cb then cb(nil) end
            return nil
        end

        if cb then cb(result) end
        return result
    end
})

-- Legacy Async functions
MySQL.Async.execute = MySQL.execute
MySQL.Async.fetchAll = MySQL.query
MySQL.Async.fetchScalar = MySQL.scalar
MySQL.Async.fetchSingle = MySQL.single
MySQL.Async.insert = MySQL.insert
MySQL.Async.transaction = MySQL.transaction
MySQL.Async.prepare = MySQL.prepare

-- Legacy Sync functions
MySQL.Sync.execute = MySQL.execute
MySQL.Sync.fetchAll = MySQL.query
MySQL.Sync.fetchScalar = MySQL.scalar
MySQL.Sync.fetchSingle = MySQL.single
MySQL.Sync.insert = MySQL.insert

local exportNames = {'query', 'insert', 'update', 'scalar', 'single', 'execute', 'transaction', 'prepare'}
local resourceNames = {'oxmysql', 'mysql-async', 'ghmattimysql'}
for _, exportName in ipairs(exportNames) do
    for _, resourceName in ipairs(resourceNames) do
        AddEventHandler('__cfx_export_'.. resourceName ..'_'.. exportName, function(cb)
            if exportName == 'transaction' and resourceName == ' ghmattimysql' then return end
            cb(function(query, params, callback)
                return MySQL[exportName](query, params, callback)
            end)
        end)
    end
end

local ghmattiNames = {
    ['executeSync'] = 'query',
    ['sync'] = 'query',
    ['transaction'] = 'transaction'
}

for exportName, mappedFunction in pairs(ghmattiNames) do
    AddEventHandler('__cfx_export_ghmattimysql_'.. exportName, function(cb)
        cb(function(query, params, callback)
            return MySQL[mappedFunction](query, params, callback)
        end)
    end)
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    print("^2SQL compatibility bridge^7: MySQL library loaded with oxmysql, mysql-async and ghmattimysql compatibility")
end)

AddEventHandler('ezsql:securityAlert', function(data)
    local message = ("Security Alert: Suspicious query from %s - Pattern: %s"):format(
        data.source or "unknown",
        data.pattern or "unknown"
    )
    print("^1" .. message .. "^7")
end)

return MySQL
