# ✅ FIX APPLIED - 2026-01-15

## 🎯 ปัญหาที่พบ

**ปัญหาหลัก:** หลังจาก AMP ทำ "Update and Restart" เสร็จ เซิร์ฟเวอร์กำลัง Starting แต่ถูกสั่ง Shutdown อีกครั้ง

**สาเหตุ:**
1. **App.ExitFile=app_exit.lck** ใน scum.kvp ทำให้เกิด race condition
2. **server_ready.flag** ถูกสร้างเร็วเกินไป (ก่อน server พร้อม)

---

## 🔧 การแก้ไขที่ทำ

### Fix 1: ลบ App.ExitFile ออก

**ไฟล์:** `AMPTemplates-dev/scum.kvp`

**เปลี่ยนจาก:**
```kvp
App.ExitFile=app_exit.lck
```

**เป็น:**
```kvp
App.ExitFile=
```

**เหตุผล:**
- Generic module ไม่รองรับ App.ExitFile อย่างถูกต้อง
- File นี้อาจถูกสร้างผิดเวลา หรือไม่ถูกลบ
- ทำให้เกิด race condition ที่ trigger shutdown ผิดเวลา
- Template ใช้ `App.ExitMethod=OS_CLOSE` + Watchdog อยู่แล้ว ไม่ต้องใช้ ExitFile

---

### Fix 2: แก้ server_ready.flag Timing

**ไฟล์:** `AMPTemplates-dev/SCUM/Binaries/Win64/SCUMWrapper.ps1`

**เปลี่ยนจาก:**
```powershell
Write-WrapperLog "State: RUNNING - Monitoring process..."
New-Item $serverReadyFlag -Force | Out-Null
```

**เป็น:**
```powershell
Write-WrapperLog "State: RUNNING - Waiting for server to be ready..."

# รอให้ server โหลดเสร็จ (ตรวจจาก SCUM.log pattern "LogSCUM: Global Stats")
$maxWaitTime = 300 # 5 minutes
$startTime = Get-Date
$serverReady = $false

while (((Get-Date) - $startTime).TotalSeconds -lt $maxWaitTime) {
    # Check if server process is still alive
    if ($process.HasExited) {
        Write-WrapperLog "Server process died during startup!" "ERROR"
        break
    }
    
    # Check SCUM.log for ready pattern
    $logContent = Get-Content $global:ServerLogPath -Tail 50 -ErrorAction SilentlyContinue
    if ($logContent -match "LogSCUM: Global Stats") {
        Write-WrapperLog "✓ Server is READY (detected Global Stats log)"
        $serverReady = $true
        break
    }
    
    Start-Sleep -Seconds 2
}

# สร้าง flag เฉพาะเมื่อ server พร้อมจริงๆ
if ($serverReady) {
    New-Item $serverReadyFlag -Force | Out-Null
    Write-WrapperLog "✓ Server ready flag created"
}
else {
    Write-WrapperLog "Server did not reach ready state within ${maxWaitTime}s" "WARNING"
    Write-WrapperLog "Flag NOT created - watchdog will FORCE KILL if wrapper dies" "WARNING"
}

# ตอนนี้ค่อย output AMP ready pattern
Write-WrapperLog "State: RUNNING - Monitoring process..."
```

**เหตุผล:**
- Wrapper เดิมสร้าง flag ทันทีที่เข้า monitoring loop
- แต่ server ยังโหลดไม่เสร็จ (อายุแค่ 8-10 วินาที)
- Watchdog เห็น flag → คิดว่า server พร้อม → graceful shutdown
- แต่ server ยังไม่พร้อมจริง → อาจทำให้ database corrupt

**หลังแก้:**
- Wrapper รอให้ server โหลดเสร็จก่อน (ตรวจจาก "LogSCUM: Global Stats")
- สร้าง flag เฉพาะเมื่อ server พร้อมจริงๆ
- Watchdog จะรู้ว่า server พร้อมหรือยัง:
  - **ไม่มี flag** = Server STARTING → Force kill ทันที
  - **มี flag** = Server READY → Graceful shutdown

---

## 📊 Expected Behavior หลังแก้

### Scenario 1: Normal Update & Restart

```
05:00:00 - Task "Update and Restart" triggered
05:00:00 - Stop server (graceful)
05:00:05 - Update starts
05:00:25 - Update complete
05:00:26 - Server starting (wrapper PID: 7812)
05:00:30 - Wrapper waiting for server ready...
05:01:30 - Server ready detected (Global Stats found)
05:01:30 - Flag created
05:01:30 - Wrapper outputs "State: RUNNING"
05:01:30 - AMP sees "Started" state
[ไม่มี shutdown อีกครั้ง!]
```

