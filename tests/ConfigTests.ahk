RunConfigTests(configPath) {
    count := 0
    cfg := ReadLabConfig(configPath)
    LabTestAssert(cfg.Profiles.Length = 19, "four examples and fifteen weapon profiles", &count)
    names := Map()
    for entry in cfg.Profiles
        names[entry.Name] := entry
    for expectedName in ["AKM", "BerylM762", "ACE32", "Groza", "M416", "AUG", "SCARL", "UMP", "MicroUZI", "TommyGun", "Mini14", "Mk12", "Mk14_single", "Mk14_continuous", "SKS"] {
        LabTestAssert(names.Has(expectedName), "weapon registered " expectedName, &count)
        entry := names[expectedName]
        LabTestAssert(entry.RecoilStatus = "unmeasured" && entry.Segments[1].Dx = 0 && entry.Segments[1].Dy = 0,
            "unknown recoil never fabricated " expectedName, &count)
        LabTestAssert(entry.FireIntervalMs > 0 && InStr(entry.Source, "https://pubg.gs/weapons/") = 1,
            "reference provenance " expectedName, &count)
    }
    LabTestAssert(names["Mk14_single"].TriggerMode = "single" && names["Mk14_continuous"].TriggerMode = "continuous", "separate Mk14 modes", &count)
    LabTestAssert(names["Mk12"].MinTriggerMs = 182, "DMR published cadence precision", &count)
    LabTestAssert(names["MicroUZI"].FireIntervalMs = 48, "UZI reference cadence", &count)
    LabTestAssert(cfg.TargetExe = "TslGame.exe", "default target", &count)
    LabTestAssert(cfg.Profiles[1].Segments[1].Dy = 0, "zero-input control", &count)
    profile := LabScaledProfile(cfg.Profiles[2], 2)
    LabTestAssert(profile.Segments[1].Dy = 2, "gain scaling", &count)
    LabTestAssert(cfg.Profiles[2].Segments[1].Dy = 1, "source profile immutable", &count)
    LabTestAssert(names["M416"].MotionMode = "elapsed", "M416 opts into elapsed smoothing", &count)
    LabTestAssert(names["BerylM762"].MotionMode = "step", "other weapons retain step mode", &count)
    LabTestAssert(LabScaledProfile(names["M416"], 1.5).MotionMode = "elapsed",
        "gain scaling preserves motion mode", &count)
    LabTestAssert(LabNumber("-0.5", "test", -1, 1) = -0.5, "negative fractional value", &count)
    for invalid in ["NaN", "Infinity", "1e9", "1,5", "", "99999999999999999999999999999"] {
        rejected := false
        try LabNumber(invalid, "test", -100, 100)
        catch
            rejected := true
        LabTestAssert(rejected, "reject invalid numeric " invalid, &count)
    }
    rejected := false
    try LabNumber("1.5", "integer", 1, 5, true)
    catch
        rejected := true
    LabTestAssert(rejected, "integer validation", &count)
    packet := LabMouseInput(-2, 3)
    offset := A_PtrSize = 8 ? 8 : 4
    LabTestAssert(packet.Size = (A_PtrSize = 8 ? 40 : 28), "INPUT ABI size", &count)
    LabTestAssert(NumGet(packet, 0, "UInt") = 0, "INPUT_MOUSE type", &count)
    LabTestAssert(NumGet(packet, offset, "Int") = -2, "signed relative X", &count)
    LabTestAssert(NumGet(packet, offset + 4, "Int") = 3, "signed relative Y", &count)
    LabTestAssert(NumGet(packet, offset + 12, "UInt") = 1, "MOUSEEVENTF_MOVE only", &count)
    engine := {Armed: true, State: "burst", Generation: 4, SessionStart: 0}
    event := {ElapsedMs: 100}
    LabTestAssert(LabCanSend(engine, 4, 100, 101, event, cfg, profile, true, true, true), "valid send guard", &count)
    LabTestAssert(!LabCanSend(engine, 3, 100, 101, event, cfg, profile, true, true, true), "stale callback rejected", &count)
    LabTestAssert(!LabCanSend(engine, 4, 100, 101, event, cfg, profile, false, true, true), "focus guard", &count)
    LabTestAssert(!LabCanSend(engine, 4, 100, 101, event, cfg, profile, true, false, true), "physical button guard", &count)
    LabTestAssert(!LabCanSend(engine, 4, 100, 250, event, cfg, profile, true, true, true), "late callback rejected", &count)
    LabTestAssert(!LabCanSend(engine, 4, 100, cfg.SessionLimitMs, event, cfg, profile, true, true, true), "session deadline guard", &count)
    event.ElapsedMs := cfg.MaxBurstMs
    LabTestAssert(!LabCanSend(engine, 4, 100, 101, event, cfg, profile, true, true, true), "burst deadline guard", &count)
    fakeLog := LabFakeLogger()
    fakeSender := LabFakeSender()
    event := LabEvent("move")
    event.Dx := 2
    event.Dy := -3
    fakeLog.Full := true
    rejected := false
    try LabAttemptMovement(fakeLog, event, "real_input", "A", 1, true, true, true, ObjBindMethod(fakeSender, "Send"))
    catch
        rejected := true
    LabTestAssert(rejected && fakeSender.Calls = 0, "full evidence buffer prevents any input call", &count)
    fakeLog.Full := false
    result := LabAttemptMovement(fakeLog, event, "real_input", "A", 1, true, true, true, ObjBindMethod(fakeSender, "Send"))
    LabTestAssert(result = 1 && fakeSender.Calls = 1, "fake sender accepted", &count)
    LabTestAssert(fakeLog.Profile = "A" && fakeLog.Attempted, "captured profile and attempt recorded", &count)
    LabTestAssert(event.SendReturnQpc >= event.SendCallQpc && event.OsInserted = 1, "call timing recorded", &count)
    fakeSender.Result := 0
    result := LabAttemptMovement(fakeLog, event, "real_input", "A", 1, true, true, true, ObjBindMethod(fakeSender, "Send"))
    LabTestAssert(result = 0 && event.Reason = "os_rejected" && fakeLog.Attempted, "OS rejection is still an attempt", &count)
    DirCreate(A_ScriptDir "\tests\artifacts")
    calibrationPath := A_ScriptDir "\tests\artifacts\calibration-test-" LabQpcTicks() ".ini"
    LabSaveProfileCalibration(calibrationPath, names["M416"], 1.5)
    LabSaveCalibration(calibrationPath, "AKM", 0, 2.5, 1.25)
    LabSaveCalibration(calibrationPath, "Mk12", 0, 3, 1.5)
    loaded := LabLoadCalibrations(ReadLabConfig(configPath), calibrationPath)
    saved := Map()
    for entry in loaded.Profiles
        saved[entry.Name] := entry
    LabTestAssert(saved["M416"].MotionMode = "elapsed" && saved["M416"].SavedGain = 1.5,
        "calibration reload retains base profile motion policy", &count)
    invalidConfigPath := calibrationPath ".config.ini"
    FileCopy(configPath, invalidConfigPath)
    IniWrite("unknown", invalidConfigPath, "Profile:M416", "MotionMode")
    rejected := false
    try ReadLabConfig(invalidConfigPath)
    catch
        rejected := true
    LabTestAssert(rejected, "unknown motion mode fails visibly", &count)
    IniWrite("elapsed", invalidConfigPath, "Profile:M416", "MotionMode")
    IniWrite("single", invalidConfigPath, "Profile:M416", "TriggerMode")
    rejected := false
    try ReadLabConfig(invalidConfigPath)
    catch
        rejected := true
    LabTestAssert(rejected, "single trigger cannot use elapsed integration", &count)
    LabTestAssert(saved["AKM"].Segments[1].Dy = 2.5 && saved["AKM"].SavedGain = 1.25, "per-weapon calibration persisted", &count)
    LabTestAssert(saved["Mk12"].Segments[1].Dy = 3 && saved["Mk12"].RecoilStatus = "user_set_unvalidated", "second calibration preserves first", &count)
    LabTestAssert(LabScaledProfile(saved["Mk12"], 1.5).Segments[1].Dy = 5, "single pulses have integer scaled counts", &count)
    LabTestAssert(saved["AUG"].RecoilStatus = "unmeasured" && names["AKM"].Segments[1].Dy = 0, "unsaved profiles and defaults preserved", &count)
    IniWrite("6x", calibrationPath, "VerticalProgressivo", "Optic")
    phased := names["VerticalProgressivo"]
    LabSaveProfileCalibration(calibrationPath, phased, 1.4)
    roundTrip := LabLoadCalibrations(ReadLabConfig(configPath), calibrationPath)
    for entry in roundTrip.Profiles {
        if entry.Name = "VerticalProgressivo"
            recovered := entry
    }
    LabTestAssert(recovered.Segments.Length = 3 && recovered.SavedGain = 1.4, "gain save preserves phase count", &count)
    LabTestAssert(recovered.IntervalMs = phased.IntervalMs, "gain save preserves interval", &count)
    for phaseIndex, phase in phased.Segments {
        restored := recovered.Segments[phaseIndex]
        LabTestAssert(restored.UntilMs = phase.UntilMs && restored.Dx = phase.Dx && restored.Dy = phase.Dy,
            "phase round trip " phaseIndex, &count)
    }
    LabTestAssert(phased.SavedGain = 1 && phased.Segments[3].Dy = 3, "saving does not mutate source profile", &count)
    LabTestAssert(Abs(LabScaledProfile(recovered, 1.4).Segments[3].Dy - 4.2) < 0.000001,
        "gain applied once after round trip", &count)
    LabTestAssert(IniRead(calibrationPath, "VerticalProgressivo", "Optic") = "6x", "metadata preserved on gain save", &count)
    for invalidSegments in ["", "100,0,1;90,0,2", "0,0,1", "100,0,99", "100,0", "100,NaN,1"] {
        rejected := false
        try LabParseSegments(invalidSegments, "test", 12)
        catch
            rejected := true
        LabTestAssert(rejected, "reject malformed curve " invalidSegments, &count)
    }
    beforeInvalidSave := FileRead(calibrationPath)
    rejected := false
    try LabSaveProfileCalibration(calibrationPath, phased, 9)
    catch
        rejected := true
    LabTestAssert(rejected && FileRead(calibrationPath) = beforeInvalidSave, "invalid save preserves original file", &count)
    LabSaveCalibration(calibrationPath, "VerticalProgressivo", 0, 2, 1.2)
    LabTestAssert(IniRead(calibrationPath, "VerticalProgressivo", "Segments", "absent") = "absent",
        "explicit constant save removes old phases", &count)
    LabTestAssert(IniRead(calibrationPath, "VerticalProgressivo", "IntervalMs", "absent") = "absent",
        "explicit constant save removes interval override", &count)
    roundTrip := LabLoadCalibrations(ReadLabConfig(configPath), calibrationPath)
    for entry in roundTrip.Profiles {
        if entry.Name = "VerticalProgressivo"
            recovered := entry
    }
    LabTestAssert(recovered.Segments.Length = 1 && recovered.Segments[1].Dy = 2 && recovered.SavedGain = 1.2,
        "constant save replaces curve on reload", &count)
    IniWrite("unknown", calibrationPath, "VerticalProgressivo", "CalibrationFormat")
    rejected := false
    try LabLoadCalibrations(ReadLabConfig(configPath), calibrationPath)
    catch
        rejected := true
    LabTestAssert(rejected, "unknown calibration format fails visibly", &count)
    count += RunEffectiveProfileConfigTests(configPath)
    probeEngine := {Armed: false, Generation: 7}
    LabTestAssert(LabCanProbe(probeEngine, 7, 100, 101, 0, true, false, true, true), "probe accepts explicit held keys", &count)
    LabTestAssert(!LabCanProbe(probeEngine, 7, 100, 101, 0, true, true, true, true), "probe rejects firing button", &count)
    LabTestAssert(!LabCanProbe(probeEngine, 7, 100, 101, 0, false, false, true, true), "probe requires game focus", &count)
    LabTestAssert(!LabCanProbe(probeEngine, 7, 100, 101, 0, true, false, false, true), "probe requires held aim", &count)
    LabTestAssert(!LabCanProbe(probeEngine, 7, 100, 101, 0, true, false, true, false), "probe stops when F10 released", &count)
    LabTestAssert(!LabCanProbe(probeEngine, 7, 100, 600, 0, true, false, true, true), "probe has strict half-second deadline", &count)
    LabTestAssert(!LabCanProbe(probeEngine, 7, 100, 99, 0, true, false, true, true), "probe rejects backwards clock", &count)
    LabTestAssert(!LabCanProbe(probeEngine, 7, 100, 101, 10, true, false, true, true), "probe caps total pulses", &count)
    LabTestAssert(!LabCanProbe(probeEngine, 6, 100, 101, 0, true, false, true, true), "probe rejects changed generation", &count)
    probeEngine.Armed := true
    LabTestAssert(!LabCanProbe(probeEngine, 7, 100, 101, 0, true, false, true, true), "probe cannot overlap armed compensation", &count)
    return count
}

