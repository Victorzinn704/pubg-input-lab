#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ..\lib\LabProfileTools.ahk

try {
    workflowAssertions := RunWorkflowTests()
    FileAppend("PASS: " workflowAssertions " workflow assertions; no hooks or input.`n", "*")
    ExitApp(0)
} catch as workflowError {
    FileAppend("FAIL: " workflowError.Message " | line " workflowError.Line "`n" workflowError.Stack "`n", "**")
    ExitApp(1)
}

RunWorkflowTests() {
    count := 0
    limits := {MaxBurstMs: 6000, SessionLimitMs: 10000, MaxLateMs: 100, MaxStep: 12}
    profile := LabNewPreset("User_Timeline")
    profile.Weapon := "M416"
    profile.MotionMode := "timeline"
    profile.Segments := [{UntilMs: 500, Dx: 0.4, Dy: 2}, {UntilMs: 2000, Dx: -0.2, Dy: 3}]
    ; Same integrated curve under regular, coarse and jittered timestamps.
    for pattern in [[10], [20], [7, 23, 11, 29], [31, 17, 12]] {
        engine := RecoilEngine(profile, limits)
        engine.Arm(0)
        engine.Tick(0, true, false, true)
        initial := engine.Tick(1, true, true, true)
        WorkflowCheck(initial.Length = 1 && initial[1].Kind = "burst_start", "No initial jump", &count)
        now := 1
        dx := 0
        dy := 0
        cursor := 1
        while now < 1001 {
            now := Min(1001, now + pattern[cursor])
            cursor := Mod(cursor, pattern.Length) + 1
            for event in engine.Tick(now, true, true, true) {
                if event.Kind != "move"
                    throw Error("Unexpected stop in bounded timeline")
                dx += event.Dx
                dy += event.Dy
                WorkflowCheck(Abs(event.Dx) <= 12 && Abs(event.Dy) <= 12, "Bounded output", &count)
            }
        }
        WorkflowCheck(Abs(dx - 5) < 1.001 && Abs(dy - 125) < 1.001, "Rate and segment area survive jitter", &count)
        previousGeneration := engine.Generation
        engine.Tick(1002, false, true, true)
        WorkflowCheck(engine.State = "paused_focus" && engine.Generation > previousGeneration, "Focus invalidates timeline", &count)
        engine.Tick(1003, true, true, true)
        WorkflowCheck(engine.State = "wait_release", "Focus restore waits release", &count)
    }
    ; Fractional residue survives at the per-call integer limit.
    profile.Segments := [{UntilMs: 2000, Dx: 0, Dy: 6.4}]
    engine := RecoilEngine(profile, limits)
    engine.Arm(0), engine.Tick(0, true, false, true), engine.Tick(1, true, true, true)
    first := engine.Tick(41, true, true, true)
    WorkflowCheck(first[1].Dy = 12, "Fractional boundary emits bounded integer", &count)
    second := engine.Tick(51, true, true, true)
    WorkflowCheck(second[1].Dy = 4, "Fractional remainder is preserved", &count)
    oversized := engine.Tick(101, true, true, true)
    WorkflowCheck(oversized.Length = 1 && oversized[1].Reason = "rate_limit" && engine.State = "wait_release", "Oversized sample stops without burst catch-up", &count)
    WorkflowCheck(engine.Tick(102, true, true, true).Length = 0, "No queued move after stop", &count)
    engine.Tick(103, true, false, true), engine.Tick(104, true, true, true)
    late := engine.Tick(240, true, true, true)
    WorkflowCheck(late[1].Reason = "scheduler_late", "Long gap rejected", &count)
    engine.Disarm("test", 241)
    WorkflowCheck(engine.Tick(242, true, true, true).Length = 0, "Disabled timeline never emits", &count)

    converted := LabFromShotTable(profile, "2,0,8`n5,2,12", 80, 12)
    WorkflowCheck(converted.MotionMode = "timeline" && converted.Segments[2].UntilMs = 400, "Shot table mode and duration", &count)
    WorkflowCheck(converted.Segments[1].Dy = 2 && converted.Segments[2].Dx = 0.5, "Shot units converted to rate", &count)
    area := converted.Segments[1].Dy * 160 / 20 + converted.Segments[2].Dy * 240 / 20
    WorkflowCheck(area = 2 * 8 + 3 * 12, "Shot table preserves total movement", &count)
    for bad in ["", "2,0,8`n1,0,4", "2,0,1000", "200,0,1", "2,0,NaN", "2,0,1,2"]
        WorkflowReject((*) => LabFromShotTable(profile, bad, 80, 12), "Invalid shot table", &count)
    roundtrip := LabParseLibrary(LabSerializeLibrary([converted], 12), 12)
    WorkflowCheck(roundtrip[1].MotionMode = "timeline", "Timeline library roundtrip", &count)
    converted.TriggerMode := "single"
    WorkflowReject((*) => LabValidatePreset(converted, 12), "Single shot cannot use timeline", &count)

    base := LabClonePreset(profile)
    base.Name := "M416"
    base.Segments := [{UntilMs: 3000, Dx: 0, Dy: 0}]
    alternate := LabClonePreset(profile)
    alternate.Name := "User_M4"
    alternate.Weapon := "M4"
    alternate.Label := "M416 SCHOOL (FDCaffeine)"
    alternate.Optic := "6x"
    alternate.Stance := "Agachado"
    other := LabClonePreset(alternate)
    other.Name := "User_Beryl"
    other.Weapon := "Beryl"
    single := LabClonePreset(alternate)
    single.Name := "User_Single"
    single.TriggerMode := "single"
    smallSingle := LabClonePreset(single)
    smallSingle.Segments := [{UntilMs: 3000, Dx: 0, Dy: 1}]
    smallSingle.SavedGain := 0.1
    WorkflowCheck(!LabProfileHasOutput(smallSingle), "Quantized zero single profile is not ready", &count)
    profiles := [base, alternate, other, single]
    selection := LabEmptySelection()
    WorkflowCheck(LabResolveWeaponProfile(profiles, 1, selection) = 2, "Empty base falls back to matching moving variant", &count)
    selection.LastProfile := alternate.Name
    selection.Preferred[LabProfileGroup(base)] := other.Name
    WorkflowCheck(LabResolveWeaponProfile(profiles, 1, selection) = 2, "Wrong-weapon preference ignored", &count)
    selection.Preferred[LabProfileGroup(base)] := single.Name
    WorkflowCheck(LabResolveWeaponProfile(profiles, 1, selection) = 2, "Wrong-mode preference ignored", &count)
    selection.Preferred[LabProfileGroup(base)] := alternate.Name
    WorkflowCheck(LabResolveWeaponProfile(profiles, 2, selection) = 2, "Explicit library binding stays exact", &count)
    WorkflowCheck(LabResolveWeaponProfile([base], 1, selection) = 1, "Missing variant remains explicit", &count)
    WorkflowCheck(LabCycleReadyProfile(profiles, 2, 1) = 2 && LabCycleReadyProfile(profiles, 1, -1) = 2, "Real cycling skips empty and other mode", &count)
    restored := LabParseSelection(LabSelectionText(selection))
    WorkflowCheck(restored.LastProfile = alternate.Name && restored.Preferred[LabProfileGroup(base)] = alternate.Name, "Selection roundtrip", &count)
    for bad in ["", "[Selection]`nSchemaVersion=2`nLastProfile=M416`n[Preferred]", "[Selection]`nSchemaVersion=1`nLastProfile=[bad]`n[Preferred]"]
        WorkflowReject((*) => LabParseSelection(bad), "Malformed selection rejected", &count)
    selected := LabProfileSearch(profiles, "m416 6x agachado")
    WorkflowCheck(selected.Length = 3, "Search combines context words", &count)
    WorkflowCheck(LabProfileSearch(profiles, "not-a-weapon").Length = 0, "Empty search result", &count)
    alternate.Source := "SCHOOL@4c2d56a; assumed_ms=16; scale=0.1"
    summary := LabProfileSummary(alternate, 1, 6000)
    WorkflowCheck(InStr(summary, "10%") && InStr(summary, "Sensibilidade ainda"), "Summary exposes conversion and missing context", &count)
    path := A_ScriptDir "\artifacts\selection-test-" LabQpcTicks() ".ini"
    DirCreate(A_ScriptDir "\artifacts")
    try {
        LabWriteTextAtomic(path, LabSelectionText(selection), LabParseSelection)
        WorkflowCheck(LabParseSelection(FileRead(path)).LastProfile = alternate.Name, "Atomic preference persistence", &count)
    } finally {
        if FileExist(path)
            FileDelete(path)
    }
    return count
}

WorkflowCheck(condition, label, &count) {
    count += 1
    if !condition
        throw Error(label)
}

WorkflowReject(callback, label, &count) {
    rejected := false
    try callback.Call()
    catch Error
        rejected := true
    WorkflowCheck(rejected, label, &count)
}
