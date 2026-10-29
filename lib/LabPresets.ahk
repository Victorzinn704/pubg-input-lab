; Versioned data and pure transformations. No hooks, windows or input dispatch.
#Include LabConfig.ahk

LabClonePreset(profile) {
    copy := profile.Clone()
    copy.Segments := []
    for segment in profile.Segments
        copy.Segments.Push(segment.Clone())
    defaults := Map("Weapon", profile.Name, "Optic", "Padrao", "Zoom", "Padrao",
        "Stance", "Em pe", "Attachments", "Padrao", "Sensitivity", "Nao registrada")
    for key, value in defaults {
        if !copy.HasOwnProp(key)
            copy.%key% := value
    }
    return copy
}

LabNewPreset(name := "") {
    return {Name: name = "" ? "User_" LabQpcTicks() : name, Label: "Novo preset",
        Weapon: "Personalizada", Optic: "Padrao", Zoom: "Padrao", Stance: "Em pe",
        Attachments: "Padrao", Sensitivity: "Nao registrada", TriggerMode: "continuous",
        MotionMode: "elapsed", MinTriggerMs: 0, FireIntervalMs: 0, IntervalMs: 20,
        SavedGain: 1.0, RecoilStatus: "user_set_unvalidated", Source: "local",
        Segments: [{UntilMs: 3000, Dx: 0, Dy: 0}]}
}

LabPresetText(value, field, maxLength := 160) {
    value := Trim(value)
    if value = "" || StrLen(value) > maxLength || RegExMatch(value, "[\x00-\x1f\[\]]")
        throw Error(field ": texto vazio, longo ou com caracteres de controle.")
    return value
}

LabValidatePreset(profile, maxStep) {
    if !RegExMatch(profile.Name, "^User_[A-Za-z0-9_-]{1,48}$")
        throw Error("ID de preset invalido; esperado User_ seguido de letras ou numeros.")
    for key in ["Label", "Weapon", "Optic", "Zoom", "Stance", "Attachments", "Sensitivity", "Source"]
        LabPresetText(profile.%key%, key, key = "Source" ? 512 : 160)
    if !InStr("|Em pe|Agachado|Deitado|", "|" profile.Stance "|")
        throw Error("Postura invalida.")
    if profile.TriggerMode != "continuous" && profile.TriggerMode != "single"
        throw Error("Modo de disparo invalido.")
    if profile.MotionMode != "elapsed" && profile.MotionMode != "step" && profile.MotionMode != "timeline"
        throw Error("Modo de movimento invalido.")
    if profile.TriggerMode = "single" && profile.MotionMode != "step"
        throw Error("Tiro unico exige modo por passo.")
    if profile.RecoilStatus != "user_set_unvalidated" && profile.RecoilStatus != "external_unvalidated"
        throw Error("O preset deve permanecer identificado como nao validado.")
    LabNumber(profile.IntervalMs, "Intervalo", 10, 1000, true)
    LabNumber(profile.MinTriggerMs, "Intervalo minimo do gatilho", 0, 1000, true)
    LabNumber(profile.FireIntervalMs, "Intervalo entre tiros", 0, 1000, true)
    if profile.Segments.Length > 1000
        throw Error("Limite de 1000 segmentos por preset.")
    LabParseSegments(LabSerializeSegments(profile.Segments), profile.Name, maxStep, profile.TriggerMode = "single")
    LabValidateEffectiveProfile(profile, profile.SavedGain, maxStep)
    return true
}

; Deliberately strict: Win32 INI silently hides duplicate sections/keys.
LabParseDataIni(contents) {
    sections := Map()
    sections.CaseSense := "Off"
    section := 0
    if StrLen(contents) > 2000000
        throw Error("Arquivo excede 2 MB de texto.")
    for raw in StrSplit(LTrim(contents, Chr(0xFEFF)), "`n", "`r") {
        line := Trim(raw)
        if line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#"
            continue
        if RegExMatch(line, "^\[([^\]]+)\]$", &match) {
            if sections.Has(match[1])
                throw Error("Secao duplicada: " match[1])
            section := Map()
            section.CaseSense := "Off"
            sections[match[1]] := section
        } else {
            position := InStr(line, "=")
            if !section || position <= 1
                throw Error("Esperado campo=valor dentro de uma secao.")
            key := Trim(SubStr(line, 1, position - 1))
            if section.Has(key)
                throw Error("Campo duplicado: " key)
            section[key] := Trim(SubStr(line, position + 1))
        }
    }
    return sections
}

