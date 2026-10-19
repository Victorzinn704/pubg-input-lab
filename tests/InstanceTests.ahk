#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ..\lib\LabInstance.ahk

try {
    instanceTestCount := RunInstanceTests()
    FileAppend("PASS: " instanceTestCount " instance assertions; isolated mutex names, no hooks/input/notifications.`n", "*")
    ExitApp(0)
} catch as instanceTestError {
    FileAppend("FAIL: " instanceTestError.Message "`n", "**")
    ExitApp(1)
}

RunInstanceTests() {
    DllCall("kernel32\QueryPerformanceCounter", "Int64*", &ticks := 0)
    name := "Local\RecoilLab.InstanceTests." DllCall("kernel32\GetCurrentProcessId", "UInt") "." ticks
    held := 0
    unrelated := 0
    assertions := 0
    try {
        held := LabClaimInstance(name, false)
        InstanceAssert(held != 0, "First isolated claim must acquire a handle", &assertions)
        InstanceAssert(LabClaimInstance(name, false) = 0,
            "A second claim must return zero while the first handle is retained", &assertions)

        unrelated := LabClaimInstance(name ".other", false)
        InstanceAssert(unrelated != 0, "Different isolated names must not block one another", &assertions)
        InstanceAssert(DllCall("kernel32\CloseHandle", "Ptr", unrelated, "Int") != 0,
            "Independent handle must close successfully", &assertions)
        unrelated := 0

        InstanceAssert(DllCall("kernel32\CloseHandle", "Ptr", held, "Int") != 0,
            "First handle must close successfully", &assertions)
        held := 0
        held := LabClaimInstance(name, false)
        InstanceAssert(held != 0,
            "Third claim must succeed after close; duplicate claims must not leak handles", &assertions)
        InstanceAssert(LabClaimInstance(name, false) = 0,
            "The newly acquired handle must still exclude duplicates", &assertions)

        rejected := false
        try LabClaimInstance("", false)
        catch ValueError
            rejected := true
        InstanceAssert(rejected, "An empty name must not create an unguarded anonymous mutex", &assertions)

        rejected := false
        try LabClaimInstance(name "\invalid", false)
        catch Error
            rejected := true
        InstanceAssert(rejected, "A Win32 creation failure must be reported as an error", &assertions)
    } finally {
        if unrelated
            DllCall("kernel32\CloseHandle", "Ptr", unrelated)
        if held
            DllCall("kernel32\CloseHandle", "Ptr", held)
    }
    return assertions
}

InstanceAssert(condition, label, &assertions) {
    assertions += 1
    if !condition
        throw Error(label)
}
