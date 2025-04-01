const mysql = require('mysql2/promise');
const schemaCache = {};

const connectionString = GetConvar('mysql_connection_string', 'string');
if (!connectionString) throw new Error('Connection string not provided. \n Please add the following to the top of the server.cfg file and restart ezsql: \n set mysql_connection_string "mysql://user:password@host/database_name"');

function parseConnectionString(connectionString) {
  const match = connectionString.match(/mysql:\/\/([^:]+)(?::([^@]+))?@([^/]+)\/([^?]*)(\?charset=(.+))?/);
  if (!match) throw new Error('Invalid connection string format.');

  const [, user, password = '', host, database, , charset = 'utf8mb4'] = match;

  return { user, password, host, database, charset };
}

const { user, password, host, database, charset } = parseConnectionString(connectionString);
if (!user || !host || !database)  throw new Error('Invalid connection string format. Please ensure it follows the pattern: mysql://user:password@host/database_name?charset=utf8mb4');

const pool = mysql.createPool({
  host,
  user,
  password,
  database,
  port: 3306,
  connectionLimit: 50,
  queueLimit: 0,
  waitForConnections: true,
  charset,
  connectTimeout: 10000,
  idleTimeout: 60000,
  enableKeepAlive: true,
  keepAliveInitialDelay: 10000
});

const connection = pool.query('SELECT 1');
if (!connection) throw new Error('Failed to establish a connection to the database. Please check your connection string and database server status.');

on("onResourceStop", (resourceName) => {
  if (resourceName === "ezsql") pool.end().then(() => console.log('MySQL connection pool closed.')).catch(err => console.error('Error closing MySQL connection pool:', err));
});

function validateDataTypes(tableName, entryData) {
  const tableSchema = schemaCache[tableName];
  if (!tableSchema) throw new Error(`Schema for table ${tableName} not found.`);

  for (const [column, value] of Object.entries(entryData)) {
    const columnSchema = tableSchema.find(col => col.column_name === column);
    if (!columnSchema) throw new Error(`Column ${column} does not exist in table ${tableName}.`);

    const expectedType = columnSchema.data_type.toLowerCase();
    const actualType = typeof value;

    if (
      (expectedType.includes('int') && actualType !== 'number') ||
      (expectedType.includes('varchar') && actualType !== 'string') ||
      (expectedType.includes('text') && actualType !== 'string') ||
      (expectedType.includes('float') && actualType !== 'number')
    ) {
      throw new Error(`Type mismatch for column ${column}: expected ${expectedType}, got ${actualType}.`);
    }
  }
}

global.exports('Initialize', async (schema) => {
  try {
    for (const [tableName, columns] of Object.entries(schema)) {
      schemaCache[tableName] = columns; // Cache schema
      const columnDefinitions = columns.map(col => {
        let def = `${col.column_name} ${col.data_type}`;
        if (col.is_primary_key) def += ' PRIMARY KEY';
        if (col.auto_increment) def += ' AUTO_INCREMENT';
        if (col.unique) def += ' UNIQUE';
        if (col.default) def += ` DEFAULT ${mysql.escape(col.default)}`;
        if (col.foreign_key) {
          def += `, FOREIGN KEY (${col.column_name}) REFERENCES ${col.foreign_key.table} (${col.foreign_key.column})`;
          if (col.foreign_key.on_delete) def += ` ON DELETE ${col.foreign_key.on_delete}`;
          if (col.foreign_key.on_update) def += ` ON UPDATE ${col.foreign_key.on_update}`;
        }
        return def;
      }).join(', ');
      const query = `CREATE TABLE IF NOT EXISTS ${tableName} (${columnDefinitions})`;
      await pool.query(query);
    }
    return true;
  } catch (err) {
    throw new Error(`Failed to Initialize Table: ${err}`);
  }
});

