import fs from 'node:fs';
import { Client } from 'pg';

const connectionString = process.env.SUPABASE_DB_URL;
if (!connectionString) {
  throw new Error('SUPABASE_DB_URL nao informado.');
}

const sql = fs.readFileSync('supabase/migrations/001_schema.sql', 'utf8');
const client = new Client({
  connectionString,
  ssl: { rejectUnauthorized: false }
});

await client.connect();
try {
  await client.query(sql);
  console.log('Schema aplicado com sucesso.');
} finally {
  await client.end();
}
