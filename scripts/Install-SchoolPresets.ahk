#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ..\lib\LabPresets.ahk
#Include ..\lib\LabInstance.ahk

try {
    if A_Args.Length != 1 || (A_Args[1] != "--install" && A_Args[1] != "--generate-example")
        throw Error("Use --install ou --generate-example.")
    schoolRoot := A_ScriptDir "\.."
    schoolInstallMode := A_Args[1] = "--install"
    if schoolInstallMode {
        schoolLock := LabClaimInstance("Local\RecoilLab.Instance.v1", false)
        if !schoolLock
            throw Error("Feche o Recoil Lab antes de instalar os presets.")
    }
    schoolLimit := schoolInstallMode ? ReadLabConfig(schoolRoot "\profiles.ini").MaxStep : 12
    schoolPack := LabSchoolPresetPack(LabReadSchool(schoolRoot "\references\school\school_presets.ini"), schoolLimit)
    schoolDestination := schoolRoot (schoolInstallMode ? "\presets.local.ini" : "\presets.example.ini")
    schoolExisting := schoolInstallMode ? LabReadLibrary(schoolDestination, schoolLimit) : []
    schoolCombined := LabAddMissingPresets(schoolExisting, schoolPack, schoolLimit)
    if !FileExist(schoolDestination) || schoolCombined.Length != schoolExisting.Length
        LabWriteLibrary(schoolDestination, schoolCombined, schoolLimit)
    FileAppend("PASS: " (schoolCombined.Length - schoolExisting.Length) " SCHOOL presets added; " schoolExisting.Length " existing presets preserved; no hooks or input.`n", "*")
    ExitApp(0)
} catch as schoolInstallError {
    FileAppend("FAIL: " schoolInstallError.Message "`n", "**")
    ExitApp(1)
}
