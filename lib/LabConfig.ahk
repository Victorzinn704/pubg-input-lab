#Include TrialLogger.ahk

ReadLabConfig(path) {
    if !FileExist(path)
        throw Error("Arquivo de configuracao ausente: " path)
    cfg := {}
    cfg.TargetExe := Trim(IniRead(path, "Lab", "TargetExe", "TslGame.exe"))
    if !RegExMatch(cfg.TargetExe, "i)^[a-z0-9_. -]+\.exe$")
        throw Error("TargetExe deve conter apenas o nome do executavel.")
    cfg.PollMs := LabNumber(IniRead(path, "Lab", "PollMs", "10"), "PollMs", 5, 100, true)
    cfg.MaxBurstMs := LabNumber(IniRead(path, "Lab", "MaxBurstMs", "3000"), "MaxBurstMs", 100, 10000, true)
    cfg.SessionLimitMs := 1000 * LabNumber(IniRead(path, "Lab", "SessionLimitSeconds", "900"), "SessionLimitSeconds", 10, 7200, true)
    cfg.MaxLateMs := LabNumber(IniRead(path, "Lab", "MaxLateMs", "100"), "MaxLateMs", 20, 1000, true)
    cfg.MaxStep := LabNumber(IniRead(path, "Lab", "MaxStep", "12"), "MaxStep", 1, 100, true)
    cfg.Profiles := []
    for section in StrSplit(IniRead(path), "`n", "`r") {
        if SubStr(section, 1, 8) != "Profile:"
            continue
        name := SubStr(section, 9)
        if name = ""
            throw Error("Perfil sem nome.")
        profile := {Name: name, Label: IniRead(path, section, "Label", name), Segments: []}
        profile.TriggerMode := IniRead(path, section, "TriggerMode", "continuous")
        if profile.TriggerMode != "continuous" && profile.TriggerMode != "single"
            throw Error(section ": TriggerMode deve ser continuous ou single.")
        profile.MotionMode := IniRead(path, section, "MotionMode", "step")
        if profile.MotionMode != "step" && profile.MotionMode != "elapsed" && profile.MotionMode != "timeline"
            throw Error(section ": MotionMode deve ser step, elapsed ou timeline.")
        if profile.MotionMode != "step" && profile.TriggerMode != "continuous"
            throw Error(section ": modo por tempo exige disparo continuo.")
        profile.MinTriggerMs := LabNumber(IniRead(path, section, "MinTriggerMs", "0"), "MinTriggerMs", 0, 1000)
        profile.FireIntervalMs := LabNumber(IniRead(path, section, "FireIntervalMs", "0"), "FireIntervalMs", 0, 1000)
        profile.RecoilStatus := IniRead(path, section, "RecoilStatus", "synthetic_example")
        profile.Source := IniRead(path, section, "Source", "")
        profile.SavedGain := 1.0
        profile.IntervalMs := LabNumber(IniRead(path, section, "IntervalMs"), section " IntervalMs", 10, 1000, true)
        profile.Segments := LabParseSegments(IniRead(path, section, "Segments"), section)
        LabValidateEffectiveProfile(profile, profile.SavedGain, cfg.MaxStep)
        cfg.Profiles.Push(profile)
    }
    if cfg.Profiles.Length = 0
        throw Error("Nenhuma secao Profile: encontrada.")
    cfg.StartProfileIndex := 0
    startProfile := IniRead(path, "Lab", "StartProfile", cfg.Profiles[1].Name)
    for index, profile in cfg.Profiles {
        if profile.Name = startProfile
            cfg.StartProfileIndex := index
    }
    if cfg.StartProfileIndex = 0
        throw Error("StartProfile nao corresponde a um perfil existente: " startProfile)
    cfg.StartMode := IniRead(path, "Lab", "StartMode", "dry_run")
    if cfg.StartMode != "dry_run" && cfg.StartMode != "real_input"
        throw Error("StartMode deve ser dry_run ou real_input.")
    return cfg
}

