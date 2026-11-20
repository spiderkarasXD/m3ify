/* m3ify 1.4.0 — Spicetify theme, no external services or telemetry. */
(() => {
  'use strict';
  if (window.__m3ify) return;
  window.__m3ify = true;
  const root = document.documentElement;
  const defaults = { language: 'auto', dynamic: true, color: '#d1e9b8', amoled: false, wave: true, motion: true, canvas: false };
  let settings;
  try { settings = { ...defaults, ...JSON.parse(localStorage.getItem('m3ify') || '{}') }; }
  catch { settings = { ...defaults }; }
  const strings = {
    en: { title: 'Your music, in colour', settings: 'm3ify settings', close: 'Close', language: 'Language', auto: 'Automatic', dynamic: 'Colour from artwork', color: 'Accent colour', amoled: 'AMOLED black', wave: 'Wavy progress', motion: 'Animations', canvas: 'Canvas videos', local: 'My tracks', folder: 'Add a music folder', playing: 'Now playing', play: 'Play / pause', previous: 'Previous track', next: 'Next track', note: 'Material 3 for your Spotify. Extensions are managed with Spicetify.', folderNote: 'In Spotify settings, enable “Show Local Files” and choose “Add a source”.' },
    ru: { title: 'Музыка в твоих цветах', settings: 'Настройки m3ify', close: 'Закрыть', language: 'Язык', auto: 'Автоматически', dynamic: 'Цвет из обложки', color: 'Акцентный цвет', amoled: 'AMOLED-чёрный', wave: 'Волнистый прогресс', motion: 'Анимации', canvas: 'Canvas-видео', local: 'Мои треки', folder: 'Добавить папку с музыкой', playing: 'Сейчас играет', play: 'Пауза / воспроизведение', previous: 'Предыдущий трек', next: 'Следующий трек', note: 'Material 3 для твоего Spotify. Расширения доступны через Spicetify.', folderNote: 'В настройках Spotify включи «Показывать локальные файлы» и выбери «Добавить источник».' }
  };
  const lang = () => settings.language === 'auto' ? ((root.lang || navigator.language).startsWith('ru') ? 'ru' : 'en') : settings.language;
  const t = key => (strings[lang()] || strings.en)[key];
  const node = (tag, cls, text) => { const el = document.createElement(tag); if (cls) el.className = cls; if (text) el.textContent = text; return el; };
  const button = (text, action) => { const el = node('button', 'm3-button', text); el.type = 'button'; el.addEventListener('click', action); return el; };
  const paths = { play: 'm9 5 10 7-10 7Z', previous: 'M6 5v14M18 5 8 12l10 7Z', next: 'M18 5v14M6 5l10 7-10 7Z' };
  function transport(key, action) {
    const el = button('', action);
    el.setAttribute('aria-label', t(key));
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('width', '20'); svg.setAttribute('height', '20'); svg.setAttribute('aria-hidden', 'true');
    const path = document.createElementNS(svg.namespaceURI, 'path');
    path.setAttribute('d', paths[key]); path.setAttribute('fill', 'none'); path.setAttribute('stroke', 'currentColor'); path.setAttribute('stroke-width', '1.5'); path.setAttribute('stroke-linejoin', 'round');
    svg.append(path); el.append(svg); return el;
  }
  function applySettings() {
    for (const key of ['amoled', 'wave', 'motion', 'canvas']) root.dataset[`m3${key[0].toUpperCase()}${key.slice(1)}`] = String(!!settings[key]);
    const color = /^#[a-f0-9]{6}$/i.test(settings.color) ? settings.color : defaults.color;
    root.style.setProperty('--m3-accent', color);
    // Pick contrasting ink for any user-selected accent.
    const rgb = color.slice(1).match(/../g).map(v => parseInt(v, 16) / 255).map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4);
    root.style.setProperty('--m3-on-accent', rgb[0] * .2126 + rgb[1] * .7152 + rgb[2] * .0722 > .179 ? '#10120f' : '#ffffff');
  }
  function persist() { try { localStorage.setItem('m3ify', JSON.stringify(settings)); } catch {} applySettings(); updateSong(); }
  let api, card, dialog, settingsButton, songGeneration = 0, artwork = '', cachedArtwork = '', cachedAccent = '';
  function openSettings() {
    if (dialog?.open) return;
    dialog?.remove();
    dialog = node('dialog'); dialog.id = 'm3-settings';
    const header = node('header'); const heading = node('h2', '', t('settings')); heading.id = 'm3-settings-title';
    dialog.setAttribute('aria-labelledby', heading.id);
    header.append(heading, button(t('close'), () => dialog.close()));
    dialog.append(header, node('p', '', t('note')));
    function row(key, input) { const label = node('div', 'm3-setting'); input.setAttribute('aria-label', t(key)); label.append(node('span', '', t(key)), input); dialog.append(label); }
    const language = node('div', 'm3-segments'); language.setAttribute('role', 'group');
    for (const [value, label] of [['auto', t('auto')], ['ru', 'Русский'], ['en', 'English']]) {
      const option = button(label, () => { settings.language = value; persist(); dialog.close(); openSettings(); settingsButton.textContent = t('settings'); });
      option.setAttribute('aria-pressed', String(settings.language === value)); language.append(option);
    }
    row('language', language);
    for (const key of ['dynamic', 'amoled', 'wave', 'motion', 'canvas']) {
      const input = button('', () => { settings[key] = !settings[key]; input.setAttribute('aria-checked', String(settings[key])); persist(); });
      input.className = 'm3-switch'; input.setAttribute('role', 'switch'); input.setAttribute('aria-checked', String(!!settings[key])); row(key, input);
    }
    const color = node('div', 'm3-colors'); color.setAttribute('role', 'group');
    const chooseColor = value => {
      settings.color = value; settings.dynamic = false; persist();
      dialog.querySelector('[role="switch"]').setAttribute('aria-checked', 'false');
      for (const swatch of color.querySelectorAll('button')) swatch.setAttribute('aria-pressed', String(swatch.dataset.color === value));
    };
    for (const value of ['#d1e9b8', '#b9dcf5', '#d4c4ef', '#f1c2cb', '#f3d2a5', '#e3e3db']) {
      const swatch = button('', () => chooseColor(value)); swatch.className = 'm3-swatch'; swatch.dataset.color = value;
      swatch.style.setProperty('--swatch', value); swatch.setAttribute('aria-label', value); swatch.setAttribute('aria-pressed', String(settings.color === value)); color.append(swatch);
    }
    row('color', color);
    const custom = node('input'); custom.type = 'text'; custom.value = settings.color; custom.maxLength = 7; custom.spellcheck = false; custom.className = 'm3-hex';
    custom.setAttribute('aria-label', 'HEX'); custom.addEventListener('change', () => { if (/^#[a-f0-9]{6}$/i.test(custom.value)) { chooseColor(custom.value); custom.removeAttribute('aria-invalid'); } else custom.setAttribute('aria-invalid', 'true'); });
    color.append(custom);
    const actions = node('div', 'm3-actions');
    actions.append(button(t('local'), () => { api.Platform.History.push('/collection/local-files'); dialog.close(); }), button(t('folder'), () => { api.Platform.History.push('/preferences'); api.showNotification(t('folderNote')); dialog.close(); }));
    dialog.append(actions);
    dialog.addEventListener('click', event => { if (event.target === dialog) { const r = dialog.getBoundingClientRect(); if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) dialog.close(); } });
    dialog.addEventListener('close', () => settingsButton.focus());
    document.body.append(dialog); dialog.showModal();
  }
  function mount() {
    const controls = document.querySelector('.main-nowPlayingBar-extraControls');
    if (controls && settingsButton.parentElement !== controls) controls.append(settingsButton);
    const home = document.querySelector('.main-home-home, [data-testid="home-page"]');
    if (home && !home.querySelector('#m3-now-playing') && api.Player.data?.item) {
      card = node('section'); card.id = 'm3-now-playing'; card.setAttribute('aria-label', t('playing'));
      const img = node('img', 'm3-art'); img.alt = ''; img.width = 192; img.height = 192;
      const content = node('div', 'm3-song');
      content.append(node('p', 'm3-eyebrow', t('playing')), node('h2', 'm3-song-title'), node('p', 'm3-song-artist'));
      const controls = node('div', 'm3-transport');
      controls.append(transport('previous', () => api.Player.back()), transport('play', () => api.Player.togglePlay()), transport('next', () => api.Player.next()));
      content.append(controls); card.append(img, content); home.prepend(card); renderSong();
    }
  }
  function renderSong() {
    if (!card?.isConnected) return;
    const meta = api.Player.data?.item?.metadata;
    if (!meta) { card.remove(); card = null; return; }
    card.querySelector('.m3-song-title').textContent = meta.title || '';
    card.querySelector('.m3-song-artist').textContent = meta.artist_name || '';
    card.querySelector('.m3-eyebrow').textContent = t('playing');
    card.setAttribute('aria-label', t('playing'));
    const img = card.querySelector('img');
    if (artwork) { img.src = artwork; img.hidden = false; } else { img.removeAttribute('src'); img.hidden = true; }
    const play = card.querySelector('.m3-transport button:nth-child(2)');
    for (const [index, key] of ['previous', 'play', 'next'].entries()) card.querySelectorAll('.m3-transport button')[index].setAttribute('aria-label', t(key));
    play.setAttribute('aria-pressed', String(api.Player.isPlaying()));
    play.querySelector('path').setAttribute('d', api.Player.isPlaying() ? 'M9 5v14M15 5v14' : paths.play);
  }
  async function updateSong() {
    if (!api) return;
    const generation = ++songGeneration;
    const item = api.Player.data?.item;
    const url = item?.metadata?.image_url || '';
    artwork = url.startsWith('spotify:image:') ? 'https://i.scdn.co/image/' + url.slice(14) : url;
    mount(); renderSong();
    if (!settings.dynamic || !artwork) return;
    if (cachedArtwork === artwork && cachedAccent) {
      root.style.setProperty('--m3-accent', cachedAccent);
      root.style.setProperty('--m3-on-accent', '#10120f');
      return;
    }
    try {
      const colors = await api.colorExtractor(item.uri);
      if (generation !== songGeneration || !settings.dynamic) return;
      const value = colors?.VIBRANT || colors?.LIGHT_VIBRANT || colors?.DESATURATED;
      if (!/^#?[a-f0-9]{6}$/i.test(value)) return;
      const hex = value.replace('#', '');
      // Pastel tone derived from the cover; keep dark text legible.
      const pastel = hex.match(/../g).map(v => Math.round(parseInt(v, 16) * .4 + 255 * .6).toString(16).padStart(2, '0')).join('');
      cachedArtwork = artwork; cachedAccent = '#' + pastel;
      root.style.setProperty('--m3-accent', cachedAccent);
      root.style.setProperty('--m3-on-accent', '#10120f');
    } catch { /* Keep the configured accent when artwork is unavailable. */ }
  }
  let attempts = 0;
  function start() {
    if (!window.Spicetify?.Player?.addEventListener || !window.Spicetify?.Platform?.History || !document.body) {
      if (++attempts < 60) setTimeout(start, 250);
      return;
    }
    api = window.Spicetify;
    settingsButton = button(t('settings'), openSettings); settingsButton.id = 'm3-settings-button';
    document.body.append(settingsButton);
    document.addEventListener('keydown', event => { if (event.ctrlKey && event.altKey && event.code === 'KeyM') { event.preventDefault(); openSettings(); } });
    api.Player.addEventListener('songchange', () => { applySettings(); updateSong(); });
    api.Player.addEventListener('onplaypause', renderSong);
    let pending = false;
    new MutationObserver(() => {
      if (pending) return;
      pending = true;
      requestAnimationFrame(() => { pending = false; mount(); });
    }).observe(document.body, { childList: true, subtree: true });
    applySettings(); updateSong();
  }
  start();
})();
