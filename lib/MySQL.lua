local ezsql = exports.ezsql

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
            print("^1Security Warning: Potentially dangerous query detected: " .. query .. "^7")
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

        local result
        local success, err = pcall(function()
            result = ezsql:Query(query, params)
        end)

        if not success then
            print("^1SQL Error: " .. (err or "Unknown error") .. "^7")
            if cb then cb(nil) end
            return nil
        end

        local processedResult = handler(result)

        if cb then cb(processedResult) end
        return processedResult
    end

    local awaitFn = function(query, params)
        if not params then params = {} end

        query = validateQuery(query)

        local p = promise.new()
        local success, result = pcall(function()
            return handler(ezsql:Query(query, params))
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

MySQL.insert = createFunction(function(result)
    return result and result.insertId or 0
end)

MySQL.update = createFunction(function(result)
    return result and result.affectedRows or 0
end)

MySQL.query = createFunction(function(result)
    return result or {}
end)

MySQL.scalar = createFunction(function(result)
    if result and #result > 0 then
        for k, v in pairs(result[1]) do
            return v
        end
    end
    return nil
end)

MySQL.single = createFunction(function(result)
    return result and result[1] or nil
end)

MySQL.execute = createFunction(function(result)
    return result and result.affectedRows or 0
end)

MySQL.transaction = setmetatable({
    await = function(queries, params)
        if not params then params = {} end
        local p = promise.new()

        if type(queries) == 'table' then
            for i, query in ipairs(queries) do
                queries[i] = validateQuery(query)
            end
        end

        local success, result = pcall(function()
            return ezsql:Transaction(queries, params)
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

        if type(queries) == 'table' then
            for i, query in ipairs(queries) do
                queries[i] = validateQuery(query)
            end
        end

        local result
        local success, err = pcall(function()
            result = ezsql:Transaction(queries, params)
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
            return ezsql:PreparedStatement(query, params)
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
            result = ezsql:PreparedStatement(query, params)
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

MySQL.rawExecute = MySQL.execute

MySQL.Async.execute = MySQL.execute
MySQL.Async.fetchAll = MySQL.query
MySQL.Async.fetchScalar = MySQL.scalar
MySQL.Async.fetchSingle = MySQL.single
MySQL.Async.insert = MySQL.insert
MySQL.Async.transaction = MySQL.transaction
MySQL.Async.prepare = MySQL.prepare

MySQL.Sync.execute = function(query, params)
    return MySQL.execute(query, params)
end

MySQL.Sync.fetchAll = function(query, params)
    return MySQL.query(query, params)
end

MySQL.Sync.fetchScalar = function(query, params)
    return MySQL.scalar(query, params)
end

MySQL.Sync.fetchSingle = function(query, params)
    return MySQL.single(query, params)
end

MySQL.Sync.insert = function(query, params)
    return MySQL.insert(query, params)
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        TriggerEvent('oxmysql:available')
        print("^2oxmysql bridge^7: MySQL library loaded through ezsql")
    end
end)

AddEventHandler('ezsql:securityAlert', function(data)
    local message = ("Security Alert: Suspicious query from %s - Pattern: %s"):format(
        data.source or "unknown",
        data.pattern or "unknown"
    )
    print("^1" .. message .. "^7")
end)

return MySQL