LabNumber(value, field, minimum, maximum, whole := false) {
    value := Trim(value)
    if !RegExMatch(value, "^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$")
        throw Error(field ": numero invalido; use ponto decimal.")
    numericValue := value + 0
    if numericValue < minimum || numericValue > maximum || (whole && numericValue != Floor(numericValue))
        throw Error(field ": valor fora do intervalo " minimum " a " maximum ".")
    return numericValue
}

LabParseSegments(specifications, field, maxStep := 100, whole := false) {
    segments := []
    previous := 0
    for specification in StrSplit(specifications, ";") {
        fields := StrSplit(specification, ",")
        if fields.Length != 3
            throw Error(field ": cada segmento deve ter fim_ms,dx,dy.")
        untilMs := LabNumber(fields[1], field " fim_ms", 1, 10000, true)
        if untilMs <= previous
            throw Error(field ": os tempos finais devem ser crescentes.")
        dx := LabNumber(fields[2], field " dx", -maxStep, maxStep, whole)
        dy := LabNumber(fields[3], field " dy", -maxStep, maxStep, whole)
        segments.Push({UntilMs: untilMs, Dx: dx, Dy: dy})
        previous := untilMs
    }
    if segments.Length = 0
        throw Error(field ": faltam segmentos.")
    return segments
}

LabSerializeSegments(segments) {
    serialized := ""
    for segment in segments
        serialized .= (A_Index = 1 ? "" : ";") segment.UntilMs "," segment.Dx "," segment.Dy
    return serialized
}

LabScaledProfile(profile, gain) {
    scaled := {Name: profile.Name, IntervalMs: profile.IntervalMs, Segments: []}
    scaled.TriggerMode := profile.HasOwnProp("TriggerMode") ? profile.TriggerMode : "continuous"
    scaled.MotionMode := profile.HasOwnProp("MotionMode") ? profile.MotionMode : "step"
    scaled.MinTriggerMs := profile.HasOwnProp("MinTriggerMs") ? profile.MinTriggerMs : 0
    for segment in profile.Segments {
        dx := segment.Dx * gain
        dy := segment.Dy * gain
        if scaled.TriggerMode = "single" {
            dx := Round(dx)
            dy := Round(dy)
        }
        scaled.Segments.Push({UntilMs: segment.UntilMs, Dx: dx, Dy: dy})
    }
    return scaled
}

LabValidateEffectiveProfile(profile, gain, maxStep) {
    gain := LabNumber(gain, "Gain", 0.1, 5)
    maxStep := LabNumber(maxStep, "MaxStep", 1, 100, true)
    for index, segment in LabScaledProfile(profile, gain).Segments {
        if Abs(segment.Dx) > maxStep || Abs(segment.Dy) > maxStep
            throw Error(profile.Name ": segmento " index " com ganho " gain
                " ultrapassa MaxStep=" maxStep ". Reduza a curva ou o ganho.")
    }
    return true
}

LabLoadCalibrations(cfg, path) {
    if !FileExist(path)
        return cfg
    for profile in cfg.Profiles {
        if IniRead(path, profile.Name, "Status", "") != "user_set_unvalidated"
            continue
        calibrationFormat := IniRead(path, profile.Name, "CalibrationFormat", "constant_v1")
        if calibrationFormat != "constant_v1" && calibrationFormat != "segments_v1"
            throw Error(profile.Name ": formato de calibracao desconhecido.")
        gain := LabNumber(IniRead(path, profile.Name, "Gain"), profile.Name " Gain", 0.1, 5)
        candidate := profile.Clone()
        if calibrationFormat = "segments_v1" {
            candidate.Segments := LabParseSegments(IniRead(path, profile.Name, "Segments"), profile.Name,
                cfg.MaxStep, profile.TriggerMode = "single")
            candidate.IntervalMs := LabNumber(IniRead(path, profile.Name, "IntervalMs"), profile.Name " IntervalMs", 10, 1000, true)
        } else {
            dx := LabNumber(IniRead(path, profile.Name, "Dx"), profile.Name " Dx", -cfg.MaxStep, cfg.MaxStep, profile.TriggerMode = "single")
            dy := LabNumber(IniRead(path, profile.Name, "Dy"), profile.Name " Dy", -cfg.MaxStep, cfg.MaxStep, profile.TriggerMode = "single")
            LabSetCalibration(candidate, dx, dy, gain)
        }
        LabValidateEffectiveProfile(candidate, gain, cfg.MaxStep)
        profile.Segments := candidate.Segments
        profile.IntervalMs := candidate.IntervalMs
        profile.SavedGain := gain
        profile.RecoilStatus := "user_set_unvalidated"
    }
    return cfg
}

