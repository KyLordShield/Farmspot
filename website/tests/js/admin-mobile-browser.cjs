/* Run render-responsive-pages.php first. Uses synthetic templates and a fresh,
   headless browser; never signs into the app or sends a form to the server. */
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const fixtures = path.join(root, 'storage/framework/testing/responsive');
const pages = process.argv.length > 2 ? process.argv.slice(2) : fs.readdirSync(fixtures).filter(name => name.endsWith('.html'));
const failures = [];

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    for (const name of pages) {
      const context = await browser.newContext({ viewport: { width: 1366, height: 900 }, reducedMotion: 'reduce' });
      let mobileCss = false;
      await context.route('**/*', async route => {
        const url = new URL(route.request().url());
        if (route.request().method() !== 'GET') return route.abort();
        if (url.pathname === '/qa/' + name) return route.fulfill({ contentType: 'text/html', body: fs.readFileSync(path.join(fixtures, name)) });
        let file;
        if (url.hostname === 'cdn.jsdelivr.net' && url.pathname.endsWith('bootstrap.min.css')) file = path.join(fixtures, 'bootstrap.css');
        else if (url.hostname === 'cdn.jsdelivr.net' && url.pathname.endsWith('bootstrap.bundle.min.js')) file = path.join(fixtures, 'bootstrap.js');
        else if (url.hostname === 'cdn.jsdelivr.net' && url.pathname.endsWith('bootstrap-icons.min.css')) file = path.join(fixtures, 'icons.css');
        else if (url.hostname === 'cdn.jsdelivr.net' && url.pathname.endsWith('.woff2')) file = path.join(fixtures, 'icons.woff2');
        else if (url.pathname.startsWith('/css/') || url.pathname.startsWith('/js/') || url.pathname.startsWith('/images/')) {
          file = path.resolve(root, 'public', '.' + url.pathname);
          if (!file.startsWith(path.join(root, 'public') + path.sep)) return route.abort();
        }
        if (url.pathname.endsWith('/admin-mobile.css') && !mobileCss) return route.fulfill({ contentType: 'text/css', body: '' });
        if (!file || !fs.existsSync(file)) return route.fulfill({ body: '', contentType: url.pathname.endsWith('.css') ? 'text/css' : 'text/plain' });
        const type = file.endsWith('.css') ? 'text/css' : file.endsWith('.js') ? 'application/javascript' : file.endsWith('.woff2') ? 'font/woff2' : file.endsWith('.svg') ? 'image/svg+xml' : 'image/png';
        return route.fulfill({ contentType: type, body: fs.readFileSync(file) });
      });
      const page = await context.newPage();
      await page.goto('http://farmspot.test/qa/' + name);
      await page.evaluate(() => document.fonts.ready);
      const geometry = () => page.evaluate(() => Array.from(document.querySelectorAll('.content,.sidebar,.page-head,.panel,.stat-grid,.ld-card,.analytics-card,.user-details-header')).map(element => {
        const rect = element.getBoundingClientRect();
        return [element.className, ...['x', 'y', 'width', 'height'].map(key => Math.round(rect[key] * 10) / 10)];
      }));
      const before = await geometry();
      mobileCss = true;
      await page.addStyleTag({ content: fs.readFileSync(path.join(root, 'public/css/admin-mobile.css'), 'utf8') });
      assert.deepEqual(await geometry(), before, name + ': desktop geometry changed');
      for (const width of [320, 390, 768]) {
        await page.setViewportSize({ width, height: 844 });
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        if (width <= 390 && ['users.html', 'listings.html', 'seller-requests.html', 'appeals.html'].includes(name)) {
          const table = page.locator('table.data-table').first();
          assert.equal(await table.evaluate(el => getComputedStyle(el).display), 'table');
          const actions = table.locator('.actions').first();
          if (await actions.count()) {
            const tops = await actions.evaluate(el => Array.from(el.querySelectorAll('a,button')).map(button => Math.round(button.getBoundingClientRect().top)));
            assert.ok(tops.every(top => Math.abs(top - tops[0]) <= 1), name + ': action buttons must stay horizontal');
          }
          const region = page.locator('.table-responsive').first();
          await region.evaluate(el => { el.scrollLeft = el.scrollWidth; });
          assert.ok(await region.evaluate(el => el.scrollLeft > 0), name + ': table must swipe horizontally');
          await region.evaluate(el => { el.scrollLeft = 0; });
        }
        const overflow = await page.evaluate(() => ({ width: document.documentElement.clientWidth, scroll: document.documentElement.scrollWidth }));
        if (overflow.scroll > overflow.width + 1) {
          const elements = await page.evaluate(() => Array.from(document.querySelectorAll('body *')).filter(el => {
            const rect = el.getBoundingClientRect();
            return rect.right > innerWidth + 1 && rect.width;
          }).slice(0, 12).map(el => [el.tagName, el.className, el.getBoundingClientRect().width, el.scrollWidth]));
          failures.push({ page: name, width, overflow, elements });
          console.log(await page.evaluate(() => ['html','body','.content','.mod-page','.mod-queue','.mod-table-scroll'].map(selector => {
            const el = document.querySelector(selector); if (!el) return null;
            const style = getComputedStyle(el); return [selector, el.getBoundingClientRect().width, el.scrollWidth, style.overflowX, style.overflowY, style.contain];
          })));
        }
        if (name === 'reports-populated.html') {
          await page.locator('.mod-table-scroll').evaluate(el => { el.scrollLeft = el.scrollWidth; });
          assert.ok(await page.locator('.mod-table-scroll').evaluate(el => el.scrollLeft > 0), 'Report table must remain swipeable');
          await page.locator('[data-mod-dialog]').click();
          const dialog = await page.locator('dialog[open]').boundingBox();
          assert.ok(dialog && dialog.x >= 0 && dialog.x + dialog.width <= width + 1, 'Report status dialog must fit the viewport');
          await page.keyboard.press('Escape');
          await page.locator('.mod-table-scroll').evaluate(el => { el.scrollLeft = 0; });
        }
        if (width === 390) {
          const toggle = page.locator('#sidebarToggle');
          if (await toggle.count()) {
            await toggle.click();
            assert.equal(await toggle.getAttribute('aria-expanded'), 'true');
            await page.keyboard.press('Escape');
            assert.equal(await toggle.getAttribute('aria-expanded'), 'false');
          }
          if (name === 'dashboard.html') {
            await page.locator('#dashAddEvent').click();
            assert.equal(await page.locator('.event-form').isVisible(), true);
          }
          if (name === 'listings.html') {
            await page.locator('[data-bs-target="#categoryPanel"]').click();
            const modal = page.locator('#categoryPanel .modal-content');
            await modal.waitFor({ state: 'visible' });
            const box = await modal.boundingBox();
            assert.ok(box.x >= 0 && box.x + box.width <= width + 1, 'Category dialog must fit the phone');
            await page.keyboard.press('Escape');
          }
          await page.screenshot({ path: path.join(fixtures, name.replace('.html', '-390.png')), fullPage: true });
        }
      }
      console.log(name + ': checked 3 mobile widths and unchanged desktop geometry');
      await context.close();
    }
    assert.equal(failures.length, 0, JSON.stringify(failures, null, 2));
    console.log('PASS: ' + pages.length + ' pages; screenshots in ' + fixtures);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
