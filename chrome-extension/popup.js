// popup.js — Claude Usage Tracker popup logic

import {
  getActiveProfile,
  getProfiles,
  getActiveProfileId,
  createProfile,
  setActiveProfileId,
} from './storage.js';

// ── DOM refs ───────────────────────────────────────────────────────────────

const $ = id => document.getElementById(id);

const profileBtn      = $('profileBtn');
const profileLabel    = $('profileLabel');
const profileDropdown = $('profileDropdown');
const settingsBtn     = $('settingsBtn');
const refreshBtn      = $('refreshBtn');
const refreshIcon     = $('refreshIcon');
const updatedLabel    = $('updatedLabel');
const footerBar       = $('footerBar');

const stateLoading = $('stateLoading');
const stateNoKey   = $('stateNoKey');
const stateError   = $('stateError');
const errorTitle   = $('errorTitle');
const errorDetail  = $('errorDetail');
const usageSection = $('usageSection');
const opusCard     = $('opusCard');

const openSettingsBtn = $('openSettingsBtn');
const retryBtn        = $('retryBtn');

// ── Helpers ────────────────────────────────────────────────────────────────

function showOnly(el) {
  for (const s of [stateLoading, stateNoKey, stateError, usageSection]) s.hidden = true;
  footerBar.hidden = true;
  el.hidden = false;
  if (el === usageSection) footerBar.hidden = false;
}

function pctColor(pct) {
  if (pct >= 90) return 'red';
  if (pct >= 75) return 'yellow';
  return '';
}

function formatCountdown(isoString) {
  if (!isoString) return '–';
  const delta = new Date(isoString) - Date.now();
  if (delta <= 0) return 'resetting soon';
  const h = Math.floor(delta / 3_600_000);
  const m = Math.floor((delta % 3_600_000) / 60_000);
  if (h > 0) return `resets in ${h}h ${m}m`;
  const s = Math.floor((delta % 60_000) / 1_000);
  return `resets in ${m}m ${s}s`;
}

