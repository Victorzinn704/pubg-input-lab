#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
; Intentionally include only this module: its dependencies must be explicit.
#Include ..\lib\LabConfig.ahk
try {
    DirCreate(A_ScriptDir "\artifacts")
    testPath := A_ScriptDir "\artifacts\standalone-config-" A_TickCount ".ini"
    LabSaveCalibration(testPath, "M416", 0, 3, 1)
    if IniRead(testPath, "M416", "Dy") != "3"
        throw Error("Saved movement did not round-trip")
    if !RegExMatch(IniRead(testPath, "M416", "SavedUtc"), "^\d{4}-\d\d-\d\dT.*Z$")
        throw Error("Saved timestamp missing")
    if IniRead(testPath, "M416", "Status") != "user_set_unvalidated"
        throw Error("Saved status mismatch")
    FileAppend("PASS: standalone LabConfig saves calibration and timestamp; no hooks/input.`n", "*")
    ExitApp(0)
} catch as dependencyTestError {
    FileAppend("FAIL: " dependencyTestError.Message "`n", "**")
    ExitApp(1)
}