LabPresetFields() {
    return ["Label", "Weapon", "Optic", "Zoom", "Stance", "Attachments", "Sensitivity",
        "TriggerMode", "MotionMode", "MinTriggerMs", "FireIntervalMs", "IntervalMs",
        "SavedGain", "RecoilStatus", "Source"]
}

LabParseLibrary(contents, maxStep) {
    data := LabParseDataIni(contents)
    if !data.Has("Library") || data["Library"].Count != 1
        || !data["Library"].Has("SchemaVersion") || data["Library"]["SchemaVersion"] != "1"
        throw Error("Formato de biblioteca desconhecido; esperado SchemaVersion=1.")
    entries := []
    for section, fields in data {
        if section = "Library"
            continue
        if SubStr(section, 1, 7) != "Preset:"
            throw Error("Secao desconhecida: " section)
        preset := LabNewPreset(SubStr(section, 8))
        expected := LabPresetFields()
        if fields.Count != expected.Length + 1
            throw Error(section ": campos ausentes ou desconhecidos.")
        for key in expected {
            if !fields.Has(key)
                throw Error(section ": campo ausente " key)
            preset.%key% := fields[key]
        }
        if !fields.Has("Segments")
            throw Error(section ": curva ausente.")
        preset.Segments := LabParseSegments(fields["Segments"], section, maxStep, preset.TriggerMode = "single")
        LabValidatePreset(preset, maxStep)
        entries.Push(preset)
        if entries.Length > 256
            throw Error("Limite de 256 presets por biblioteca.")
    }
    return entries
}

LabSerializeLibrary(entries, maxStep) {
    if entries.Length > 256
        throw Error("Limite de 256 presets por biblioteca.")
    text := "[Library]`nSchemaVersion=1`n"
    names := Map()
    names.CaseSense := "Off"
    for profile in entries {
        LabValidatePreset(profile, maxStep)
        if names.Has(profile.Name)
            throw Error("ID duplicado: " profile.Name)
        names[profile.Name] := true
        text .= "`n[Preset:" profile.Name "]`n"
        for key in LabPresetFields()
            text .= key "=" profile.%key% "`n"
        text .= "Segments=" LabSerializeSegments(profile.Segments) "`n"
    }
    return text
}

LabReadLibrary(path, maxStep) {
    if !FileExist(path)
        return []
    if FileGetSize(path) > 4000000
        throw Error("Biblioteca excede 4 MB.")
    return LabParseLibrary(FileRead(path), maxStep)
}

LabWriteTextAtomic(path, text, validator) {
    validator.Call(text)
    staged := path ".pending-" LabQpcTicks()
    try {
        FileAppend(text, staged, "UTF-8")
        validator.Call(FileRead(staged))
        if FileExist(path)
            FileCopy(path, path ".bak", true)
        FileMove(staged, path, true)
    } finally {
        if FileExist(staged)
            FileDelete(staged)
    }
}

LabWriteLibrary(path, entries, maxStep) {
    LabWriteTextAtomic(path, LabSerializeLibrary(entries, maxStep), (text) => LabParseLibrary(text, maxStep))
}

LabMergeLibrary(baseProfiles, entries) {
    combined := baseProfiles.Clone()
    names := Map()
    names.CaseSense := "Off"
    for profile in baseProfiles
        names[profile.Name] := true
    for profile in entries {
        if names.Has(profile.Name)
            throw Error("Preset conflita com um perfil existente: " profile.Name)
        names[profile.Name] := true
        combined.Push(profile)
    }
    return combined
}

LabImportPresets(existing, incoming, maxStep) {
    combined := existing.Clone()
    names := Map()
    names.CaseSense := "Off"
    for profile in existing
        names[profile.Name] := true
    for profile in incoming {
        copy := LabClonePreset(profile)
        if names.Has(copy.Name) {
            copy.Name := "User_" LabQpcTicks() "_" A_Index
            copy.Label := SubStr(copy.Label, 1, 145) " (importado)"
        }
        names[copy.Name] := true
        combined.Push(copy)
    }
    LabSerializeLibrary(combined, maxStep)
    return combined
}