function formatDate(isoString) {
  if (!isoString) return '–';
  return new Date(isoString).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function formatUpdated(isoString) {
  if (!isoString) return 'Never updated';
  const delta = Date.now() - new Date(isoString);
  if (delta < 60_000) return 'Updated just now';
  const m = Math.floor(delta / 60_000);
  return `Updated ${m}m ago`;
}

function setBar(barId, pct) {
  const el = $(barId);
  const clamped = Math.min(100, Math.max(0, pct));
  el.style.width = `${clamped}%`;
  el.className = `progress-bar ${pctColor(pct)}`;
}

function setCard(barId, pctId, pct, resetId, resetText) {
  setBar(barId, pct);
  $(pctId).textContent = `${Math.round(pct)}%`;
  $(pctId).style.color = pct >= 90 ? 'var(--red)' : pct >= 75 ? 'var(--yellow)' : '';
  if (resetId) $(resetId).textContent = resetText;
}

// ── Profile dropdown ───────────────────────────────────────────────────────

async function buildProfileDropdown() {
  const [profiles, activeId] = await Promise.all([getProfiles(), getActiveProfileId()]);

  profileLabel.textContent = profiles.find(p => p.id === activeId)?.name ?? 'Profile';

  profileDropdown.innerHTML = '';

  for (const p of profiles) {
    const li = document.createElement('li');
    li.setAttribute('role', 'option');
    li.dataset.id = p.id;
    if (p.id === activeId) li.classList.add('active');

    const dot = document.createElement('span');
    dot.className = 'dot';

    const name = document.createElement('span');
    name.textContent = p.name;

    li.append(dot, name);
    li.addEventListener('click', () => switchProfile(p.id));
    profileDropdown.appendChild(li);
  }

  if (profiles.length > 0) {
    const div = document.createElement('li');
    div.className = 'divider';
    div.setAttribute('role', 'separator');
    profileDropdown.appendChild(div);
  }

  const addLi = document.createElement('li');
  addLi.className = 'add-btn';
  addLi.textContent = '+ New Profile';
  addLi.addEventListener('click', addProfile);
  profileDropdown.appendChild(addLi);
}

async function switchProfile(id) {
  closeDropdown();
  showOnly(stateLoading);
  await chrome.runtime.sendMessage({ type: 'SWITCH_PROFILE', profileId: id });
  await render();
}

async function addProfile() {
  closeDropdown();
  const newProfile = await createProfile();
  await switchProfile(newProfile.id);
}

// ── Dropdown toggle ────────────────────────────────────────────────────────

function toggleDropdown() {
  const open = profileDropdown.classList.toggle('open');
  profileBtn.setAttribute('aria-expanded', String(open));
}

function closeDropdown() {
  profileDropdown.classList.remove('open');
  profileBtn.setAttribute('aria-expanded', 'false');
}

document.addEventListener('click', e => {
  if (!e.target.closest('.profile-switcher')) closeDropdown();
});

profileBtn.addEventListener('click', e => { e.stopPropagation(); toggleDropdown(); });

// ── Render ─────────────────────────────────────────────────────────────────

async function render() {
  await buildProfileDropdown();

  const profile = await getActiveProfile();
  if (!profile) { showOnly(stateNoKey); return; }

  const usage = profile.cachedUsage;

  if (!usage) {
    // First load — trigger background refresh then wait briefly
    chrome.runtime.sendMessage({ type: 'REFRESH' });
    showOnly(stateLoading);

    // Poll storage for up to 5 seconds
    let attempts = 0;
    const poll = setInterval(async () => {
      attempts++;
      const fresh = await getActiveProfile();
      if (fresh?.cachedUsage) {
        clearInterval(poll);
        renderUsage(fresh);
      } else if (attempts >= 10) {
        clearInterval(poll);
        // Check if no session key
        const hasCookie = await checkForSessionKey(profile);
        if (!hasCookie) showOnly(stateNoKey);
        else showError('No data', 'Could not fetch usage. Try again.');
      }
    }, 500);
    return;
  }

  renderUsage(profile);
}

async function checkForSessionKey(profile) {
  if (profile.sessionKey) return true;
  try {
    const cookie = await chrome.cookies.get({ url: 'https://claude.ai', name: 'sessionKey' });
    return !!cookie?.value;
  } catch { return false; }
}

function renderUsage(profile) {
  const { cachedUsage: u, lastUpdated, settings = {} } = profile;

  const mode = settings.percentageMode ?? 'used';

  function displayPct(raw) {
    return mode === 'remaining' ? Math.max(0, 100 - raw) : raw;
  }

  // Session
  setCard(
    'sessionBar', 'sessionPct', displayPct(u.session.percentage),
    'sessionReset', formatCountdown(u.session.resetAt),
  );

  // Weekly
  setCard(
    'weeklyBar', 'weeklyPct', displayPct(u.weekly.percentage),
    'weeklyReset', `Resets ${formatDate(u.weekly.resetAt)}`,
  );

  // Opus
  if (u.hasOpus) {
    opusCard.hidden = false;
    setCard('opusBar', 'opusPct', displayPct(u.opus.percentage), null, null);
  } else {
    opusCard.hidden = true;
  }

  updatedLabel.textContent = formatUpdated(lastUpdated);
  showOnly(usageSection);
}

function showError(title, detail) {
  errorTitle.textContent = title;
  errorDetail.textContent = detail;
  showOnly(stateError);
}

// ── Refresh button ─────────────────────────────────────────────────────────

refreshBtn.addEventListener('click', async () => {
  refreshBtn.classList.add('loading');
  await chrome.runtime.sendMessage({ type: 'REFRESH' });

  // Short wait for background to finish
  await new Promise(r => setTimeout(r, 1200));
  refreshBtn.classList.remove('loading');
  await render();
});

// ── Settings / retry ───────────────────────────────────────────────────────

settingsBtn.addEventListener('click', () => chrome.runtime.openOptionsPage());
openSettingsBtn.addEventListener('click', () => chrome.runtime.openOptionsPage());
retryBtn.addEventListener('click', () => { showOnly(stateLoading); render(); });

// ── Init ───────────────────────────────────────────────────────────────────

render();
