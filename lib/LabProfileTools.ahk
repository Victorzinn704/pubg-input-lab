; Pure workflow helpers. No hooks, capture, input dispatch or game inference.
#Include LabPresets.ahk
#Include LabHotkeys.ahk

LabProfileGroup(profile) {
    return LabWeaponIdentity(profile) "-" profile.TriggerMode
}

LabProfileHasOutput(profile, gain := unset) {
    return LabProfileHasMovement(LabScaledProfile(profile, IsSet(gain) ? gain : profile.SavedGain))
}

LabEmptySelection() {
    preferred := Map()
    preferred.CaseSense := "Off"
    return {LastProfile: "", Preferred: preferred}
}

LabParseSelection(text) {
    data := LabParseDataIni(text)
    if data.Count != 2 || !data.Has("Selection") || !data.Has("Preferred")
        throw Error("Selecao local invalida.")
    header := data["Selection"]
    if header.Count != 2 || !header.Has("SchemaVersion") || header["SchemaVersion"] != "1" || !header.Has("LastProfile")
        throw Error("Versao da selecao local invalida.")
    selection := LabEmptySelection()
    selection.LastProfile := header["LastProfile"]
    if selection.LastProfile != ""
        LabPresetText(selection.LastProfile, "Ultimo perfil")
    for key, name in data["Preferred"] {
        if !RegExMatch(key, "^[A-Z0-9]+-(?:single|continuous)$")
            throw Error("Preferencia de arma invalida.")
        LabPresetText(name, "Perfil preferido")
        selection.Preferred[key] := name
    }
    return selection
}

LabSelectionText(selection) {
    text := "[Selection]`nSchemaVersion=1`nLastProfile=" selection.LastProfile "`n`n[Preferred]`n"
    for key, name in selection.Preferred
        text .= key "=" name "`n"
    LabParseSelection(text)
    return text
}

LabResolveWeaponProfile(profiles, index, selection) {
    requested := profiles[index]
    ; Explicit library bindings remain exact; only base weapon shortcuts resolve variants.
    if SubStr(requested.Name, 1, 5) = "User_"
        return index
    group := LabProfileGroup(requested)
    if selection.Preferred.Has(group) {
        for candidateIndex, candidate in profiles {
            if candidate.Name = selection.Preferred[group] && LabProfileGroup(candidate) = group && LabProfileHasOutput(candidate)
                return candidateIndex
        }
    }
    if LabProfileHasOutput(requested)
        return index
    for candidateIndex, candidate in profiles {
        if LabProfileGroup(candidate) = group && LabProfileHasOutput(candidate)
            return candidateIndex
    }
    return index
}

LabCycleReadyProfile(profiles, index, direction) {
    if direction != 1 && direction != -1
        throw Error("Direcao invalida.")
    group := LabProfileGroup(profiles[index])
    Loop profiles.Length {
        candidate := Mod(index - 1 + direction * A_Index + profiles.Length, profiles.Length) + 1
        if LabProfileGroup(profiles[candidate]) = group && LabProfileHasOutput(profiles[candidate])
            return candidate
    }
    return index
}

LabProfileSearch(profiles, query) {
    found := []
    words := StrSplit(StrLower(Trim(query)), " ")
    for index, profile in profiles {
        p := LabClonePreset(profile)
        haystack := StrLower(p.Name " " p.Label " " p.Weapon " " p.Optic " " p.Zoom " " p.Stance " " p.Attachments)
        matches := true
        for word in words {
            if word != "" && !InStr(haystack, word) {
                matches := false
                break
            }
        }
        if matches
            found.Push(index)
    }
    return found
}

LabProfileSummary(profile, gain, maxBurst) {
    p := LabClonePreset(profile)
    duration := Min(maxBurst, p.Segments[-1].UntilMs)
    text := p.Weapon " | " p.Optic " / " p.Zoom " | " p.Stance
    text .= "`n" (LabProfileHasOutput(p, gain) ? "Curva configurada; resultado no jogo ainda nao medido." : "SEM MOVIMENTO: escolha outra variante ou edite a curva.")
    text .= "`nDuracao efetiva: " Format("{:g}", duration / 1000) " s | ganho " Format("{:.2f}", gain)
    text .= " | " (p.MotionMode = "timeline" ? "tempo acumulado" : p.MotionMode = "elapsed" ? "tempo limitado" : "por passo")
    if p.TriggerMode = "single"
        text .= "`nY inicial: " Round(p.Segments[1].Dy * gain) " contagens por clique."
    else
        text .= "`nTaxa inicial nominal Y: " Format("{:.2f}", p.Segments[1].Dy * gain * 1000 / p.IntervalMs) " contagens/s."
    if RegExMatch(p.Source, "scale=([0-9.]+)", &scale)
        text .= "`nSCHOOL: escala " Format("{:g}", (scale[1] + 0) * 100) "% | intervalo assumido " p.IntervalMs " ms."
    if p.Sensitivity = "Nao registrada"
        text .= "`nSensibilidade ainda nao registrada para esta curva."
    return text
}

; Rows: last shot, X counts per shot, Y counts per shot. No empirical values invented.
LabFromShotTable(template, text, fireInterval, maxStep) {
    fireInterval := LabNumber(fireInterval, "Intervalo entre tiros", 10, 1000, true)
    preset := LabClonePreset(template)
    preset.Name := "User_" LabQpcTicks()
    preset.TriggerMode := "continuous"
    preset.MotionMode := "timeline"
    preset.FireIntervalMs := fireInterval
    preset.IntervalMs := 20
    preset.SavedGain := 1
    preset.RecoilStatus := "user_set_unvalidated"
    preset.Source := "Tabela por disparo informada pelo usuario; sem medicao automatica"
    preset.Segments := []
    previous := 0
    for raw in StrSplit(text, "`n", "`r") {
        if Trim(raw) = ""
            continue
        fields := StrSplit(raw, ",")
        if fields.Length != 3
            throw Error("Use ultima_bala,X,Y em cada linha.")
        shot := LabNumber(fields[1], "Ultima bala", 1, 1000, true)
        if shot <= previous || shot * fireInterval > 10000
            throw Error("Balas devem crescer e a curva deve durar ate 10 segundos.")
        x := LabNumber(fields[2], "X por disparo", -1000, 1000) * 20 / fireInterval
        y := LabNumber(fields[3], "Y por disparo", -1000, 1000) * 20 / fireInterval
        preset.Segments.Push({UntilMs: shot * fireInterval, Dx: x, Dy: y})
        previous := shot
    }
    LabValidatePreset(preset, maxStep)
    return preset
}