LabReadSchool(path) {
    entries := []
    if FileGetSize(path) > 100000
        throw Error("Referencia SCHOOL excede 100 KB.")
    for name, fields in LabParseDataIni(FileRead(path)) {
        if fields.Count != 5
            throw Error("Referencia SCHOOL deve conter normal, ctrl, prone, delay e strength.")
        entry := {Name: LabPresetText(name, "Arma")}
        for key in ["normal", "ctrl", "prone", "delay", "strength"] {
            if !fields.Has(key)
                throw Error("Referencia SCHOOL incompleta: " name)
            entry.%key% := LabNumber(fields[key], name " " key, key = "delay" ? 1 : 0, 1000, true)
        }
        entries.Push(entry)
    }
    return entries
}

LabConvertSchool(entry, stance, observedInterval, scale, duration, maxStep) {
    observedInterval := LabNumber(observedInterval, "Intervalo assumido do loop", 10, 1000, true)
    scale := LabNumber(scale, "Escala de importacao", 0.001, 1)
    duration := LabNumber(duration, "Duracao", observedInterval, 10000, true)
    if !InStr("|Em pe|Agachado|Deitado|", "|" stance "|")
        throw Error("Postura invalida.")
    base := stance = "Deitado" ? entry.prone : (stance = "Agachado" ? entry.ctrl : entry.normal)
    preset := LabNewPreset()
    preset.Label := entry.Name " - SCHOOL (FDCaffeine) - " stance
    preset.Weapon := entry.Name
    preset.Stance := stance
    preset.IntervalMs := observedInterval
    preset.MotionMode := "step"
    preset.RecoilStatus := "external_unvalidated"
    preset.Source := "SCHOOL@4c2d56a; requested_ms=" entry.delay "; assumed_ms=" observedInterval "; scale=" Format("{:g}", scale)
    preset.Segments := []
    Loop Ceil(duration / observedInterval) {
        dy := Format("{:.6f}", Min(1000, Round(base + A_Index * (entry.strength / 1000) ** 2)) * scale)
        endTime := Min(duration, A_Index * observedInterval)
        if preset.Segments.Length && Abs(preset.Segments[-1].Dy - dy) < 0.0000001
            preset.Segments[-1].UntilMs := endTime
        else
            preset.Segments.Push({UntilMs: endTime, Dx: 0, Dy: dy})
    }
    LabValidatePreset(preset, maxStep)
    return preset
}

LabSchoolPresetPack(entries, maxStep) {
    presets := []
    for entry in entries {
        for stanceIndex, stance in ["Em pe", "Agachado", "Deitado"] {
            profile := LabConvertSchool(entry, stance, 16, 0.1, 3000, maxStep)
            token := RegExReplace(StrUpper(StrReplace(entry.Name, Chr(0x039F), "O")), "[^A-Z0-9]", "")
            profile.Name := "User_School_" token "_" stanceIndex
            presets.Push(profile)
        }
    }
    LabSerializeLibrary(presets, maxStep)
    return presets
}

LabAddMissingPresets(existing, incoming, maxStep) {
    combined := existing.Clone()
    names := Map()
    names.CaseSense := "Off"
    for profile in existing
        names[profile.Name] := true
    for profile in incoming {
        if !names.Has(profile.Name) {
            combined.Push(LabClonePreset(profile))
            names[profile.Name] := true
        }
    }
    LabSerializeLibrary(combined, maxStep)
    return combined
}

LabReadPreferences(path) {
    defaults := {ReticleEnabled: 0, ReticleSize: 5, ReticleColor: "E85D6A"}
    if !FileExist(path)
        return defaults
    values := LabParseDataIni(FileRead(path))
    if values.Count != 1 || !values.Has("Display") || values["Display"].Count != 3
        throw Error("Configuracao visual invalida.")
    for key in ["ReticleEnabled", "ReticleSize", "ReticleColor"] {
        if !values["Display"].Has(key)
            throw Error("Configuracao visual incompleta.")
        defaults.%key% := values["Display"][key]
    }
    LabPreferencesText(defaults)
    return defaults
}

LabPreferencesText(prefs) {
    LabNumber(prefs.ReticleEnabled, "Ponto central", 0, 1, true)
    LabNumber(prefs.ReticleSize, "Tamanho", 3, 9, true)
    if !RegExMatch(prefs.ReticleColor, "^[A-Fa-f0-9]{6}$")
        throw Error("Cor invalida.")
    return "[Display]`nReticleEnabled=" prefs.ReticleEnabled "`nReticleSize=" prefs.ReticleSize
        . "`nReticleColor=" prefs.ReticleColor "`n"
}
