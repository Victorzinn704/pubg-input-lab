#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ..\lib\LabHotkeys.ahk

try {
    hotkeyTestCount := RunHotkeyTests()
    FileAppend("PASS: " hotkeyTestCount " hotkey assertions; pure selection, no hooks or input.`n", "*")
    ExitApp(0)
} catch as hotkeyTestError {
    FileAppend("FAIL: " hotkeyTestError.Message " | line " hotkeyTestError.Line "`n" hotkeyTestError.Stack "`n", "**")
    ExitApp(1)
}

RunHotkeyTests() {
    assertions := 0
    configPath := A_ScriptDir "\..\profiles.ini"
    cfg := ReadLabConfig(configPath)
    defaults := LabReadHotkeys(A_ScriptDir "\..\hotkeys.example.ini", cfg.Profiles)
    expected := Map("M416", "a", "BerylM762", "b", "AKM", "k", "ACE32", "c", "Groza", "g",
        "AUG", "m", "SCARL", "s", "UMP", "u", "MicroUZI", "i", "TommyGun", "t", "Mini14", "n",
        "Mk12", "l", "Mk14_single", "j", "Mk14_continuous", "o", "SKS", "h")
    HotkeyAssert(defaults.Weapons.Length = expected.Count, "Every requested weapon has a default chord", &assertions)
    for name, key in expected {
        HotkeyAssert(defaults.ByProfile.Has(name), "Missing default binding: " name, &assertions)
        binding := defaults.ByProfile[name]
        HotkeyAssert(binding.Key = key && binding.Chord = "^!" key, "Wrong default chord: " name, &assertions)
        HotkeyAssert(cfg.Profiles[binding.ProfileIndex].Name = name, "Binding index points to a different profile", &assertions)
    }
    HotkeyAssert(defaults.Stop.Key = "d" && defaults.Stop.Chord = "^!d", "The only stop chord is Ctrl+Alt+D", &assertions)
    custom := LabParseHotkeys(Chr(0xFEFF) "; comment`r`n[Weapons]`r`nm416 = z`r`n# comment`nBerylM762 = Q`n", cfg.Profiles)
    HotkeyAssert(custom.ByProfile["M416"].Chord = "^!z" && custom.ByProfile["BerylM762"].Chord = "^!q",
        "Custom letters and case-insensitive profile names must be respected", &assertions)
    invalid := ["", "[Weapons]", "M416=A", "[Other]`nM416=A", "[Weapons]`nUnknown=A",
        "[Weapons]`nM416=D", "[Weapons]`nM416=d", "[Weapons]`nM416=A`nM416=B",
        "[Weapons]`nM416=A`nm416=B", "[Weapons]`nM416=A`nBerylM762=a",
        "[Weapons]`nM416=F8", "[Weapons]`nM416=^!A", "[Weapons]`nM416=XButton1",
        "[Weapons]`nM416=", "[Weapons]`nM416=A=B", "[Weapons]`nM416 A",
        "[Weapons]`nM416=A`n[Weapons]`nBerylM762=B"]
    for text in invalid
        HotkeyAssertThrows(LabParseHotkeys.Bind(text, cfg.Profiles), "Invalid hotkey file accepted: " text, &assertions)

    missing := A_Temp "\RecoilLab-hotkeys-missing-" DllCall("GetCurrentProcessId", "UInt") "-" A_TickCount ".ini"
    fallback := LabReadHotkeys(missing, cfg.Profiles, A_ScriptDir "\..\hotkeys.example.ini")
    HotkeyAssert(fallback.Weapons.Length = 15 && !FileExist(missing),
        "Fallback must load the example without creating a private configuration", &assertions)
    HotkeyAssert(fallback.SourcePath = A_ScriptDir "\..\hotkeys.example.ini", "Fallback must report the actual source", &assertions)
    HotkeyAssertThrows(LabReadHotkeys.Bind(missing, cfg.Profiles), "A missing file without fallback must fail", &assertions)
    try {
        FileAppend("[Weapons]`nM416=D`n", missing, "UTF-8-RAW")
        HotkeyAssertThrows(LabReadHotkeys.Bind(missing, cfg.Profiles, A_ScriptDir "\..\hotkeys.example.ini"),
            "An invalid private configuration must not silently fall back to defaults", &assertions)
    } finally {
        if FileExist(missing)
            FileDelete(missing)
    }

    cfg.SessionLimitMs := 100000
    for index, profile in cfg.Profiles
        LabSetCalibration(profile, 0, 1, Round(1 + index / 10, 1))
    currentIndex := 1
    currentGain := cfg.Profiles[currentIndex].SavedGain
    engine := RecoilEngine(LabScaledProfile(cfg.Profiles[currentIndex], currentGain), cfg)
    now := 100
    sessionStart := now
    for binding in defaults.Weapons {
        previous := engine
        previousGeneration := engine.Generation
        wasBurst := engine.State = "burst"
        result := LabSelectWeapon(engine, cfg, currentIndex, currentGain, binding.ProfileIndex, now, true)
        engine := result.Engine
        currentIndex := result.ProfileIndex
        currentGain := result.Gain
        HotkeyAssert(result.Accepted && result.Changed, "Switch must select the requested weapon", &assertions)
        HotkeyAssert(engine.Profile.Name = binding.Profile && engine.Armed, "Switch must arm the target weapon", &assertions)
        HotkeyAssert(currentGain = cfg.Profiles[binding.ProfileIndex].SavedGain, "Switch must restore target saved gain", &assertions)
        HotkeyAssert(engine.SessionStart = sessionStart, "Switch must preserve the original session deadline", &assertions)
        HotkeyAssert(engine.Generation > previousGeneration && !previous.Armed,
            "Only the new generation may remain armed", &assertions)
        HotkeyAssert(engine.State = "wait_release", "A switched profile requires physical trigger release", &assertions)
        if wasBurst
            HotkeyAssert(HotkeyHasEvent(result.PreviousEvents, "burst_stop"), "Switch must cancel the prior burst", &assertions)
        HotkeyAssert(!HotkeyHasEvent(result.Events, "move"), "Selection itself must never generate movement", &assertions)

        engine.Tick(now + 1, true, false, true)
        engine.Tick(now + 2, true, true, true)
        HotkeyAssert(engine.State = "burst", "Synthetic held buttons must establish an active burst", &assertions)
        generation := engine.Generation
        burst := engine.BurstId
        repeated := LabSelectWeapon(engine, cfg, currentIndex, currentGain, currentIndex, now + 3, true)
        HotkeyAssert(repeated.Accepted && !repeated.Changed && repeated.Engine = engine,
            "Repeating the armed weapon must preserve the engine", &assertions)
        HotkeyAssert(engine.Generation = generation && engine.BurstId = burst && engine.State = "burst",
            "Repeating the armed weapon must not restart a burst", &assertions)
        HotkeyAssert(repeated.Events.Length = 0 && repeated.PreviousEvents.Length = 0,
            "Idempotent selection must not manufacture transitions", &assertions)
        rejected := LabSelectWeapon(engine, cfg, currentIndex, currentGain, defaults.Weapons[1].ProfileIndex, now + 4, false)
        HotkeyAssert(!rejected.Accepted && rejected.Engine = engine && engine.Generation = generation,
            "An unfocused selection must not mutate state", &assertions)
        now += 50
    }

    stopEvents := engine.Disarm("manual_stop", now)
    generation := engine.Generation
    HotkeyAssert(!engine.Armed && HotkeyHasEvent(stopEvents, "burst_stop"), "Global stop must cancel the active burst", &assertions)
    HotkeyAssert(engine.SessionStart = sessionStart, "Stopping must preserve the original session start", &assertions)
    engine.Disarm("manual_stop", now + 1)
    HotkeyAssert(!engine.Armed && engine.Generation > generation, "Repeated stop must invalidate pending work", &assertions)
    rearmed := LabSelectWeapon(engine, cfg, currentIndex, currentGain, currentIndex, now + 2, true)
    HotkeyAssert(rearmed.Engine.Armed && rearmed.Engine.SessionStart = sessionStart,
        "Reactivation must not reset the session deadline", &assertions)
    HotkeyAssertThrows(LabSelectWeapon.Bind(engine, cfg, currentIndex, currentGain, 0, now + 3, true),
        "Invalid profile index must fail", &assertions)

    selected := defaults.Weapons[1].ProfileIndex
    unsavedGain := cfg.Profiles[selected].SavedGain + 0.25
    unsaved := RecoilEngine(LabScaledProfile(cfg.Profiles[selected], unsavedGain), cfg)
    unsaved.Arm(1000)
    repeated := LabSelectWeapon(unsaved, cfg, selected, unsavedGain, selected, 1001, true)
    HotkeyAssert(repeated.Gain = unsavedGain && repeated.Engine = unsaved && unsaved.Generation = 1,
        "An already armed weapon must keep its current unsaved gain", &assertions)

    nextIndex := defaults.Weapons[2].ProfileIndex
    edited := RecoilEngine(LabScaledProfile(cfg.Profiles[selected], unsavedGain), cfg)
    edited.Arm(1000)
    edited.Disarm("configuration_changed", 1001)
    editedRate := edited.Profile.Segments[1].Dy
    rearmedEdited := LabSelectWeapon(edited, cfg, selected, unsavedGain, selected, 1002, true)
    HotkeyAssert(rearmedEdited.Engine = edited && rearmedEdited.Engine.Armed && rearmedEdited.Gain = unsavedGain,
        "Rearming the same weapon must retain its applied but unsaved gain", &assertions)
    HotkeyAssert(rearmedEdited.Engine.Profile.Segments[1].Dy = editedRate && rearmedEdited.Engine.SessionStart = 1000,
        "Same-weapon rearming must preserve the effective movement and deadline", &assertions)
    changedEdited := LabSelectWeapon(rearmedEdited.Engine, cfg, selected, rearmedEdited.Gain, nextIndex, 1003, true)
    HotkeyAssert(changedEdited.Engine.Armed && changedEdited.Gain = cfg.Profiles[nextIndex].SavedGain,
        "Switching to another weapon must still load that weapon's saved gain", &assertions)

    destination := cfg.Profiles[nextIndex]
    savedSegments := destination.Segments
    savedGain := destination.SavedGain
    destination.Segments := [{UntilMs: 3000, Dx: 0, Dy: cfg.MaxStep}]
    destination.SavedGain := 2
    HotkeyAssertThrows(LabSelectWeapon.Bind(unsaved, cfg, selected, unsavedGain, nextIndex, 1002, true),
        "An excessive effective movement must reject weapon selection", &assertions)
    HotkeyAssert(unsaved.Armed && unsaved.Generation = 1 && unsaved.Profile.Name = cfg.Profiles[selected].Name,
        "Rejected target settings must not mutate the previous engine", &assertions)
    destination.Segments := savedSegments
    destination.SavedGain := savedGain

    cfg.SessionLimitMs := 20
    expiring := RecoilEngine(LabScaledProfile(cfg.Profiles[selected], unsavedGain), cfg)
    expiring.Arm(2000)
    atDeadline := LabSelectWeapon(expiring, cfg, selected, unsavedGain, selected, 2020, true)
    HotkeyAssert(!atDeadline.Engine.Armed && atDeadline.Engine.State = "expired",
        "Same-weapon idempotence must not bypass the exact session deadline", &assertions)
    switchedExpired := LabSelectWeapon(atDeadline.Engine, cfg, atDeadline.ProfileIndex, atDeadline.Gain,
        nextIndex, 2021, true)
    HotkeyAssert(!switchedExpired.Engine.Armed && switchedExpired.Engine.State = "expired"
        && switchedExpired.Engine.SessionStart = 2000, "Switching an expired session must not revive it", &assertions)

    expiring := RecoilEngine(LabScaledProfile(cfg.Profiles[selected], cfg.Profiles[selected].SavedGain), cfg)
    expiring.Arm(3000)
    switchedAtDeadline := LabSelectWeapon(expiring, cfg, selected, cfg.Profiles[selected].SavedGain,
        nextIndex, 3020, true)
    HotkeyAssert(!switchedAtDeadline.Engine.Armed && switchedAtDeadline.Engine.State = "expired"
        && switchedAtDeadline.Engine.SessionStart = 3000, "Changing weapons at the deadline must remain expired", &assertions)
    zero := {Segments: [{Dx: 0, Dy: 0}, {Dx: 0, Dy: 0}]}
    HotkeyAssert(!LabProfileHasMovement(zero), "Zero profiles must be distinguishable from calibrated input", &assertions)
    zero.Segments[2].Dx := 0.5
    HotkeyAssert(LabProfileHasMovement(zero), "Movement detection must inspect every segment", &assertions)
    return assertions
}

HotkeyHasEvent(events, kind) {
    for event in events {
        if event.Kind = kind
            return true
    }
    return false
}

HotkeyAssertThrows(callback, label, &assertions) {
    rejected := false
    try callback.Call()
    catch Error
        rejected := true
    HotkeyAssert(rejected, label, &assertions)
}

HotkeyAssert(condition, label, &assertions) {
    assertions += 1
    if !condition
        throw Error(label)
}
