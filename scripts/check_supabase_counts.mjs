import { Client } from 'pg';

const client = new Client({
  connectionString: process.env.SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false }
});

await client.connect();
try {
  for (const table of ['products', 'carriers', 'payment_terms', 'orders', 'order_items']) {
    const result = await client.query(`select count(*)::int as count from public.${table}`);
    console.log(`${table}: ${result.rows[0].count}`);
  }
} finally {
  await client.end();
}
