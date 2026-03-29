
const mysql = require('mysql2/promise');
require('dotenv').config();

async function checkSchema() {
  const pool = mysql.createPool({
    host: process.env.MYSQLHOST || process.env.DB_HOST || 'localhost',
    port: process.env.MYSQLPORT || process.env.DB_PORT || 3306,
    user: process.env.MYSQLUSER || process.env.DB_USER,
    password: process.env.MYSQLPASSWORD || process.env.DB_PASSWORD,
    database: process.env.MYSQLDATABASE || process.env.DB_NAME,
  });

  try {
    const [rows] = await pool.query('DESCRIBE service_drafts');
    console.log('Columns in service_drafts:');
    rows.forEach(row => console.log(`- ${row.Field} (${row.Type})`));
  } catch (err) {
    console.error('Error checking schema:', err.message);
  } finally {
    await pool.end();
  }
}

checkSchema();