RunEffectiveProfileConfigTests(configPath) {
    count := 0
    profile := {Name: "M416", IntervalMs: 20, TriggerMode: "continuous",
        Segments: [{UntilMs: 100, Dx: 0, Dy: 1}, {UntilMs: 200, Dx: 0, Dy: 3}]}
    LabTestAssert(LabValidateEffectiveProfile(profile, 4, 12), "effective value exactly at MaxStep accepted", &count)
    LabAssertConfigError(() => LabValidateEffectiveProfile(profile, 5, 12),
        "later phase Dy=3 times gain=5 exceeds MaxStep=12", &count)
    for axes in [{Dx: -3, Dy: 0}, {Dx: 3, Dy: 0}, {Dx: 0, Dy: -3}] {
        signed := {Name: "signed", IntervalMs: 20, Segments: [{UntilMs: 100, Dx: axes.Dx, Dy: axes.Dy}]}
        LabAssertConfigError(() => LabValidateEffectiveProfile(signed, 5, 12),
            "effective limit applies to both axes and signs", &count)
    }
    single := {Name: "Mk12", IntervalMs: 20, TriggerMode: "single",
        Segments: [{UntilMs: 100, Dx: 0, Dy: 3}]}
    LabTestAssert(LabValidateEffectiveProfile(single, 4.1, 12), "single 12.3 rounds to accepted 12", &count)
    LabAssertConfigError(() => LabValidateEffectiveProfile(single, 4.2, 12),
        "single 12.6 rounds to rejected 13", &count)
    single.Segments[1].Dy := -3
    LabTestAssert(LabValidateEffectiveProfile(single, 4.1, 12), "single -12.3 rounds to accepted -12", &count)
    LabAssertConfigError(() => LabValidateEffectiveProfile(single, 4.2, 12),
        "single -12.6 rounds to rejected -13", &count)

    fixturePath := A_ScriptDir "\tests\artifacts\effective-profile-" LabQpcTicks() ".ini"
    FileCopy(configPath, fixturePath)
    IniWrite("M416-typo", fixturePath, "Lab", "StartProfile")
    LabAssertConfigError(() => ReadLabConfig(fixturePath), "unknown explicit StartProfile fails visibly", &count)
    IniWrite("", fixturePath, "Lab", "StartProfile")
    LabAssertConfigError(() => ReadLabConfig(fixturePath), "blank explicit StartProfile fails visibly", &count)
    IniWrite("M416", fixturePath, "Lab", "StartProfile")
    selected := ReadLabConfig(fixturePath)
    LabTestAssert(selected.Profiles[selected.StartProfileIndex].Name = "M416", "known StartProfile selects requested weapon", &count)
    IniDelete(fixturePath, "Lab", "StartProfile")
    LabTestAssert(ReadLabConfig(fixturePath).StartProfileIndex = 1, "omitted StartProfile keeps first-profile default", &count)
    IniWrite("100,13,0", fixturePath, "Profile:AKM", "Segments")
    LabAssertConfigError(() => ReadLabConfig(fixturePath), "oversized unselected base profile rejected", &count)
    IniWrite("100,0,12", fixturePath, "Profile:AKM", "Segments")
    LabTestAssert(ReadLabConfig(fixturePath).MaxStep = 12, "base profile exactly at MaxStep accepted", &count)

    calibrationPath := fixturePath ".calibration.ini"
    LabSaveCalibration(calibrationPath, "AKM", 0, 2, 1, 12)
    originalFile := FileRead(calibrationPath)
    LabAssertConfigError(() => LabSaveCalibration(calibrationPath, "AKM", 0, 3, 5, 12),
        "constant save rejects effective overflow", &count)
    LabAssertConfigError(() => LabSaveCalibration(calibrationPath, "AKM", 0, 3, 4.1, 12),
        "continuous constant save cannot round 12.3 down to limit", &count)
    LabAssertConfigError(() => LabSaveCalibration(calibrationPath, "AKM", 0, 1, 1, 12, "invalid"),
        "constant save rejects unknown trigger mode", &count)
    LabAssertConfigError(() => LabSaveCalibration(calibrationPath, "SKS", 0, 2.5, 1, 12, "single"),
        "single constant save requires whole raw counts like reload", &count)
    LabTestAssert(FileRead(calibrationPath) = originalFile, "rejected constant save preserves existing file", &count)
    LabAssertConfigError(() => LabSaveProfileCalibration(calibrationPath, profile, 5, 12),
        "curve save rejects overflow after first phase", &count)
    LabTestAssert(FileRead(calibrationPath) = originalFile, "rejected curve save preserves existing file", &count)
    absentPath := fixturePath ".absent.ini"
    LabAssertConfigError(() => LabSaveCalibration(absentPath, "AKM", 0, 3, 5, 12),
        "invalid save to new file rejected", &count)
    LabTestAssert(!FileExist(absentPath), "invalid save does not create calibration file", &count)

    LabSaveCalibration(calibrationPath, "AKM", 0, 3, 4, 12)
    LabSaveProfileCalibration(calibrationPath, profile, 4, 12)
    LabSaveProfileCalibration(calibrationPath, single, 4.1, 12)
    LabSaveCalibration(calibrationPath, "SKS", 0, 3, 4.1, 12, "single")
    loaded := LabLoadCalibrations(ReadLabConfig(configPath), calibrationPath)
    entries := Map()
    for entry in loaded.Profiles
        entries[entry.Name] := entry
    LabTestAssert(LabScaledProfile(entries["AKM"], entries["AKM"].SavedGain).Segments[1].Dy = 12,
        "constant exact-limit calibration round trips", &count)
    LabTestAssert(LabScaledProfile(entries["M416"], entries["M416"].SavedGain).Segments[2].Dy = 12,
        "curve exact-limit calibration round trips", &count)
    LabTestAssert(LabScaledProfile(entries["Mk12"], entries["Mk12"].SavedGain).Segments[1].Dy = -12,
        "single rounded-limit calibration round trips", &count)
    LabTestAssert(LabScaledProfile(entries["SKS"], entries["SKS"].SavedGain).Segments[1].Dy = 12,
        "single constant Dy3 gain4.1 saves and reloads rounded limit12", &count)
    IniWrite(5, calibrationPath, "AKM", "Gain")
    candidate := ReadLabConfig(configPath)
    LabAssertConfigError(() => LabLoadCalibrations(candidate, calibrationPath),
        "manually edited constant overflow rejected on load", &count)
    for entry in candidate.Profiles {
        if entry.Name = "AKM"
            LabTestAssert(entry.Segments[1].Dy = 0 && entry.SavedGain = 1,
                "invalid constant never mutates destination profile", &count)
    }
    IniWrite(4, calibrationPath, "AKM", "Gain")
    IniWrite(5, calibrationPath, "M416", "Gain")
    candidate := ReadLabConfig(configPath)
    LabAssertConfigError(() => LabLoadCalibrations(candidate, calibrationPath),
        "manually edited curve overflow rejected on load", &count)
    for entry in candidate.Profiles {
        if entry.Name = "M416"
            LabTestAssert(entry.Segments[1].Dy = 0 && entry.SavedGain = 1,
                "invalid curve never mutates destination profile", &count)
    }
    return count
}

LabAssertConfigError(callback, description, &count) {
    rejected := false
    try callback.Call()
    catch Error
        rejected := true
    LabTestAssert(rejected, description, &count)
}

class LabFakeLogger {
    Full := false
    RequireCapacity() {
        if this.Full
            throw Error("full")
    }
    Record(event, mode, profile, generation, focused, left, right, attempted) {
        this.Profile := profile
        this.Attempted := attempted
    }
}

class LabFakeSender {
    Calls := 0
    Result := 1
    Send(dx, dy) {
        this.Calls += 1
        return this.Result
    }
}

LabTestAssert(condition, description, &count) {
    if !condition
        throw Error("Assertion failed: " description)
    count += 1
}
