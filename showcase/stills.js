// 预览：node stills.js out_dir t1 t2 ...
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

(async () => {
  const [outDir, ...times] = process.argv.slice(2);
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  page.on('pageerror', e => console.error('pageerror', e.message));
  page.on('console', m => m.type() === 'error' && console.error('console', m.text()));
  await page.goto('file://' + path.join(__dirname, 'index.html'));
  await page.evaluate(() => window.ready);
  for (const t of times) {
    await page.evaluate(t => window.renderFrame(t), +t);
    await page.screenshot({ path: path.join(outDir, `t${(+t).toFixed(2).padStart(6, '0')}.png`) });
  }
  await browser.close();
})();
