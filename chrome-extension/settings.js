// settings.js — Settings page for Claude Usage Tracker

import {
  getProfiles,
  getActiveProfileId,
  setActiveProfileId,
  createProfile,
  updateProfile,
  deleteProfile,
  generateProfileName,
} from './storage.js';

// ── Helpers ────────────────────────────────────────────────────────────────

const $ = id => document.getElementById(id);
function showToast(msg, duration = 2500) {
  const el = $('toast');
  el.textContent = msg;
  el.hidden = false;
  setTimeout(() => { el.hidden = true; }, duration);
}

// ── Section navigation ─────────────────────────────────────────────────────

const sections = {
  profiles:      $('sec-profiles'),
  appearance:    $('sec-appearance'),
  notifications: $('sec-notifications'),
  refresh:       $('sec-refresh'),
  about:         $('sec-about'),
};

document.querySelectorAll('.nav-link').forEach(link => {
  link.addEventListener('click', e => {
    e.preventDefault();
    const key = link.dataset.section;
    document.querySelectorAll('.nav-link').forEach(l => l.classList.remove('active'));
    link.classList.add('active');
    Object.entries(sections).forEach(([k, el]) => el.classList.toggle('hidden', k !== key));
    if (key === 'appearance' || key === 'notifications' || key === 'refresh') loadActiveSettings();
  });
});

// ── Profile list ───────────────────────────────────────────────────────────

async function renderProfiles() {
  const [profiles, activeId] = await Promise.all([getProfiles(), getActiveProfileId()]);
  const list = $('profileList');
  list.innerHTML = '';

  if (profiles.length === 0) {
    list.innerHTML = '<p style="color:var(--text-muted);font-size:13px;">No profiles yet.</p>';
    return;
  }

  for (const p of profiles) {
    const card = document.createElement('div');
    card.className = `profile-card${p.id === activeId ? ' active-profile' : ''}`;

    const initials = p.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase();

    const keyStatus = p.sessionKey
      ? '🔑 Session key set (manual)'
      : '🍪 Auto-detect cookie';

    card.innerHTML = `
      <div class="profile-avatar">${initials}</div>
      <div class="profile-info">
        <div class="profile-name-row">
          <span>${p.name}</span>
          ${p.id === activeId ? '<span class="active-badge">Active</span>' : ''}
        </div>
        <div class="profile-meta">${keyStatus}</div>
      </div>
      <div class="profile-actions">
        ${p.id !== activeId ? `<button class="btn-outline set-active-btn" data-id="${p.id}">Set active</button>` : ''}
        <button class="btn-outline edit-btn" data-id="${p.id}">Edit</button>
        ${profiles.length > 1 ? `<button class="btn-danger delete-btn" data-id="${p.id}">Delete</button>` : ''}
      </div>
    `;
    list.appendChild(card);
  }

  // Bind buttons
  list.querySelectorAll('.set-active-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      await setActiveProfileId(btn.dataset.id);
      await chrome.runtime.sendMessage({ type: 'SWITCH_PROFILE', profileId: btn.dataset.id });
      renderProfiles();
    });
  });

  list.querySelectorAll('.edit-btn').forEach(btn => {
    btn.addEventListener('click', () => openEditDialog(btn.dataset.id));
  });

  list.querySelectorAll('.delete-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      if (!confirm('Delete this profile? This cannot be undone.')) return;
      await deleteProfile(btn.dataset.id);
      renderProfiles();
      showToast('Profile deleted.');
    });
  });
}

$('addProfileBtn').addEventListener('click', async () => {
  await createProfile();
  renderProfiles();
  showToast('Profile created.');
});

// ── Profile edit dialog ────────────────────────────────────────────────────

let editingProfileId = null;

