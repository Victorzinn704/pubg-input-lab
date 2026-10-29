#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ..\lib\LabPresets.ahk
#Include ..\lib\LabCurvePreview.ahk
#Include ..\lib\LabHotkeys.ahk
#Include ..\lib\LabReticle.ahk

try {
    presetTestCount := RunPresetTests()
    FileAppend("PASS: " presetTestCount " preset assertions; no hooks or input.`n", "*")
    ExitApp(0)
} catch as presetTestError {
    FileAppend("FAIL: " presetTestError.Message " | line " presetTestError.Line "`n" presetTestError.Stack "`n", "**")
    ExitApp(1)
}

RunPresetTests() {
    DetectHiddenWindows(true)
    count := 0
    preset := LabNewPreset("User_Test")
    preset.Label := "M416 / João / 6x"
    preset.Segments := [{UntilMs: 500, Dx: 0.25, Dy: 1}, {UntilMs: 3000, Dx: -0.5, Dy: 2}]
    preset.SavedGain := 1.75
    serialized := LabSerializeLibrary([preset], 12)
    read := LabParseLibrary(serialized, 12)
    PresetAssert(read.Length = 1 && read[1].Label = preset.Label, "Unicode roundtrip", &count)
    PresetAssert(read[1].Segments.Length = 2 && read[1].Segments[2].Dx = -0.5, "Curve roundtrip", &count)
    PresetAssert(read[1].SavedGain = 1.75 && read[1].Sensitivity = "Nao registrada", "Context roundtrip", &count)
    clone := LabClonePreset(preset)
    clone.Segments[1].Dy := 4
    PresetAssert(preset.Segments[1].Dy = 1, "Deep clone isolation", &count)
    PresetAssert(LabParseLibrary(LabSerializeLibrary([], 12), 12).Length = 0, "Empty library", &count)
    for malformed in ["", StrReplace(serialized, "SchemaVersion=1", "SchemaVersion=2"),
        serialized "`n[Library]`nSchemaVersion=1", StrReplace(serialized, "SavedGain=1.75", "SavedGain=5`nSavedGain=1"),
        StrReplace(serialized, "[Preset:User_Test]", "[Preset:M416]"),
        StrReplace(serialized, "RecoilStatus=user_set_unvalidated", "RecoilStatus=validated"),
        StrReplace(serialized, "IntervalMs=20", "IntervalMs=-1"),
        StrReplace(serialized, "SavedGain=1.75", "SavedGain=7"),
        StrReplace(serialized, "3000,-0.5,2", "100,-0.5,2"),
        serialized "unknown=3`n"]
        PresetReject((*) => LabParseLibrary(malformed, 12), "Invalid library rejected", &count)
    invalid := LabClonePreset(preset)
    invalid.Label := "Injected`nSegments=1,0,0"
    PresetReject((*) => LabSerializeLibrary([invalid], 12), "INI injection", &count)
    invalid := LabClonePreset(preset)
    invalid.Segments[1].Dy := 10
    PresetReject((*) => LabSerializeLibrary([invalid], 12), "Effective max step", &count)
    PresetReject((*) => LabSerializeLibrary([preset, preset], 12), "Duplicate IDs", &count)
    PresetReject((*) => LabMergeLibrary([preset], [preset]), "Protected base collision", &count)
    imported := LabImportPresets([preset], [preset], 12)
    PresetAssert(imported.Length = 2 && imported[1].Name != imported[2].Name, "Import copies on collision", &count)
    PresetAssert(preset.Label = "M416 / João / 6x", "Import preserves original", &count)
    binding := LabParseHotkeys("[Weapons]`nUser_Test=1", [preset])
    PresetAssert(binding.Weapons[1].Chord = "^!1", "Additional numeric shortcut", &count)
    PresetReject((*) => LabParseHotkeys("[Weapons]`nUser_Test=0", [preset]), "Zero reserved to reticle", &count)
    path := A_ScriptDir "\artifacts\preset-" LabQpcTicks() ".ini"
    DirCreate(A_ScriptDir "\artifacts")
    try {
        LabWriteLibrary(path, [preset], 12)
        first := FileRead(path)
        changed := LabClonePreset(preset)
        changed.Label := "Renomeado"
        LabWriteLibrary(path, [changed], 12)
        PresetAssert(FileRead(path ".bak") = first, "Backup of previous revision", &count)
        before := FileRead(path)
        PresetReject((*) => LabWriteLibrary(path, [invalid], 12), "Invalid write rejected", &count)
        PresetAssert(FileRead(path) = before, "Invalid write preserves bytes", &count)
        PresetAssert(LabReadLibrary(path, 12)[1].Label = "Renomeado", "Persisted rename", &count)
        LabWriteLibrary(path, [], 12)
        PresetAssert(LabReadLibrary(path, 12).Length = 0, "Delete last custom preset", &count)
    } finally {
        if FileExist(path)
            FileDelete(path)
        if FileExist(path ".bak")
            FileDelete(path ".bak")
    }
    school := LabReadSchool(A_ScriptDir "\..\references\school\school_presets.ini")
    PresetAssert(school.Length = 26, "26 attributed reference weapons", &count)
    pack := LabSchoolPresetPack(school, 12)
    PresetAssert(pack.Length = 78, "26 weapons times 3 stances", &count)
    PresetAssert(LabSerializeLibrary(pack, 12) = LabSerializeLibrary(LabSchoolPresetPack(school, 12), 12), "Stable reference IDs and content", &count)
    shipped := LabReadLibrary(A_ScriptDir "\..\presets.example.ini", 12)
    expectedPack := LabParseLibrary(LabSerializeLibrary(pack, 12), 12)
    PresetAssert(LabSerializeLibrary(shipped, 12) = LabSerializeLibrary(expectedPack, 12), "Shipped pack matches pinned source conversion", &count)
    customPack := LabClonePreset(pack[1])
    customPack.SavedGain := 0.5
    seeded := LabAddMissingPresets([customPack], pack, 12)
    PresetAssert(seeded.Length = 78 && seeded[1].SavedGain = 0.5, "Seeding preserves edited reference", &count)
    repeated := LabAddMissingPresets(seeded, pack, 12)
    PresetAssert(LabSerializeLibrary(repeated, 12) = LabSerializeLibrary(seeded, 12), "Seeding is idempotent", &count)
    cfg := ReadLabConfig(A_ScriptDir "\..\profiles.ini")
    combined := LabMergeLibrary(cfg.Profiles, pack)
    for index, profile in combined {
        forward := LabCyclePresetIndex(combined, index, 1)
        backward := LabCyclePresetIndex(combined, forward, -1)
        PresetAssert(backward = index, "Forward/backward roundtrip", &count)
        PresetAssert(LabWeaponIdentity(combined[forward]) = LabWeaponIdentity(profile), "Cycling never changes weapon", &count)
        PresetAssert(combined[forward].TriggerMode = profile.TriggerMode, "Cycling never changes trigger mode", &count)
    }
    for name in ["M416", "BerylM762", "SCARL", "TommyGun", "Mk14_continuous"] {
        start := 0
        for index, profile in combined {
            if profile.Name = name
                start := index
        }
        current := start
        seen := Map()
        Loop 4 {
            seen[current] := true
            current := LabCyclePresetIndex(combined, current, 1)
        }
        PresetAssert(current = start && seen.Count = 4, "Base plus three stances for " name, &count)
    }
    PresetReject((*) => LabCyclePresetIndex(combined, 0, 1), "Invalid cycle index", &count)
    PresetReject((*) => LabCyclePresetIndex(combined, 1, 0), "Invalid cycle direction", &count)
    for profile in pack
        PresetAssert(InStr(profile.Label, "SCHOOL (FDCaffeine)"), "Visible author credit", &count)
    for entry in school {
        for stance in ["Em pe", "Agachado", "Deitado"] {
            converted := LabConvertSchool(entry, stance, 16, 0.1, 3000, 12)
            PresetAssert(converted.Stance = stance && converted.RecoilStatus = "external_unvalidated", "Explicit reference context", &count)
            PresetAssert(converted.Segments[-1].UntilMs = 3000 && converted.IntervalMs = 16, "Explicit timing", &count)
            PresetAssert(InStr(converted.Source, "scale=0.1") && InStr(converted.Source, "assumed_ms=16"), "Conversion provenance", &count)
            LabParseLibrary(LabSerializeLibrary([converted], 12), 12)
        }
    }
    sample := {Name: "Test", normal: 4, ctrl: 3, prone: 2, delay: 1, strength: 1000}
    curve := LabConvertSchool(sample, "Em pe", 20, 0.1, 60, 12)
    PresetAssert(curve.Segments[1].Dy = 0.5 && Abs(curve.Segments[3].Dy - 0.7) < 0.00001, "School ramp conversion", &count)
    PresetReject((*) => LabConvertSchool(sample, "Em pe", 20, 1, 3000, 12), "No silent clipping", &count)
    PresetReject((*) => LabConvertSchool(sample, "Em pe", 1, 0.1, 3000, 12), "Cannot claim 1ms timing", &count)
    PresetReject((*) => LabConvertSchool(sample, "Unknown", 20, 0.1, 3000, 12), "Unknown stance", &count)
    bitmap := LabCurveBitmap(preset)
    PresetAssert(bitmap != 0, "Native curve preview", &count)
    DllCall("gdi32\DeleteObject", "Ptr", bitmap)
    rect := LabReticleBounds(100, 200, 640, 480, 5)
    PresetAssert(rect.X = 417 && rect.Y = 437 && rect.W = 5, "Client-centered reticle", &count)
    PresetAssert(!LabReticleBounds(0, 0, 200, 100, 5), "Reticle hidden for transient small window", &count)
    dot := LabReticle()
    try {
        PresetAssert(!dot.Shown, "Reticle defaults hidden", &count)
        styles := WinGetExStyle("ahk_id " dot.Gui.Hwnd)
        PresetAssert((styles & 0x20) && (styles & 0x08000000), "Reticle click through and no activation", &count)
    } finally dot.Destroy()
    return count
}

PresetAssert(condition, message, &count) {
    count += 1
    if !condition
        throw Error(message)
}

PresetReject(callback, message, &count) {
    rejected := false
    try callback.Call()
    catch Error
        rejected := true
    PresetAssert(rejected, message, &count)
}
