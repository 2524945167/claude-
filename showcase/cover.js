// 导出封面：node cover.js out/cover.png
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const out = path.resolve(process.argv[2] || path.join(__dirname, 'out', 'cover.png'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  page.on('pageerror', e => console.error('pageerror', e.message));
  await page.goto('file://' + path.join(__dirname, 'cover.html'));
  await page.evaluate(() => window.ready);
  await page.screenshot({ path: out });
  await browser.close();
  console.log('wrote', out);
})();
