; Configuration and state transitions only. This module installs no hooks or input.
#Include RecoilEngine.ahk
#Include LabConfig.ahk

LabReadHotkeys(path, profiles, fallbackPath := "") {
    source := FileExist(path) ? path : fallbackPath
    if source = "" || !FileExist(source)
        throw Error("Configuracao de atalhos ausente: " path)
    bindings := LabParseHotkeys(FileRead(source, "UTF-8"), profiles)
    bindings.SourcePath := source
    return bindings
}

LabParseHotkeys(contents, profiles) {
    known := Map()
    known.CaseSense := "Off"
    for index, profile in profiles
        known[profile.Name] := {Name: profile.Name, Index: index}
    byProfile := Map()
    byProfile.CaseSense := "Off"
    usedKeys := Map()
    weapons := []
    inWeapons := false
    foundSection := false
    for lineNumber, rawLine in StrSplit(LTrim(contents, Chr(0xFEFF)), "`n", "`r") {
        line := Trim(rawLine)
        if line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#"
            continue
        if RegExMatch(line, "^\[([^\]]+)\]$", &section) {
            if StrLower(section[1]) != "weapons" || foundSection
                throw Error("Atalhos, linha " lineNumber ": use uma unica secao [Weapons].")
            inWeapons := true
            foundSection := true
            continue
        }
        if !inWeapons || !RegExMatch(line, "^([^=]+)=([^=]+)$", &entry)
            throw Error("Atalhos, linha " lineNumber ": esperado Perfil=Letra em [Weapons].")
        name := Trim(entry[1])
        key := StrUpper(Trim(entry[2]))
        if !known.Has(name)
            throw Error("Atalhos, linha " lineNumber ": perfil desconhecido: " name)
        if !RegExMatch(key, "^[A-Z1-9]$")
            throw Error("Atalhos, linha " lineNumber ": use A-Z ou 1-9; zero e reservado ao ponto central.")
        if key = "D"
            throw Error("Ctrl+Alt+D e reservado para desativar.")
        if byProfile.Has(name)
            throw Error("Perfil repetido nos atalhos: " known[name].Name)
        if usedKeys.Has(key)
            throw Error("Atalho repetido: Ctrl+Alt+" key)
        profile := known[name]
        binding := {Profile: profile.Name, ProfileIndex: profile.Index, Key: StrLower(key),
            Chord: "^!" StrLower(key), Label: "Ctrl+Alt+" key}
        usedKeys[key] := true
        weapons.Push(binding)
        byProfile[profile.Name] := binding
    }
    if !weapons.Length
        throw Error("[Weapons] deve configurar pelo menos um perfil.")
    return {Weapons: weapons, ByProfile: byProfile,
        Stop: {Key: "d", Chord: "^!d", Label: "Ctrl+Alt+D"}}
}

LabSelectWeapon(engine, cfg, currentIndex, currentGain, targetIndex, now, focused) {
    result := {Accepted: false, Changed: false, Engine: engine, ProfileIndex: currentIndex,
        Gain: currentGain, PreviousEvents: [], Events: []}
    if !focused
        return result
    if !IsInteger(targetIndex) || targetIndex < 1 || targetIndex > cfg.Profiles.Length
        throw Error("Indice de perfil invalido para o atalho.")
    result.Accepted := true
    if targetIndex = currentIndex && engine.Armed && engine.State != "expired"
        && now >= engine.SessionStart && now - engine.SessionStart < cfg.SessionLimitMs
        return result
    profile := cfg.Profiles[targetIndex]
    gain := targetIndex = currentIndex ? currentGain : profile.SavedGain
    LabValidateEffectiveProfile(profile, gain, cfg.MaxStep)
    changed := targetIndex != currentIndex || gain != currentGain
    if changed {
        ; Validate the replacement before invalidating the previous generation.
        next := RecoilEngine(LabScaledProfile(profile, gain), cfg)
        result.PreviousEvents := engine.Disarm("weapon_switch", now)
        next.SessionStart := engine.SessionStart
        next.Generation := engine.Generation + 1
        next.BurstId := engine.BurstId
        if engine.State = "expired"
            next.State := "expired"
        result.Engine := next
        result.Changed := true
        result.ProfileIndex := targetIndex
        result.Gain := gain
    }
    result.Events := result.Engine.Arm(now)
    return result
}

LabProfileHasMovement(profile) {
    for segment in profile.Segments {
        if segment.Dx || segment.Dy
            return true
    }
    return false
}

LabWeaponIdentity(profile) {
    name := profile.HasOwnProp("Weapon") ? profile.Weapon : profile.Name
    key := RegExReplace(StrUpper(StrReplace(name, Chr(0x039F), "O")), "[^A-Z0-9]", "")
    aliases := Map("M4", "M416", "BERYL", "BERYLM762", "UZI", "MICROUZI",
        "UMP45", "UMP", "THOMPSON", "TOMMYGUN", "MK14SINGLE", "MK14", "MK14CONTINUOUS", "MK14")
    return aliases.Has(key) ? aliases[key] : key
}

LabCyclePresetIndex(profiles, currentIndex, direction) {
    if direction != 1 && direction != -1
        throw Error("Direcao deve ser +1 ou -1.")
    if !IsInteger(currentIndex) || currentIndex < 1 || currentIndex > profiles.Length
        throw Error("Indice de perfil invalido.")
    current := profiles[currentIndex]
    identity := LabWeaponIdentity(current)
    mode := current.HasOwnProp("TriggerMode") ? current.TriggerMode : "continuous"
    candidates := []
    position := 0
    for index, profile in profiles {
        profileMode := profile.HasOwnProp("TriggerMode") ? profile.TriggerMode : "continuous"
        if LabWeaponIdentity(profile) = identity && profileMode = mode {
            candidates.Push(index)
            if index = currentIndex
                position := candidates.Length
        }
    }
    next := Mod(position - 1 + direction + candidates.Length, candidates.Length) + 1
    return candidates[next]
}
