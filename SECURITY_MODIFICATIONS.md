# Security Modifications

This document describes the security hardening modifications made to this fork of Claude Usage Tracker.

## ⚠️ Original Security Concerns

The original app had several critical security issues:

1. **App Sandbox Disabled** - Full system access without restrictions
2. **Unsigned Executable Memory** - Could execute dynamically generated code
3. **Disabled Library Validation** - Could load malicious libraries
4. **Automatic Updates** - Updates from GitHub without user verification
5. **Build Script Sandboxing Disabled** - Build scripts could execute anything

## ✅ Security Fixes Applied

### 1. App Sandbox Enabled

**Files Modified:**
- `Claude Usage/ClaudeUsageTracker.entitlements`
- `Claude Usage/Claude UsageRelease.entitlements`

**Changes:**
```xml
<!-- BEFORE -->
<key>com.apple.security.app-sandbox</key>
<false/>

<!-- AFTER -->
<key>com.apple.security.app-sandbox</key>
<true/>
```

**Impact:**
- App now runs in a secure sandbox
- Can only access files/resources explicitly granted permission
- Cannot access arbitrary system resources
- Protects your system from potential malicious behavior

### 2. Removed Dangerous Permissions

**Removed:**
- `com.apple.security.cs.allow-unsigned-executable-memory` - Blocked dynamic code execution
- `com.apple.security.cs.disable-library-validation` - Blocked unsigned library loading

**Added Safe Permissions:**
- `com.apple.security.files.user-selected.read-only` - Read files you explicitly select
- `com.apple.security.files.user-selected.read-write` - Write to files you explicitly allow

### 3. Disabled Automatic Updates

**File Modified:**
- `Claude Usage/Resources/Info.plist`

**Changes:**
```xml
<key>SUEnableAutomaticChecks</key>
<false/>
<key>SUAllowsAutomaticUpdates</key>
<false/>
```

**Impact:**
- App will no longer automatically download/install updates
- You must manually verify and install updates
- Protects against malicious update injection

## 🚨 Feature Limitations

Due to sandboxing, some features may have reduced functionality:

### 1. Claude Code CLI Integration (Partially Broken)

**What Doesn't Work:**
- Automatic sync of Claude Code credentials from system Keychain
- The app tries to execute `/usr/bin/security` command which is blocked in sandbox
- Reading another app's Keychain entries is not allowed

**What Still Works:**
- Manual session key configuration
- Core usage tracking functionality
- All other features

**Workaround:**
- Manually enter your Claude session key instead of syncing from CLI
- Extract session key from browser (see README.md Quick Start Guide)

### 2. File Access Requires User Permission

**Before:** App could read/write any file
**After:** App must request permission for each file/directory

**Impact:**
- First time accessing `~/.claude-session-key` - you'll see a file picker
- First time writing to `~/.claude/` directory - you'll need to grant permission
- This is a GOOD thing - you control what the app can access

## 🔒 Security Best Practices

### Before Building:

1. **Verify Source Code:**
   ```bash
   git remote -v  # Ensure you're on a trusted repository
   git log --oneline -10  # Check recent commits
   ```

2. **Review Changes:**
   ```bash
   git diff HEAD~1 HEAD  # Review latest changes
   ```

3. **Check Entitlements:**
   ```bash
   cat "Claude Usage/ClaudeUsageTracker.entitlements"
   ```
   Ensure `com.apple.security.app-sandbox` is `<true/>`

### After Building:

1. **Verify Sandbox:**
   ```bash
   codesign -d --entitlements - "path/to/Claude Usage.app"
   ```
   Look for `<key>com.apple.security.app-sandbox</key><true/>`

2. **Monitor Network Activity:**
   ```bash
   # Use Little Snitch or Lulu firewall to monitor network connections
   # App should ONLY connect to:
   # - claude.ai
   # - api.anthropic.com
   # - console.anthropic.com
   # - status.claude.com
   # - api.github.com (for contributors list)
   ```

3. **Check File Access:**
   - App should NOT access files without showing file picker
   - Watch for suspicious file system activity in Console.app

## 🛡️ What This Protects Against

### With These Changes:

✅ **Prevents:**
- Arbitrary file system access
- Executing malicious code in memory
- Loading malicious libraries
- Automatic malware installation via updates
- Accessing sensitive system resources
- Reading/writing files without permission

❌ **Does NOT Prevent:**
- Network communication (required for functionality)
- Keychain access to app's own credentials (required for functionality)
- Access to files you explicitly grant permission to

## 🔍 How to Verify Security

### 1. Check Sandbox Status:
```bash
codesign -d --entitlements :- "/Applications/Claude Usage.app" 2>&1 | grep sandbox
```
Should show: `<key>com.apple.security.app-sandbox</key><true/>`

### 2. Monitor System Logs:
```bash
log stream --predicate 'process == "Claude Usage"' --level debug
```
Watch for:
- Sandbox violations (should see denied attempts if something tries to break out)
- Network connections (should only be to legitimate Claude domains)

### 3. Check Process Info:
```bash
ps aux | grep "Claude Usage"
# Note the PID, then:
sudo fs_usage -f filesys [PID]
```
Watch what files the app tries to access.

## 📋 Testing Checklist

After building with these security modifications:

- [ ] App launches successfully
- [ ] Can manually configure session key
- [ ] Usage data displays correctly
- [ ] Network requests work (to claude.ai)
- [ ] Menu bar icon shows usage
- [ ] Settings can be modified
- [ ] No unexpected permission requests
- [ ] No network connections to suspicious domains
- [ ] Console.app shows no sandbox violations

## ⚠️ Known Issues

### Issue: "Operation not permitted" errors in logs

**Cause:** Sandboxed app trying to access restricted resources

**Solution:** This is expected and GOOD. The sandbox is working correctly.

### Issue: CLI sync feature doesn't work

**Cause:** Cannot access Claude Code's Keychain entries from sandbox

**Solution:** Use manual session key configuration instead

### Issue: File picker appears for ~/.claude-session-key

**Cause:** Sandboxed apps must request explicit permission for file access

**Solution:** This is expected. Select the file to grant permission.

## 🔄 Updating the App

Since automatic updates are disabled:

1. **Check for Updates Manually:**
   ```bash
   # Check GitHub releases
   curl -s https://api.github.com/repos/hamed-elfayome/Claude-Usage-Tracker/releases/latest | grep tag_name
   ```

2. **Review Changes:**
   - Read the CHANGELOG.md
   - Review the diff on GitHub
   - Check for security-related changes

3. **Build from Source:**
   - Pull latest code
   - Review security modifications are still in place
   - Build and test before deploying

## 📞 Questions?

If you have questions about these security modifications:

1. Review the code changes in entitlements files
2. Check Apple's App Sandbox documentation
3. Test in a VM or separate user account first

## ⚖️ License

These modifications are provided as-is for security hardening purposes. The original app is licensed under MIT License by hamed-elfayome.

---

**Last Updated:** 2026-01-23
**Modified By:** Security Hardening Review
**Original Repository:** https://github.com/hamed-elfayome/Claude-Usage-Tracker
