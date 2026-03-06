// storage.js — Profile & settings persistence for Claude Usage Tracker

const KEYS = {
  PROFILES: 'profiles',
  ACTIVE_ID: 'activeProfileId',
};

const DEFAULT_SETTINGS = {
  refreshInterval: 1,       // minutes (Chrome alarms minimum = 1 min)
  badgeDisplay: 'session',  // 'session' | 'weekly' | 'off'
  percentageMode: 'used',   // 'used' | 'remaining'
  colorMode: 'auto',        // 'auto' | 'light' | 'dark'
  notifications: {
    session75: true,
    session90: true,
    session95: true,
    weekly75: true,
    weekly90: true,
    weekly95: true,
  },
};

// Fun profile names (matching macOS app style)
const ADJECTIVES = [
  'Swift', 'Clever', 'Bright', 'Quick', 'Sharp',
  'Bold', 'Keen', 'Wise', 'Calm', 'Agile',
];
const NOUNS = [
  'Falcon', 'Lynx', 'Hawk', 'Wolf', 'Fox',
  'Owl', 'Bear', 'Raven', 'Tiger', 'Eagle',
];

export function generateProfileName() {
  const adj = ADJECTIVES[Math.floor(Math.random() * ADJECTIVES.length)];
  const noun = NOUNS[Math.floor(Math.random() * NOUNS.length)];
  return `${adj} ${noun}`;
}

// ---------------------------------------------------------------------------
// Low-level helpers
// ---------------------------------------------------------------------------

export async function getProfiles() {
  const { profiles = [] } = await chrome.storage.local.get(KEYS.PROFILES);
  return profiles;
}

async function saveProfiles(profiles) {
  await chrome.storage.local.set({ [KEYS.PROFILES]: profiles });
}

export async function getActiveProfileId() {
  const { activeProfileId = null } = await chrome.storage.local.get(KEYS.ACTIVE_ID);
  return activeProfileId;
}

export async function setActiveProfileId(id) {
  await chrome.storage.local.set({ [KEYS.ACTIVE_ID]: id });
}

// ---------------------------------------------------------------------------
// Profile CRUD
// ---------------------------------------------------------------------------

export async function getActiveProfile() {
  const [profiles, activeId] = await Promise.all([getProfiles(), getActiveProfileId()]);
  if (profiles.length === 0) return null;
  return profiles.find(p => p.id === activeId) ?? profiles[0];
}

export async function createProfile(name = null) {
  const profiles = await getProfiles();
  const profile = {
    id: crypto.randomUUID(),
    name: name ?? generateProfileName(),
    sessionKey: null,       // null = auto-read from cookie
    organizationId: null,   // null = auto-discover
    settings: structuredClone(DEFAULT_SETTINGS),
    firedThresholds: { session: [], weekly: [] },
    cachedUsage: null,
    lastUpdated: null,
  };
  profiles.push(profile);
  await saveProfiles(profiles);

  // First profile becomes active automatically
  const activeId = await getActiveProfileId();
  if (!activeId) await setActiveProfileId(profile.id);

  return profile;
}

export async function updateProfile(id, updates) {
  const profiles = await getProfiles();
  const idx = profiles.findIndex(p => p.id === id);
  if (idx === -1) return null;
  profiles[idx] = { ...profiles[idx], ...updates };
  await saveProfiles(profiles);
  return profiles[idx];
}

export async function deleteProfile(id) {
  let profiles = await getProfiles();
  profiles = profiles.filter(p => p.id !== id);
  await saveProfiles(profiles);

  const activeId = await getActiveProfileId();
  if (activeId === id) {
    await setActiveProfileId(profiles[0]?.id ?? null);
  }
}

export async function updateCachedUsage(profileId, usage) {
  const profiles = await getProfiles();
  const idx = profiles.findIndex(p => p.id === profileId);
  if (idx === -1) return;
  profiles[idx].cachedUsage = usage;
  profiles[idx].lastUpdated = new Date().toISOString();
  await saveProfiles(profiles);
}

// ---------------------------------------------------------------------------
// Init — ensure at least one profile exists
// ---------------------------------------------------------------------------

export async function initStorage() {
  const profiles = await getProfiles();
  if (profiles.length === 0) {
    await createProfile('Default');
  }
}
