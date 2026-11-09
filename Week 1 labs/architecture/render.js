// Render each HTML file given on the command line to a PNG with headless Firefox (Playwright).
const { firefox } = require('playwright');  // npm install playwright && npx playwright install firefox
(async () => {
  const b = await firefox.launch({ headless: true });
  for (const f of process.argv.slice(2)) {
    const p = await b.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 2 });
    await p.goto('file://' + f); await p.waitForTimeout(500);
    const el = p.locator('#canvas'); await el.screenshot({ path: f.replace(/\.html$/, '.png') });
    console.log('rendered', f.replace(/\.html$/, '.png')); await p.close();
  }
  await b.close();
})();
