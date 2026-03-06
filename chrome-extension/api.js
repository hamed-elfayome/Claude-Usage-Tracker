// api.js — Claude.ai API integration for Claude Usage Tracker

const API_BASE = 'https://claude.ai/api';

// ---------------------------------------------------------------------------
// Cookie auto-detection (zero-config)
// ---------------------------------------------------------------------------

export async function getSessionKeyFromCookies() {
  try {
    const cookie = await chrome.cookies.get({ url: 'https://claude.ai', name: 'sessionKey' });
    return cookie?.value ?? null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Organization discovery
// ---------------------------------------------------------------------------

export async function fetchOrganizations(sessionKey) {
  const res = await apiFetch(`${API_BASE}/organizations`, sessionKey);
  const orgs = await res.json();
  if (!Array.isArray(orgs) || orgs.length === 0) throw new ApiError('NO_ORGANIZATIONS');
  return orgs; // [{ uuid, name, capabilities }]
}

// ---------------------------------------------------------------------------
// Usage data
// ---------------------------------------------------------------------------

export async function fetchUsage(sessionKey, orgId) {
  const res = await apiFetch(`${API_BASE}/organizations/${orgId}/usage`, sessionKey);
  const data = await res.json();
  return parseUsage(data);
}

// Fetch usage for a profile, auto-discovering org ID if needed.
// Returns { usage, orgId } — orgId may differ from profile.organizationId if re-discovered.
export async function fetchUsageForProfile(profile, sessionKey) {
  let orgId = profile.organizationId;

  if (!orgId) {
    const orgs = await fetchOrganizations(sessionKey);
    orgId = orgs[0].uuid;
  }

  try {
    const usage = await fetchUsage(sessionKey, orgId);
    return { usage, orgId };
  } catch (err) {
    // Org ID stale (403/404) → re-discover once
    if (err instanceof ApiError && (err.code === 'HTTP_403' || err.code === 'HTTP_404')) {
      const orgs = await fetchOrganizations(sessionKey);
      orgId = orgs[0].uuid;
      const usage = await fetchUsage(sessionKey, orgId);
      return { usage, orgId };
    }
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

async function apiFetch(url, sessionKey) {
  let res;
  try {
    res = await fetch(url, {
      headers: {
        Cookie: `sessionKey=${sessionKey}`,
        Accept: 'application/json',
      },
    });
  } catch (err) {
    throw new ApiError('NETWORK_ERROR', err.message);
  }

  if (res.status === 401 || res.status === 403) throw new ApiError('UNAUTHORIZED');
  if (res.status === 404) throw new ApiError('HTTP_404');
  if (res.status === 429) throw new ApiError('RATE_LIMITED');
  if (!res.ok) throw new ApiError(`HTTP_${res.status}`);

  return res;
}

function parseUtilization(v) {
  if (typeof v === 'number') return v;
  if (typeof v === 'string') {
    const n = parseFloat(v.replace('%', '').trim());
    return isNaN(n) ? 0 : n;
  }
  return 0;
}

function parseUsage(data) {
  const session = { percentage: 0, resetAt: null };
  const weekly  = { percentage: 0, resetAt: null };
  const opus    = { percentage: 0, resetAt: null };
  const sonnet  = { percentage: 0, resetAt: null };

  if (data.five_hour) {
    session.percentage = parseUtilization(data.five_hour.utilization ?? data.five_hour.utilization_pct ?? 0);
    session.resetAt    = data.five_hour.resets_at ?? null;
  }
  if (data.seven_day) {
    weekly.percentage = parseUtilization(data.seven_day.utilization ?? data.seven_day.utilization_pct ?? 0);
    weekly.resetAt    = data.seven_day.resets_at ?? null;
  }
  if (data.seven_day_opus) {
    opus.percentage = parseUtilization(data.seven_day_opus.utilization ?? data.seven_day_opus.utilization_pct ?? 0);
    opus.resetAt    = data.seven_day_opus.resets_at ?? null;
  }
  if (data.seven_day_sonnet) {
    sonnet.percentage = parseUtilization(data.seven_day_sonnet.utilization ?? data.seven_day_sonnet.utilization_pct ?? 0);
    sonnet.resetAt    = data.seven_day_sonnet.resets_at ?? null;
  }

  return {
    session,
    weekly,
    opus,
    sonnet,
    hasOpus: !!data.seven_day_opus,
    hasSonnet: !!data.seven_day_sonnet,
  };
}

// ---------------------------------------------------------------------------
// Custom error class
// ---------------------------------------------------------------------------

export class ApiError extends Error {
  constructor(code, detail = '') {
    super(`ApiError: ${code}${detail ? ` — ${detail}` : ''}`);
    this.code = code;
  }
}
