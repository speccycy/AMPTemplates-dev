# Action Items - SCUM Double-Trigger Bug Fix

**Date**: 2026-01-15  
**Issue**: Scheduled task triggering twice, causing server downtime  
**Status**: Root cause identified, solutions ready

---

## 🔴 CRITICAL FINDINGS

### The Bug
Your AMP Scheduled Task "Every 4 Hours" is executing **TWICE**:
- **First trigger** at XX:00:00 → Works correctly ✅
- **Second trigger** at XX:01:00 → Kills server, fails to restart ❌

### Impact
- **2026-01-14**: 7.5 hours downtime (05:01 - 12:27 UTC / 12:01 - 19:27 Thailand)
- **2026-01-15**: 26 minutes downtime (05:01 - 05:27 UTC / 12:01 - 12:27 Thailand)
- Occurs at **every scheduled restart**

### Root Cause
**NOT a template bug** - SCUMWrapper and SCUMWatchdog are working correctly.

**AMP configuration issue** - Scheduled task is misconfigured or duplicated.

---

## 🎯 IMMEDIATE ACTIONS (User Side)

### Step 1: Check for Duplicate Tasks

1. Open AMP Admin Panel
2. Go to **Scheduled Tasks**
3. Look for task: **"Every 4 Hours"**
4. Task ID: `c51bece4-3d66-4519-a314-936bf6795cb7`

**Check for:**
- ❓ Are there TWO tasks with same schedule?
- ❓ Is task set to "Repeat every 1 minute"?
- ❓ Is task interval "4 hours" or "240 minutes"?

### Step 2: Fix Task Configuration

**Option A: Delete and Recreate**
1. Delete existing "Every 4 Hours" task
2. Create new task:
   - **Name**: SCUM Restart & Update
   - **Action**: Restart Server
   - **Schedule**: Every 4 hours
   - **Start Time**: 12:00 (Thailand time)
   - **Enable**: Update before restart ✓

**Option B: Edit Existing Task**
1. Edit "Every 4 Hours" task
2. Verify settings:
   - Interval: 4 hours (NOT 1 minute)
   - No "Repeat" option enabled
   - Only ONE task exists

### Step 3: Test Configuration

1. Set test task to trigger in 5 minutes
2. Monitor AMP logs during execution
3. Verify:
   - ✓ Only ONE trigger occurs
   - ✓ Server restarts successfully
   - ✓ No second trigger at +1 minute

---

## 🛡️ TEMPLATE SAFEGUARDS (Developer Side)

I've prepared template enhancements to prevent this issue even if AMP misconfiguration occurs.

### Safeguards to Implement

1. **Execution Lock** - Prevents multiple wrapper instances
2. **Minimum Interval Check** - Blocks execution if last run < 30 minutes ago
3. **Enhanced Orphan Cleanup** - Better detection and graceful shutdown
4. **Auto-Start Verification** - Ensures server starts after update
5. **State File Cleanup** - Proper cleanup on all exit paths

### Implementation Files

📄 **TEMPLATE_SAFEGUARD_IMPLEMENTATION.md** - Complete implementation guide with code

**Benefits:**
- Blocks duplicate execution automatically
- Prevents rapid re-execution (< 30 minutes)
- Verifies server starts after update
- Better orphan process handling

---

## 📊 ANALYSIS DOCUMENTS

I've created comprehensive analysis documents:

1. **DOUBLE_TRIGGER_BUG_ANALYSIS.md**
   - Detailed timeline comparison (2026-01-14 vs 2026-01-15)
   - Root cause analysis
   - Impact assessment
   - Recommended solutions

2. **TEMPLATE_SAFEGUARD_IMPLEMENTATION.md**
   - Complete code implementation
   - Integration points
   - Testing checklist
   - Expected behavior after implementation

3. **CORRECT_TIMELINE_ANALYSIS.md** (from 2026-01-14)
   - Original bug discovery
   - Detailed log analysis

---

## 🔍 WHAT TO CHECK IN AMP PANEL

### Scheduled Tasks Section

Look for these patterns:

❌ **Bad Configuration:**
```
Task: Every 4 Hours
Interval: 1 minute
Repeat: Yes
Window: 4 hours
```

✅ **Good Configuration:**
```
Task: Every 4 Hours
Interval: 4 hours
Repeat: No
Start Time: 12:00
```

### Task Execution Log

After next scheduled run, check for:

❌ **Bad Pattern (Double Trigger):**
```
2026-01-16 05:00:00 - Task started
2026-01-16 05:01:00 - Task started  ← DUPLICATE!
```

✅ **Good Pattern (Single Trigger):**
```
2026-01-16 05:00:00 - Task started
2026-01-16 05:01:30 - Task completed
[No second trigger]
```

---

## 📝 NEXT STEPS

### For User (Priority: URGENT)

1. ✅ **Check AMP Scheduled Tasks** (5 minutes)
   - Look for duplicates
   - Verify interval configuration
   - Delete/fix misconfigured task

2. ✅ **Test with Short Interval** (15 minutes)
   - Create test task (trigger in 5 minutes)
   - Monitor for duplicate execution
   - Verify single trigger only

3. ✅ **Monitor Next Scheduled Run** (4 hours)
   - Watch AMP logs at next scheduled time
   - Verify no duplicate trigger
   - Verify server auto-starts

### For Developer (Priority: HIGH)

1. ⏳ **Review Safeguard Implementation** (30 minutes)
   - Read TEMPLATE_SAFEGUARD_IMPLEMENTATION.md
   - Understand each safeguard mechanism
   - Plan integration into SCUMWrapper.ps1

2. ⏳ **Implement Safeguards** (2 hours)
   - Add execution lock
   - Add minimum interval check
   - Enhance orphan cleanup
   - Add auto-start verification

3. ⏳ **Test in Development** (1 hour)
   - Test single execution
   - Test duplicate blocking
   - Test rapid restart blocking
   - Test auto-start verification

4. ⏳ **Deploy to Production** (30 minutes)
   - Backup current wrapper
   - Deploy enhanced wrapper
   - Monitor first scheduled execution

---

## ⚠️ IMPORTANT NOTES

### Why Server Doesn't Auto-Start After Second Update

After the second update completes, AMP state changes to "Stopped" but no start command is issued.

**Possible reasons:**
1. AMP thinks task is still running
2. Internal update lock not cleared
3. Restart counter exceeded limit
4. Update flag not cleared properly

**Template safeguards will help by:**
- Blocking second execution entirely
- Verifying server starts after update
- Logging detailed state information

### Template is NOT the Problem

The SCUMWrapper and SCUMWatchdog are working correctly:
- ✅ Graceful shutdown working
- ✅ LogExit detection working
- ✅ Orphan cleanup working
- ✅ State detection working
- ✅ Watchdog monitoring working

The issue is **AMP configuration**, not template code.

---

## 📞 SUPPORT

If you need help:

1. **Check scheduled tasks first** - This is most likely the issue
2. **Share task configuration** - Screenshot of task settings
3. **Monitor next execution** - Watch for duplicate triggers
4. **Implement safeguards** - Prevents issue even if AMP misconfigured

---

## ✅ SUCCESS CRITERIA

After fix is applied, you should see:

- ✅ Only ONE task trigger per scheduled interval
- ✅ Server stops gracefully
- ✅ Update completes successfully
- ✅ Server auto-starts after update
- ✅ No manual intervention required
- ✅ No downtime beyond update duration (~1 minute)

---

**Status**: Awaiting user action on scheduled task configuration  
**Priority**: URGENT - Affects every scheduled restart  
**ETA**: Can be fixed in 5 minutes by checking/fixing scheduled task
