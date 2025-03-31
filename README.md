# EZSQL Documentation

This document explains how to connect to and use the `ezsql` exports from another FiveM script.

---

## Prerequisites

1. Ensure the `ezsql` resource is running on your server.
2. Add the following to your `server.cfg`:
   ```
   set mysql_connection_string "mysql://user:password@host/database_name?charset=charset"
   ensure ezsql
   ```

---

## Usage in Lua

You can use the `exports` object to call the `ezsql` functions.

### Example: Initialize Tables
```lua
local success = exports.ezsql:Initialize({
    users = {
        { column_name = "id", data_type = "INT", is_primary_key = true, auto_increment = true },
        { column_name = "username", data_type = "VARCHAR(255)", unique = true },
        { column_name = "age", data_type = "INT" }
    }
})
if success then
    print("Tables initialized successfully!")
else
    print("Failed to initialize tables.")
end
```

### Example: Initialize Tables with Foreign Keys
```lua
local success = exports.ezsql:Initialize({
    users = {
        { column_name = "id", data_type = "INT", is_primary_key = true, auto_increment = true },
        { column_name = "username", data_type = "VARCHAR(255)", unique = true },
        { column_name = "age", data_type = "INT" }
    },
    orders = {
        { column_name = "order_id", data_type = "INT", is_primary_key = true, auto_increment = true },
        { column_name = "user_id", data_type = "INT", foreign_key = {
            table = "users",
            column = "id",
            on_delete = "CASCADE",
            on_update = "CASCADE"
        }},
        { column_name = "order_date", data_type = "DATETIME" }
    }
})
if success then
    print("Tables initialized successfully!")
else
    print("Failed to initialize tables.")
end
```

### Example: Add an Entry
```lua
local success = exports.ezsql:AddEntry("users", {
    username = "testuser",
    age = 25
})
if success then
    print("Entry added successfully!")
else
    print("Failed to add entry.")
end
```

### Example: Get All Entries
```lua
local users = exports.ezsql:GetAllEntries("users")
for _, user in ipairs(users) do
    print(("User: %s, Age: %d"):format(user.username, user.age))
end
```

### Example: Get Entries by Data with Specific Columns
```lua
local users = exports.ezsql:GetAllEntriesByData("users", { age = 25 }, { "username" })
for _, user in ipairs(users) do
    print(("Username: %s"):format(user.username))
end
```

### Example: Get First Entry by Data with Specific Columns
```lua
local user = exports.ezsql:GetFirstEntryByData("users", { age = 25 }, { "username" })
if user then
    print(("First User: %s"):format(user.username))
else
    print("No user found.")
end
```

### Example: Get All Entries (All Columns)
```lua
local users = exports.ezsql:GetAllEntries("users")
for _, user in ipairs(users) do
    print(("User: %s, Age: %d"):format(user.username, user.age))
end
```

### Example: Get Entries by Data (All Columns)
```lua
local users = exports.ezsql:GetAllEntriesByData("users", { age = 25 })
for _, user in ipairs(users) do
    print(("User: %s, Age: %d"):format(user.username, user.age))
end
```

---

## Security Features

EZSQL provides several security features:

1. **Prepared Statements**: All database operations use prepared statements to prevent SQL injection attacks.

2. **Query Validation**: When using the oxmysql bridge, all query strings are validated against common SQL injection patterns.

3. **Security Alerts**: Suspicious queries are logged and an event `ezsql:securityAlert` is triggered with details.

4. **Error Handling**: SQL errors are properly caught and logged to prevent exposing sensitive information.

## OxMySQL Bridge

EZSQL provides full compatibility with oxmysql through its bridge. This allows resources that depend on oxmysql to work without any modifications.

The bridge includes security measures to protect against SQL injection while maintaining full compatibility with the oxmysql API.

---

## Notes

- Replace `"users"` with your table name.
- Replace the data fields (`username`, `age`, etc.) with the actual columns in your database schema.
- Ensure proper error handling in your scripts.
- All queries use prepared statements for improved security.
