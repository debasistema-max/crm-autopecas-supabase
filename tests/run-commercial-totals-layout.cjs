const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { chromium } = require('playwright');

const context = vm.createContext({ money: value => new Intl.NumberFormat('pt-BR', {
  style: 'currency', currency: 'BRL'
}).format(value) });
vm.runInContext(fs.readFileSync('public/js/commercial_prices.js', 'utf8'), context);
const styles = ['theme', 'app', 'seller', 'commercial_prices'].map(name =>
  `<style>${fs.readFileSync(`public/css/${name}.css`, 'utf8')}</style>`).join('');
const scenarios = [[], [{ quantidade: 20, preco: 13000, desconto_percentual: 10,
  fiscal_details: { status: 'OK', base_price: 10000, ipi_amount: 1000,
    icms_st_amount: 2000, total_taxes: 3000, final_price: 13000 } }],
[{ quantidade: 1, preco: 100 }]];

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    let count = 0;
    for (const width of [320, 390, 768, 1440]) {
      const page = await browser.newPage({ viewport: { width, height: 900 } });
      for (const [index, items] of scenarios.entries()) {
        await page.setContent(`${styles}<main class="commercial-document" style="padding:16px">
          <div class="sap-totals">${context.renderDocumentTaxTotals(items)}</div></main>`);
        const result = await page.locator('.commercial-tax-totals').evaluate(summary => {
          const bounds = summary.getBoundingClientRect();
          const rows = [...summary.children].map(row => row.getBoundingClientRect());
          const total = summary.querySelector('.commercial-grand-total');
          return {
            display: getComputedStyle(summary).display,
            fits: summary.scrollWidth <= summary.clientWidth + 1,
            contained: rows.every(row => row.left >= bounds.left - 1 && row.right <= bounds.right + 1),
            vertical: rows.every((row, i) => !i || row.top >= rows[i - 1].bottom - 1),
            totalColor: getComputedStyle(total.querySelector('strong')).color,
            textColor: getComputedStyle(total).color,
            text: total.textContent,
            pageFits: document.documentElement.scrollWidth <= innerWidth
          };
        });
        assert.equal(result.display, 'grid');
        for (const key of ['fits', 'contained', 'vertical', 'pageFits']) {
          assert.equal(result[key], true, `${width}px scenario ${index}: ${key}`);
        }
        assert.equal(result.totalColor, result.textColor);
        assert.match(result.text, /Total com impostos/);
        if (index === 1) assert.match(result.text, /234\.000,00/);
        count += 1;
        if (index === 1 && [390, 1440].includes(width)) {
          const file = path.join(process.env.CRM_LAYOUT_SCREENSHOT_DIR || os.tmpdir(), `crm-tax-totals-${width}.png`);
          await page.screenshot({ path: file });
          console.log(`Screenshot: ${file}`);
        }
      }
      await page.close();
    }
    console.log(`PASS: ${count} responsive tax summary scenarios (no network or real data).`);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
