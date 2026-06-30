import fs from 'node:fs';
import { Client } from 'pg';

const connectionString = process.env.SUPABASE_DB_URL;
if (!connectionString) {
  throw new Error('SUPABASE_DB_URL nao informado.');
}

const client = new Client({
  connectionString,
  ssl: { rejectUnauthorized: false }
});

function parseCsv(text) {
  const rows = [];
  let row = [];
  let value = '';
  let quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    const next = text[i + 1];
    if (ch === '"' && quoted && next === '"') {
      value += '"';
      i += 1;
    } else if (ch === '"') {
      quoted = !quoted;
    } else if (ch === ',' && !quoted) {
      row.push(value);
      value = '';
    } else if ((ch === '\n' || ch === '\r') && !quoted) {
      if (ch === '\r' && next === '\n') i += 1;
      row.push(value);
      if (row.some((cell) => cell !== '')) rows.push(row);
      row = [];
      value = '';
    } else {
      value += ch;
    }
  }
  if (value || row.length) {
    row.push(value);
    rows.push(row);
  }
  const headers = rows.shift() || [];
  return rows.map((cells) => Object.fromEntries(headers.map((header, index) => [header, cells[index] || ''])));
}

function num(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function bool(value) {
  const text = String(value || '').toLowerCase();
  return !['false', '0', 'nao', 'não', 'inativo'].includes(text);
}

async function importProducts() {
  const rows = parseCsv(fs.readFileSync('supabase_import/products.csv', 'utf8'));
  const columns = [
    'codigo', 'descricao', 'marca', 'aplicacao', 'ano', 'ipi', 'preco_sem_imposto',
    'estoque', 'estoque_quantidade', 'preco_sp', 'preco_pr', 'status_estoque',
    'status_cadastro', 'url_imagem', 'grupo', 'categoria', 'montadora', 'detalhes',
    'oem', '"similar"'
  ];
  const updates = columns
    .filter((column) => column !== 'codigo')
    .map((column) => `${column} = excluded.${column}`)
    .concat('updated_at = now()')
    .join(',');
  const values = rows.filter((row) => row.codigo).map((row) => [
    row.codigo, row.descricao, row.marca, row.aplicacao, row.ano,
    num(row.ipi), num(row.preco_sem_imposto), row.estoque, num(row.estoque_quantidade),
    num(row.preco_sp), num(row.preco_pr), row.status_estoque, row.status_cadastro,
    row.url_imagem, row.grupo, row.categoria, row.montadora, row.detalhes, row.oem, row.similar
  ]);
  for (const chunk of chunks(values, 300)) {
    const params = [];
    const placeholders = chunk.map((row, rowIndex) => {
      params.push(...row);
      const offset = rowIndex * columns.length;
      return `(${columns.map((_, colIndex) => `$${offset + colIndex + 1}`).join(',')})`;
    }).join(',');
    const sql = `
    insert into public.products (
      ${columns.join(',')}
    ) values ${placeholders}
    on conflict (codigo) do update set
      ${updates}
  `;
    await client.query(sql, params);
  }
  console.log(`Produtos importados: ${values.length}`);
}

async function importSimple(path, table, columns, mapper) {
  if (!fs.existsSync(path)) return;
  const rows = parseCsv(fs.readFileSync(path, 'utf8'));
  const placeholders = columns.map((_, index) => `$${index + 1}`).join(',');
  const updates = columns.map((column) => `${column}=excluded.${column}`).join(',');
  const conflict = columns.includes('legacy_id') ? '(legacy_id)' : '(id)';
  const sql = `insert into public.${table} (${columns.join(',')}) values (${placeholders}) on conflict ${conflict} do update set ${updates}`;
  let total = 0;
  for (const row of rows) {
    if (!Object.values(row).some(Boolean)) continue;
    await client.query(sql, mapper(row));
    total += 1;
  }
  console.log(`${table}: ${total}`);
}

await client.connect();
try {
  await client.query('begin');
  await importProducts();
  await importSimple('supabase_import/carriers.csv', 'carriers', ['legacy_id', 'cnpj', 'nome', 'telefone', 'endereco', 'ativo'], (r) => [
    r.legacy_id || null, r.cnpj, r.nome || 'Transportadora', r.telefone, r.endereco, bool(r.ativo)
  ]);
  await importSimple('supabase_import/payment_terms.csv', 'payment_terms', ['legacy_id', 'descricao', 'ativo'], (r) => [
    r.legacy_id || null, r.descricao || 'Prazo', bool(r.ativo)
  ]);
  await client.query('commit');
  console.log('Importacao concluida.');
} catch (error) {
  await client.query('rollback');
  throw error;
} finally {
  await client.end();
}

function chunks(items, size) {
  const out = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}