LabSetCalibration(profile, dx, dy, gain) {
    profile.Segments := [{UntilMs: profile.Segments[-1].UntilMs, Dx: dx, Dy: dy}]
    profile.SavedGain := gain
    profile.RecoilStatus := "user_set_unvalidated"
}

LabSaveCalibration(path, name, dx, dy, gain, maxStep := 100, triggerMode := "continuous") {
    if triggerMode != "continuous" && triggerMode != "single"
        throw Error("TriggerMode deve ser continuous ou single.")
    maxStep := LabNumber(maxStep, "MaxStep", 1, 100, true)
    dx := LabNumber(dx, "Dx", -maxStep, maxStep, triggerMode = "single")
    dy := LabNumber(dy, "Dy", -maxStep, maxStep, triggerMode = "single")
    candidate := {Name: name, IntervalMs: 20, TriggerMode: triggerMode,
        Segments: [{UntilMs: 1, Dx: dx, Dy: dy}]}
    LabValidateEffectiveProfile(candidate, gain, maxStep)
    LabWriteCalibration(path, name, dx, dy, gain)
}

LabSaveProfileCalibration(path, profile, gain, maxStep := 100) {
    maxStep := LabNumber(maxStep, "MaxStep", 1, 100, true)
    serialized := LabSerializeSegments(profile.Segments)
    LabParseSegments(serialized, profile.Name, maxStep, profile.TriggerMode = "single")
    interval := LabNumber(profile.IntervalMs, "IntervalMs", 10, 1000, true)
    LabValidateEffectiveProfile(profile, gain, maxStep)
    LabWriteCalibration(path, profile.Name, profile.Segments[1].Dx, profile.Segments[1].Dy,
        gain, serialized, interval)
}

LabWriteCalibration(path, name, dx, dy, gain, segments := "", interval := 0) {
    if Trim(name) = "" || RegExMatch(name, "[\[\]\r\n]")
        throw Error("Nome de calibracao invalido.")
    dx := LabNumber(dx, "Dx", -100, 100)
    dy := LabNumber(dy, "Dy", -100, 100)
    gain := LabNumber(gain, "Gain", 0.1, 5)
    stagedPath := path ".pending-" LabQpcTicks()
    if FileExist(path)
        FileCopy(path, stagedPath, false)
    else {
        stagedFile := FileOpen(stagedPath, "w", "UTF-16")
        stagedFile.Close()
    }
    try {
        IniWrite(dx, stagedPath, name, "Dx")
        IniWrite(dy, stagedPath, name, "Dy")
        IniWrite(gain, stagedPath, name, "Gain")
        IniWrite(segments = "" ? "constant_v1" : "segments_v1", stagedPath, name, "CalibrationFormat")
        if segments != "" {
            IniWrite(segments, stagedPath, name, "Segments")
            IniWrite(interval, stagedPath, name, "IntervalMs")
        } else {
            IniDelete(stagedPath, name, "Segments")
            IniDelete(stagedPath, name, "IntervalMs")
        }
        IniWrite(LabUtcIso(), stagedPath, name, "SavedUtc")
        IniWrite("user_set_unvalidated", stagedPath, name, "Status")
        FileMove(stagedPath, path, true)
    } catch as saveError {
        try FileDelete(stagedPath)
        throw saveError
    }
}

LabMouseInput(dx, dy) {
    size := A_PtrSize = 8 ? 40 : 28
    offset := A_PtrSize = 8 ? 8 : 4
    packet := Buffer(size, 0)
    NumPut("Int", dx, "Int", dy, "UInt", 0, "UInt", 0x0001, "UInt", 0, packet, offset)
    return packet
}