global.exports('AddEntry', async (tableName, entryData) => {
  try {
    validateDataTypes(tableName, entryData);
    const columnKeys = Object.keys(entryData);
    const columns = columnKeys.join(', ');
    const placeholders = columnKeys.map(() => '?').join(', ');
    const values = Object.values(entryData);

    const query = `INSERT INTO ${tableName} (${columns}) VALUES (${placeholders})`;
    const conn = await pool.getConnection();
    if (!conn) throw new Error('Failed to establish a connection to the database.');
    await conn.query(query, values);
    conn.release();

    return true;
  } catch (err) {
    throw new Error(`Failed to add entry: ${err}`);
  }
});

global.exports('UpdateEntry', async (tableName, entryData, id) => {
  try {
    validateDataTypes(tableName, entryData);
    const columnKeys = Object.keys(entryData);
    const updates = columnKeys.map(col => `${col} = ?`).join(', ');
    const values = [...Object.values(entryData), id];

    const query = `UPDATE ${tableName} SET ${updates} WHERE id = ?`;
    const conn = await pool.getConnection();
    if (!conn) throw new Error('Failed to establish a connection to the database.');
    const [result] = await conn.query(query, values);
    conn.release();

    if (result.affectedRows === 0) {
      throw new Error(`No entry found with id ${id} in table ${tableName}.`);
    }
    return true;
  } catch (err) {
    throw new Error(`Failed to update entry: ${err}`);
  }
});

global.exports('DeleteEntry', async (tableName, id) => {
  try {
    const query = `DELETE FROM ${tableName} WHERE id = ?`;
    const conn = await pool.getConnection();
    if (!conn) throw new Error('Failed to establish a connection to the database.');
    const [result] = await conn.query(query, [id]);
    conn.release();

    if (result.affectedRows === 0) throw new Error(`No entry found with id ${id} in table ${tableName}.`);

    return true;
  } catch (err) {
    throw new Error(`Failed to delete entry: ${err}`);
  }
});

global.exports('GetAllEntries', async (tableName, returnColumns = null, cb = null) => {
  try {
    const columns = returnColumns ? returnColumns.join(', ') : '*';

    const query = `SELECT ${columns} FROM ${tableName}`;
    const conn = await pool.getConnection();
    if (!conn) throw new Error('Failed to establish a connection to the database.');
    const [rows] = await conn.query(query);
    conn.release();

    if (cb) {
      cb(rows);
      return;
    }

    return rows;
  } catch (err) {
    throw new Error(`Failed to get all entries: ${err}`);
  }
});

global.exports('GetAllEntriesByData', async (tableName, entryData, returnColumns = null) => {
  try {
    validateDataTypes(tableName, entryData);
    const columns = returnColumns ? returnColumns.join(', ') : '*';
    const columnKeys = Object.keys(entryData);
    const conditions = columnKeys.map(col => `${col} = ?`).join(' AND ');
    const values = Object.values(entryData);

    const query = `SELECT ${columns} FROM ${tableName} WHERE ${conditions}`;
    const conn = await pool.getConnection();
    if (!conn) throw new Error('Failed to establish a connection to the database.');
    const [rows] = await conn.query(query, values);
    conn.release();

    return rows;
  } catch (err) {
    throw new Error(`Failed to get entries by data: ${err}`);
  }
});

global.exports('GetFirstEntryByData', async (tableName, entryData, returnColumns = null) => {
  let conn;
  try {
    if (entryData) validateDataTypes(tableName, entryData);

    const columns = returnColumns ? returnColumns.join(', ') : '*';
    const columnKeys = Object.keys(entryData || {});
    const conditions = columnKeys.length > 0
      ? columnKeys.map(col => `${col} = ?`).join(' AND ')
      : '1=1';
    const values = Object.values(entryData || {});

    const query = `SELECT ${columns} FROM ${tableName} WHERE ${conditions} LIMIT 1`;

    conn = await pool.getConnection();
    if (!conn) throw new Error('Failed to establish a connection to the database.');

    const [rows] = await conn.query(query, values);

    return rows.length > 0 ? rows[0] : null;
  } catch (err) {
    throw new Error(`Failed to get first entry by data: ${err}`);
  } finally {
    if (conn) conn.release();
  }
});

