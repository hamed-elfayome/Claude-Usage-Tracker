// background.js — Service worker for Claude Usage Tracker
// Handles: alarms, polling, badge updates, notifications

import {
  initStorage,
  getActiveProfile,
  getProfiles,
  setActiveProfileId,
  updateProfile,
  updateCachedUsage,
} from './storage.js';

import { fetchUsageForProfile, getSessionKeyFromCookies, ApiError } from './api.js';

const ALARM_NAME = 'usage-refresh';

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

chrome.runtime.onInstalled.addListener(async () => {
  await initStorage();
  await scheduleAlarm();
  await refreshUsage();
});

chrome.runtime.onStartup.addListener(async () => {
  await scheduleAlarm();
  await refreshUsage();
});

// ---------------------------------------------------------------------------
// Alarm
// ---------------------------------------------------------------------------

async function scheduleAlarm() {
  const profile = await getActiveProfile();
  const intervalMinutes = profile?.settings?.refreshInterval ?? 1;

  await chrome.alarms.clear(ALARM_NAME);
  chrome.alarms.create(ALARM_NAME, { periodInMinutes: Math.max(1, intervalMinutes) });
}

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === ALARM_NAME) await refreshUsage();
});

// ---------------------------------------------------------------------------
// Core refresh
// ---------------------------------------------------------------------------

async function refreshUsage() {
  const profile = await getActiveProfile();
  if (!profile) {
    setBadgeError('?');
    return;
  }

  // Priority: profile stored key → auto-detected cookie
  const sessionKey = profile.sessionKey ?? await getSessionKeyFromCookies();
  if (!sessionKey) {
    setBadgeError('–');
    return;
  }

  try {
    const { usage, orgId } = await fetchUsageForProfile(profile, sessionKey);

    // Persist discovered org ID
    if (orgId !== profile.organizationId) {
      await updateProfile(profile.id, { organizationId: orgId });
    }

    await updateCachedUsage(profile.id, usage);
    updateBadge(usage, profile.settings);
    await fireNotifications(profile, usage);

  } catch (err) {
    console.error('[Claude Usage] refresh failed:', err.message);
    if (err instanceof ApiError && err.code === 'UNAUTHORIZED') {
      setBadgeError('!');
    } else {
      setBadgeError('?');
    }
  }
}

// ---------------------------------------------------------------------------
// Badge
// ---------------------------------------------------------------------------

function getBadgeColor(pct) {
  if (pct >= 90) return '#ef4444';
  if (pct >= 75) return '#f59e0b';
  return '#22c55e';
}

function setBadgeError(text) {
  chrome.action.setBadgeText({ text });
  chrome.action.setBadgeBackgroundColor({ color: '#6b7280' });
}

function updateBadge(usage, settings = {}) {
  const display = settings.badgeDisplay ?? 'session';
  const mode    = settings.percentageMode ?? 'used';

  if (display === 'off') {
    chrome.action.setBadgeText({ text: '' });
    return;
  }

  const rawPct = display === 'weekly' ? usage.weekly.percentage : usage.session.percentage;
  const pct    = mode === 'remaining' ? Math.max(0, 100 - rawPct) : rawPct;

  chrome.action.setBadgeText({ text: `${Math.round(pct)}%` });
  chrome.action.setBadgeBackgroundColor({ color: getBadgeColor(rawPct) });
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

async function fireNotifications(profile, usage) {
  const notif   = profile.settings?.notifications ?? {};
  const fired   = profile.firedThresholds ?? { session: [], weekly: [] };
  let changed   = false;

  for (const threshold of [75, 90, 95]) {
    // Session
    if (notif[`session${threshold}`] !== false) {
      if (usage.session.percentage >= threshold && !fired.session.includes(threshold)) {
        chrome.notifications.create(`session-${threshold}-${Date.now()}`, {
          type: 'basic',
          iconUrl: 'icons/icon48.png',
          title: 'Claude Session Usage Alert',
          message: `Session usage has reached ${threshold}%.`,
        });
        fired.session = [...fired.session, threshold];
        changed = true;
      }
    }

    // Weekly
    if (notif[`weekly${threshold}`] !== false) {
      if (usage.weekly.percentage >= threshold && !fired.weekly.includes(threshold)) {
        chrome.notifications.create(`weekly-${threshold}-${Date.now()}`, {
          type: 'basic',
          iconUrl: 'icons/icon48.png',
          title: 'Claude Weekly Usage Alert',
          message: `Weekly usage has reached ${threshold}%.`,
        });
        fired.weekly = [...fired.weekly, threshold];
        changed = true;
      }
    }
  }

  // Reset fired thresholds when usage drops back below 75 (new window/week)
  if (usage.session.percentage < 74 && fired.session.length > 0) {
    fired.session = [];
    changed = true;
  }
  if (usage.weekly.percentage < 74 && fired.weekly.length > 0) {
    fired.weekly = [];
    changed = true;
  }

  if (changed) await updateProfile(profile.id, { firedThresholds: fired });
}

// ---------------------------------------------------------------------------
// Message handler (popup & settings communicate via messages)
// ---------------------------------------------------------------------------

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  switch (msg.type) {
    case 'REFRESH':
      refreshUsage().then(() => sendResponse({ ok: true })).catch(() => sendResponse({ ok: false }));
      return true; // async

    case 'SWITCH_PROFILE':
      setActiveProfileId(msg.profileId)
        .then(() => scheduleAlarm())
        .then(() => refreshUsage())
        .then(() => sendResponse({ ok: true }))
        .catch(() => sendResponse({ ok: false }));
      return true;

    case 'RESCHEDULE_ALARM':
      scheduleAlarm().then(() => sendResponse({ ok: true }));
      return true;
  }
});
