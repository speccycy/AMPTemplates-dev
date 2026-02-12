# Quick Reference - Double-Trigger Bug

## 🔴 THE PROBLEM

```
Scheduled Task "Every 4 Hours" triggers TWICE:

05:00:00 UTC (12:00 Thailand) → First trigger  ✅ Works
05:01:00 UTC (12:01 Thailand) → Second trigger ❌ Kills server, no restart

Result: Server offline until manual start
```

---

## 🎯 THE FIX (5 Minutes)

### Check AMP Scheduled Tasks

```
AMP Panel → Scheduled Tasks → "Every 4 Hours"
```

**Look for:**
- [ ] Two tasks with same schedule? → Delete one
- [ ] Interval = "1 minute"? → Change to "4 hours"
- [ ] "Repeat" enabled? → Disable it

---

## 📊 EVIDENCE

### 2026-01-14 Timeline
```
05:00:00 - First trigger  → Update → Server starts ✅
05:01:00 - Second trigger → Update → NO START ❌
12:27:23 - Manual start by user
Downtime: 7 hours 26 minutes
```

### 2026-01-15 Timeline
```
05:00:00 - First trigger  → Update → Server starts ✅
05:01:00 - Second trigger → Update → NO START ❌
05:27:23 - Manual start by user "no-admin"
Downtime: 26 minutes
```

**Pattern**: Exact same bug, 60 seconds apart, every day

---

## ✅ VERIFICATION

After fixing, next scheduled run should show:

```
✅ GOOD:
05:00:00 - Task triggered
05:00:51 - Update complete, server starting
05:01:30 - Server online
[No second trigger]

❌ BAD:
05:00:00 - Task triggered
05:01:00 - Task triggered AGAIN ← Still broken!
```

---

## 🛡️ TEMPLATE SAFEGUARDS (Optional)

If you want extra protection, implement these in SCUMWrapper.ps1:

1. **Execution Lock** - Blocks duplicate wrapper instances
2. **Interval Check** - Blocks if last run < 30 minutes ago
3. **Auto-Start Verify** - Ensures server starts after update

See: `TEMPLATE_SAFEGUARD_IMPLEMENTATION.md`

---

## 📄 FULL DOCUMENTATION

- **DOUBLE_TRIGGER_BUG_ANALYSIS.md** - Complete analysis
- **TEMPLATE_SAFEGUARD_IMPLEMENTATION.md** - Code implementation
- **ACTION_ITEMS_2026-01-15.md** - Detailed action plan

---

## 🔍 ROOT CAUSE

**NOT a template bug** ✅  
Template (SCUMWrapper + SCUMWatchdog) working correctly

**AMP configuration issue** ❌  
Scheduled task misconfigured or duplicated

---

## ⏱️ TIMELINE TO FIX

- **Check tasks**: 2 minutes
- **Fix configuration**: 2 minutes
- **Test**: 5 minutes
- **Total**: ~10 minutes

---

**Priority**: URGENT  
**Impact**: Every scheduled restart  
**Difficulty**: Easy (configuration fix)
