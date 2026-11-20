const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');
const repo = path.resolve(__dirname, '..');
(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 860 }, locale: 'en-US' });
    page.setDefaultTimeout(8000);
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.route('http://m3ify.test/**', route => route.fulfill({ contentType: 'text/html', body: '<!doctype html><html lang="en"><title>m3ify theme fixture</title><body><div class="main-home-home"></div><div class="main-nowPlayingBar-extraControls"></div></body></html>' }));
    await page.goto('http://m3ify.test/');
    await page.addStyleTag({ path: path.join(repo, 'theme/m3.css') });
    await page.evaluate(() => {
      window.calls = []; window.events = {};
      window.Spicetify = {
        Player: { data: { item: { uri: 'spotify:track:fixture', metadata: { title: 'A track from your library', artist_name: 'Current artist', image_url: '' } } }, isPlaying: () => true,
          addEventListener: (name, cb) => { window.events[name] = cb; }, togglePlay: () => calls.push('play'), back: () => calls.push('back'), next: () => calls.push('next') },
        Platform: { History: { push: path => calls.push(path) } }, showNotification: text => calls.push(text),
        colorExtractor: async uri => { if (uri !== 'spotify:track:fixture') throw new Error('Expected a Spotify URI'); return { VIBRANT: '#567845' }; }
      };
    });
    await page.addScriptTag({ path: path.join(repo, 'theme/m3.js') });
    await page.evaluate(() => { const bar = document.createElement('div'); bar.className = 'playback-progressbar'; bar.innerHTML = '<div data-testid="progress-bar-background"><div><div class="x-progressBar-fillColor"></div></div></div>'; document.body.append(bar); });
    const progressStyle = await page.locator('.x-progressBar-fillColor').evaluate(el => ({ height: getComputedStyle(el).height, mask: getComputedStyle(el).maskImage }));
    assert.equal(progressStyle.height, '12px');
    assert(progressStyle.mask.includes('data:image/svg+xml'), 'Current Spotify fill must receive the wave mask');
    assert.equal(await page.locator('.x-progressBar-fillColor').evaluate(el => getComputedStyle(el).height), '12px');
    assert.match(await page.locator('.x-progressBar-fillColor').evaluate(el => getComputedStyle(el).maskImage), /svg/);
    await page.getByRole('button', { name: 'Play / pause', exact: true }).click();
    assert.deepEqual(await page.evaluate(() => calls), ['play']);
    await page.getByRole('button', { name: 'm3ify settings', exact: true }).click();
    await page.getByRole('switch', { name: 'AMOLED black' }).click();
    assert.equal(await page.locator('html').getAttribute('data-m3-amoled'), 'true');
    await page.getByRole('button', { name: 'Русский', exact: true }).click();
    await page.getByRole('heading', { name: 'Настройки m3ify' }).waitFor();
    await page.getByRole('button', { name: 'Мои треки', exact: true }).click();
    assert((await page.evaluate(() => calls)).includes('/collection/local-files'));
    await page.keyboard.press('Control+Alt+m');
    await page.getByRole('heading', { name: 'Настройки m3ify' }).waitFor();
    await page.getByRole('button', { name: 'Добавить папку с музыкой' }).click();
    assert((await page.evaluate(() => calls)).includes('/preferences'));
    // Hostile metadata must remain text, and absent artwork must not show a broken image.
    await page.evaluate(() => { Spicetify.Player.data.item.metadata.title = '<img src=x onerror=alert(1)>'; events.songchange(); });
    assert.equal(await page.locator('.m3-song-title').textContent(), '<img src=x onerror=alert(1)>');
    assert.equal(await page.locator('#m3-now-playing img:not([hidden])').count(), 0);
    await page.evaluate(() => { Spicetify.Player.data.item.metadata.image_url = 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192"><rect width="192" height="192" fill="#567845"/><circle cx="96" cy="96" r="56" fill="#d1e9b8"/></svg>'); events.songchange(); });
    await page.waitForFunction(() => document.documentElement.style.getPropertyValue('--m3-accent') === '#bbc9b5');
    assert.equal(await page.locator('#m3-now-playing img:not([hidden])').count(), 1);
    // Navigation remounts the card once, using the real player's current state.
    await page.evaluate(() => { document.querySelector('.main-home-home').replaceChildren(); });
    await page.locator('#m3-now-playing').waitFor();
    assert.equal(await page.locator('#m3-now-playing').count(), 1);
    await page.evaluate(() => { Spicetify.Player.data.item = null; events.songchange(); });
    assert.equal(await page.locator('#m3-now-playing').count(), 0);
    await page.getByRole('button', { name: 'Настройки m3ify', exact: true }).click();
    if (process.env.M3_SCREENSHOT) await page.screenshot({ path: process.env.M3_SCREENSHOT });
    await page.setViewportSize({ width: 390, height: 800 });
    const bounds = await page.locator('dialog').boundingBox();
    assert(bounds.x >= 0 && bounds.x + bounds.width <= 390, 'Settings must fit a narrow window');
    await page.keyboard.press('Escape');
    assert.equal(await page.locator('dialog[open]').count(), 0);
    assert.deepEqual(errors, []);
    console.log('UI checks passed: playback, preferences, language, navigation, untrusted metadata, empty player, narrow window');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exit(1); });