async function openEditDialog(profileId) {
  const profiles = await getProfiles();
  const profile  = profiles.find(p => p.id === profileId);
  if (!profile) return;

  editingProfileId = profileId;
  $('dialogTitle').textContent = 'Edit Profile';
  $('profileName').value = profile.name;
  $('sessionKeyInput').value = profile.sessionKey ?? '';
  $('sessionKeyInput').type = 'password';
  $('profileDialog').showModal();
}

$('toggleKeyVisible').addEventListener('click', () => {
  const inp = $('sessionKeyInput');
  inp.type = inp.type === 'password' ? 'text' : 'password';
});

$('cancelDialogBtn').addEventListener('click', () => $('profileDialog').close());

$('profileForm').addEventListener('submit', async e => {
  e.preventDefault();
  if (!editingProfileId) return;

  const name = $('profileName').value.trim() || generateProfileName();
  const key  = $('sessionKeyInput').value.trim() || null;

  await updateProfile(editingProfileId, {
    name,
    sessionKey: key,
    organizationId: null, // reset so it's re-discovered with new key
  });

  $('profileDialog').close();
  renderProfiles();
  showToast('Profile saved.');

  // Re-fetch with new credentials
  chrome.runtime.sendMessage({ type: 'REFRESH' });
});

// ── Per-profile settings ───────────────────────────────────────────────────

async function loadActiveSettings() {
  const profiles = await getProfiles();
  const activeId = await getActiveProfileId();
  const profile  = profiles.find(p => p.id === activeId) ?? profiles[0];
  if (!profile) return;

  const s = profile.settings ?? {};
  const n = s.notifications ?? {};

  // Appearance
  $('badgeDisplay').value    = s.badgeDisplay    ?? 'session';
  $('percentageMode').value  = s.percentageMode  ?? 'used';
  $('colorMode').value       = s.colorMode       ?? 'auto';

  // Notifications
  $('notifSession75').checked = n.session75 !== false;
  $('notifSession90').checked = n.session90 !== false;
  $('notifSession95').checked = n.session95 !== false;
  $('notifWeekly75').checked  = n.weekly75  !== false;
  $('notifWeekly90').checked  = n.weekly90  !== false;
  $('notifWeekly95').checked  = n.weekly95  !== false;

  // Refresh
  $('refreshInterval').value = String(s.refreshInterval ?? 1);
}

async function saveActiveSettings(partial) {
  const profiles = await getProfiles();
  const activeId = await getActiveProfileId();
  const profile  = profiles.find(p => p.id === activeId) ?? profiles[0];
  if (!profile) return;

  const current = profile.settings ?? {};
  await updateProfile(profile.id, {
    settings: { ...current, ...partial },
  });
}

$('saveAppearanceBtn').addEventListener('click', async () => {
  await saveActiveSettings({
    badgeDisplay:   $('badgeDisplay').value,
    percentageMode: $('percentageMode').value,
    colorMode:      $('colorMode').value,
  });
  chrome.runtime.sendMessage({ type: 'REFRESH' });
  showToast('Appearance saved.');
});

$('saveNotificationsBtn').addEventListener('click', async () => {
  await saveActiveSettings({
    notifications: {
      session75: $('notifSession75').checked,
      session90: $('notifSession90').checked,
      session95: $('notifSession95').checked,
      weekly75:  $('notifWeekly75').checked,
      weekly90:  $('notifWeekly90').checked,
      weekly95:  $('notifWeekly95').checked,
    },
  });
  showToast('Notification preferences saved.');
});

$('saveRefreshBtn').addEventListener('click', async () => {
  await saveActiveSettings({ refreshInterval: Number($('refreshInterval').value) });
  chrome.runtime.sendMessage({ type: 'RESCHEDULE_ALARM' });
  showToast('Refresh interval saved.');
});

// ── About version ──────────────────────────────────────────────────────────

const manifest = chrome.runtime.getManifest();
$('aboutVersion').textContent = `v${manifest.version}`;

// ── Init ───────────────────────────────────────────────────────────────────

renderProfiles();