global.exports('Query', (query, parameters = [], cb) => {
  if (typeof parameters === 'function') {
    cb = parameters;
    parameters = [];
  }

  if (typeof cb === 'function') {
    let conn;
    pool.getConnection()
      .then(connection => {
        conn = connection;
        return conn.query(query, parameters);
      })
      .then(([rows]) => {
        let result;
        if (rows && !Array.isArray(rows)) {
          result = {
            ...rows,
            insertId: rows.insertId || 0,
            affectedRows: rows.affectedRows || 0
          };
        } else if (Array.isArray(rows)) {
          result = rows;
        } else {
          result = { insertId: 0, affectedRows: 0 };
        }

        if (conn) conn.release();
        cb(result);
      })
      .catch(err => {
        throw new Error(`Failed to execute query: ${err}`);
        if (conn) conn.release();
        cb(null);
      });

    return;
  }

  return (async () => {
    let conn;
    try {
      conn = await pool.getConnection();
      const [rows, fields] = await conn.query(query, parameters);

      if (rows && !Array.isArray(rows)) {
        return {
          ...rows,
          insertId: rows.insertId || 0,
          affectedRows: rows.affectedRows || 0
        };
      } else if (Array.isArray(rows)) {
        return rows;
      } else {
        return { insertId: 0, affectedRows: 0 };
      }
    } catch (err) {
      throw new Error(`Failed to execute query: ${err}`);
    } finally {
      if (conn) conn.release();
    }
  })();
});

global.exports('Transaction', async (queries, parameters = []) => {
  let conn;
  try {
    if (!Array.isArray(queries)) throw new Error('Queries parameter must be an array');

    conn = await pool.getConnection();
    await conn.beginTransaction();

    const results = [];
    for (let i = 0; i < queries.length; i++) {
      const query = queries[i];
      const params = Array.isArray(parameters[i]) ? parameters[i] : [];

      try {
        const [result] = await conn.query(query, params);
        results.push(result);
      } catch (queryErr) {
        await conn.rollback();
        throw new Error(`Query #${i+1} failed: ${queryErr.message}`);
      }
    }

    await conn.commit();
    return results.length > 0 ? results : true;
  } catch (err) {
    if (conn) {
      try {
        await conn.rollback();
      } catch (rollbackErr) {
        console.error('Error during rollback:', rollbackErr);
      }
    }
    console.error(`Transaction failed: ${err.message}`);
    throw new Error(`Failed to execute transaction: ${err.message}`);
  } finally {
    if (conn) conn.release();
  }
});

global.exports('PreparedStatement', async (query, parameters = []) => {
  let conn;
  try {
    conn = await pool.getConnection();
    const [rows] = await conn.execute(query, parameters);
    return rows;
  } catch (err) {
    throw new Error(`Failed to execute prepared statement: ${err}`);
  } finally {
    if (conn) conn.release();
  }
});

// Add a function to check pool status
global.exports('GetPoolStatus', () => {
  // Return pool status synchronously (not as a promise)
  return {
    threadId: pool.threadId,
    config: pool.config,
    activeConnections: pool._allConnections?.length || 0,
    idleConnections: pool._freeConnections?.length || 0,
    totalConnections: pool._allConnections?.length || 0
  };
});

// Add periodic connection cleanup function
setInterval(() => {
  try {
    // Get pool status directly without using the export
    const status = {
      threadId: pool.threadId,
      config: pool.config,
      activeConnections: pool._allConnections?.length || 0,
      idleConnections: pool._freeConnections?.length || 0,
      totalConnections: pool._allConnections?.length || 0
    };

    // If we're getting close to the connection limit, force a cleanup
    if (status.activeConnections > 0.8 * (status.config?.connectionLimit || 50)) {
      console.log(`^3MySQL connection pool getting high (${status.activeConnections}/${status.config?.connectionLimit || 50}), forcing cleanup...^7`);

      // The following will force unused connections to be released
      pool.query('SELECT 1').catch(err => console.error('Error in connection cleanup:', err));
    }
  } catch (err) {
    console.error('Error during connection pool maintenance:', err);
  }
}, 30000); // Run every 30 seconds