### Scenario 2: Abort ขณะ Starting (ก่อน server พร้อม)

```
User clicks "Abort"
  ↓
AMP kills wrapper
  ↓
Watchdog detects wrapper death
  ↓
Check for flag file → NOT FOUND
  ↓
DECISION: Server was STARTING
  ↓
FORCE KILL immediately (ถูกต้อง!)
```

### Scenario 3: Stop หลัง Server Ready

```
User clicks "Stop"
  ↓
AMP kills wrapper
  ↓
Watchdog detects wrapper death
  ↓
Check for flag file → FOUND
  ↓
DECISION: Server was READY
  ↓
Send Ctrl+C (graceful shutdown)
  ↓
Wait for LogExit (max 30s)
  ↓
Success!
```

---

## ✅ Verification Checklist

หลังแก้ไข ให้ตรวจสอบ:

### 1. Wrapper Logs ควรเห็น:

```
[INFO] State: RUNNING - Waiting for server to be ready...
[DEBUG] Waiting for server to reach ready state (max 300s)...
[DEBUG] Looking for pattern: 'LogSCUM: Global Stats' in SCUM.log
[INFO] ✓ Server is READY (detected Global Stats log after 45.2s)
[DEBUG] ✓ Server ready flag created
[INFO] State: RUNNING - Monitoring process...
```

### 2. Watchdog Logs ควรเห็น:

**ถ้า Abort ขณะ Starting:**
```
[WATCHDOG-DEBUG] Flag file NOT found
[WATCHDOG-WARNING] DECISION: Server was STARTING
[WATCHDOG-WARNING] Performing FORCE KILL
```

**ถ้า Stop หลัง Ready:**
```
[WATCHDOG-DEBUG] ✓ Server was READY (flag file exists)
[WATCHDOG-WARNING] DECISION: Server was READY
[WATCHDOG-WARNING] Attempting GRACEFUL SHUTDOWN...
[WATCHDOG-DEBUG] ✓ Ctrl+C sent successfully
[WATCHDOG-DEBUG] ✓ LogExit pattern detected
```

### 3. AMP Logs ควรเห็น:

```
[05:00:00] Task triggered
[05:00:25] Update complete
[05:00:26] Server starting
[05:01:30] Server online (State: RUNNING detected)
[ไม่มี shutdown อีกครั้ง!]
```

---

## 🎯 Benefits

### ก่อนแก้:
- ❌ Server ถูก shutdown หลัง update เสร็จ
- ❌ Flag ถูกสร้างเร็วเกินไป
- ❌ Watchdog ไม่รู้ว่า server พร้อมจริงหรือยัง
- ❌ อาจทำให้ database corrupt

### หลังแก้:
- ✅ Server ไม่ถูก shutdown หลัง update
- ✅ Flag ถูกสร้างเมื่อ server พร้อมจริงๆ
- ✅ Watchdog รู้ว่า server พร้อมหรือยัง
- ✅ ป้องกัน database corruption
- ✅ Abort ขณะ starting → Force kill (ถูกต้อง)
- ✅ Stop หลัง ready → Graceful shutdown (ถูกต้อง)

---

## 📝 Next Steps

1. **Commit changes** to AMPTemplates-dev
2. **Test** with scheduled update:
   - ตั้ง task ให้ trigger ใน 5 นาที
   - ดู logs ว่า server start สำเร็จ
   - ไม่มี shutdown อีกครั้ง
3. **Monitor** next scheduled run (12:00 Thailand)
4. **Verify** no more issues

---

## 🔍 Root Cause Summary

**ปัญหาจริงๆ คือ:**

1. **App.ExitFile=app_exit.lck** ทำให้เกิด race condition
   - AMP สร้าง file นี้เพื่อบอก wrapper ให้ shutdown
   - แต่ Generic module ไม่รองรับอย่างถูกต้อง
   - File อาจถูกสร้างผิดเวลา หรือไม่ถูกลบ
   - ทำให้ server ถูก shutdown หลัง update เสร็จ

2. **server_ready.flag timing** ไม่ถูกต้อง
   - Flag ถูกสร้างเร็วเกินไป (ก่อน server พร้อม)
   - Watchdog คิดว่า server พร้อมแล้ว
   - ส่ง graceful shutdown แทนที่จะ force kill
   - อาจทำให้ database corrupt

**ไม่ใช่ AMP Scheduler Bug!**
- Schedule ถูกต้อง (00:00, 12:00, 20:00)
- Task action ถูกต้อง (Update and Restart)
- ปัญหาอยู่ที่ template configuration

---

**Fix Applied Date**: 2026-01-15  
**Status**: Ready for testing  
**Priority**: HIGH - Test with next scheduled run
