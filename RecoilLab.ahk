#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include %A_ScriptDir%\lib\RecoilEngine.ahk
#Include %A_ScriptDir%\lib\TrialLogger.ahk
#Include %A_ScriptDir%\lib\LabConfig.ahk
#Include %A_ScriptDir%\lib\LabInstance.ahk
#Include %A_ScriptDir%\lib\LabStatusOverlay.ahk
#Include %A_ScriptDir%\lib\LabHotkeys.ahk
#Include %A_ScriptDir%\tests\EngineTests.ahk
#Include %A_ScriptDir%\tests\ConfigTests.ahk
#Include %A_ScriptDir%\tests\LoggerTests.ahk

try {
    if A_Args.Length && A_Args[1] = "--self-test" {
        labAssertionCount := RunEngineTests() + RunConfigTests(A_ScriptDir "\profiles.ini")
            + RunLoggerTests(A_ScriptDir "\profiles.ini")
        FileAppend("PASS: " labAssertionCount " assertions; no hooks or input installed.`n", "*")
        ExitApp(0)
    }
    labStartArmed := A_Args.Length && A_Args[1] = "--background-armed"
    if A_Args.Length && A_Args[1] != "--smoke-test" && A_Args[1] != "--background" && !labStartArmed
        throw Error("Argumento desconhecido. Use --self-test, --smoke-test, --background ou --background-armed.")
    if !(A_Args.Length && A_Args[1] = "--smoke-test") {
        labInstanceHandle := LabClaimInstance()
        if !labInstanceHandle
            ExitApp(0)
    }
    app := RecoilLab(A_Args.Length && A_Args[1] = "--smoke-test", (A_Args.Length && A_Args[1] = "--background") || labStartArmed)
    if labStartArmed {
        app.SetEnabled(true)
        if app.Failed || !app.Engine.Armed
            throw Error("Falha ao ativar o ensaio pela linha de comando.")
    }
} catch as startupError {
    if A_Args.Length {
        FileAppend("FAIL: " startupError.Message " | line " startupError.Line "`n" startupError.Stack "`n", "**")
        ExitApp(1)
    }
    MsgBox(startupError.Message, "Recoil Lab - erro", "Iconx")
    ExitApp(1)
}

class RecoilLab {
    __New(smoke := false, background := false) {
        this.Smoke := smoke
        this.LastFeedback := ""
        this.FeedbackCallback := ObjBindMethod(this, "ClearFeedback")
        this.ConfigPath := A_ScriptDir "\profiles.ini"
        this.CalibrationPath := A_ScriptDir "\calibrations.ini"
        if smoke {
            DirCreate(A_ScriptDir "\tests\artifacts")
            this.CalibrationPath := A_ScriptDir "\tests\artifacts\calibration-smoke-" LabQpcTicks() ".ini"
        }
        this.Config := LabLoadCalibrations(ReadLabConfig(this.ConfigPath), this.CalibrationPath)
        this.Hotkeys := LabReadHotkeys(A_ScriptDir "\hotkeys.ini", this.Config.Profiles,
            A_ScriptDir "\hotkeys.example.ini")
        this.ProfileIndex := smoke ? 1 : this.Config.StartProfileIndex
        this.Gain := this.Config.Profiles[this.ProfileIndex].SavedGain
        this.Mode := smoke ? "dry_run" : this.Config.StartMode
        this.Closing := false
        this.Failed := false
        this.Marker := 0
        this.LastUi := 0
        this.LastFlush := 0
        this.LastHeartbeat := 0
        this.Engine := RecoilEngine(this.SelectedProfile(), this.Config)
        sources := [A_ScriptFullPath, A_ScriptDir "\lib\RecoilEngine.ahk",
            A_ScriptDir "\lib\TrialLogger.ahk", A_ScriptDir "\lib\LabConfig.ahk",
            A_ScriptDir "\lib\LabStatusOverlay.ahk", A_ScriptDir "\lib\LabHotkeys.ahk", this.Hotkeys.SourcePath]
        if FileExist(this.CalibrationPath)
            sources.Push(this.CalibrationPath)
        logRoot := A_ScriptDir (smoke ? "\tests\artifacts" : "\logs")
        this.Logger := TrialLogger(logRoot, this.ConfigPath, sources)
        this.BuildGui()
        this.BuildStatusGui()
        if !smoke
            OnMessage(0x8001, ObjBindMethod(this, "ShowPanel"))
        this.Logger.Record(LabEvent("configuration", "gain=" this.Gain ";motion=" this.Engine.Profile.MotionMode ";api=SendInput;startup=disabled;mode=" this.Mode),
            this.Mode, this.SelectedProfile().Name, this.Engine.Generation, false, false, false)
        OnExit(ObjBindMethod(this, "OnShutdown"))
        if smoke {
            this.Gui.Show("Hide w620")
            this.GainInput.Value := "1.5"
            this.ProfileChoice.Choose(2)
            this.ModeChoice.Choose(2)
            this.ApplyControls()
            if this.Gain != 1.5 || this.ProfileIndex != 2 || this.Mode != "real_input" || this.Engine.Armed
                throw Error("Smoke test: falha ao aplicar controles.")
            this.Toggle()
            sessionStart := this.Engine.SessionStart
            if !this.Engine.Armed
                throw Error("Smoke test: falha ao armar estado sem entrada.")
            this.ModeChoice.Choose(1)
            this.ApplyControls()
            if this.Engine.Armed || this.Mode != "dry_run" || this.Engine.SessionStart != sessionStart
                throw Error("Smoke test: mudanca de modo nao preservou limites/desarme.")
            for profileNumber, entry in this.Config.Profiles {
                if entry.Name = "Mk12" {
                    this.ProfileChoice.Choose(profileNumber)
                    break
                }
            }
            this.ProfileChanged()
            this.CalibrationX.Value := "0"
            this.CalibrationY.Value := "3"
            this.GainInput.Value := "1.5"
            this.SaveCalibration()
            if this.Failed || this.Engine.Armed || this.Engine.Profile.TriggerMode != "single"
                throw Error("Smoke test: falha ao salvar calibracao single.")
            reloaded := LabLoadCalibrations(ReadLabConfig(this.ConfigPath), this.CalibrationPath)
            if reloaded.Profiles[this.ProfileIndex].SavedGain != 1.5 || reloaded.Profiles[this.ProfileIndex].Segments[1].Dy != 3
                throw Error("Smoke test: ajuste por arma nao persistiu.")
            if !InStr(this.StatusLabel.Value, "Mk12") || !InStr(this.StatusLabel.Value, "ganho 1.50")
                || this.CalibrationY.Value != 3 || this.Engine.Profile.Segments[1].Dy != 5
                throw Error("Smoke test: painel, indicador e motor nao refletem o ajuste salvo.")
            rejectedGeneration := this.Engine.Generation
            this.GainInput.Value := "5"
            this.ApplyControls()
            if this.Failed || this.Gain != 1.5 || this.Engine.Generation != rejectedGeneration
                throw Error("Smoke test: amplitude invalida alterou estado ou causou erro fatal.")
            this.CalibrationY.Value := "12"
            this.GainInput.Value := "5"
            this.SaveCalibration()
            if this.Failed || this.Gain != 1.5 || this.Engine.Generation != rejectedGeneration
                throw Error("Smoke test: calibracao invalida alterou estado ou causou erro fatal.")
            this.GainInput.Value := this.Gain
            this.ShowCalibrationFields()
            this.GainInput.Value := "4.1"
            this.SaveCalibration()
            reloaded := LabLoadCalibrations(ReadLabConfig(this.ConfigPath), this.CalibrationPath)
            if this.Failed || this.Gain != 4.1 || this.Engine.Profile.Segments[1].Dy != 12
                || reloaded.Profiles[this.ProfileIndex].SavedGain != 4.1
                throw Error("Smoke test: arredondamento single valido nao persistiu no limite efetivo.")
            this.SmokeQuickControls(sessionStart)
            this.ProfileChoice.Choose(1)
            this.GainInput.Value := 1
            this.ModeChoice.Choose(2)
            this.ApplyControls()
            this.SelectWeapon(1, true)
            if !this.Engine.Armed || !InStr(this.StatusLabel.Value, "SEM AJUSTE")
                throw Error("Smoke test: perfil sem movimento nao foi identificado no indicador.")
            this.SetEnabled(true)
            activationGeneration := this.Engine.Generation
            this.SetEnabled(true)
            if !this.Engine.Armed || this.Engine.Generation != activationGeneration
                throw Error("Smoke test: ativacao repetida alterou o estado.")
            this.SetEnabled(false)
            disabledGeneration := this.Engine.Generation
            this.SetEnabled(false)
            if this.Engine.Armed || this.Engine.SessionStart != sessionStart || this.Engine.Generation <= disabledGeneration
                throw Error("Smoke test: desativacao alterou limite de sessao.")
            if LabCanProbe(this.Engine, disabledGeneration, 0, 1, 0, true, false, true, true)
                throw Error("Smoke test: desativacao nao cancelou sonda pendente.")
            this.Gui.Destroy()
            this.StatusGui.Destroy()
            this.Logger.Close("smoke_test_without_hooks_or_input")
            this.Closing := true
            FileAppend("PASS: GUI, modes, session limit, weapon calibration, quick controls and logging; no hooks or input installed.`n", "*")
            ExitApp(0)
        }
        InstallMouseHook()
        InstallKeybdHook()
        HotIfWinActive("ahk_exe " this.Config.TargetExe)
        for binding in this.Hotkeys.Weapons
            Hotkey(binding.Chord, ObjBindMethod(this, "WeaponKey", binding.ProfileIndex, binding.Key))
        Hotkey("F3", ObjBindMethod(this, "QuickKey", "gain_down", "F3"))
        Hotkey("F4", ObjBindMethod(this, "QuickKey", "gain_up", "F4"))
        Hotkey("F5", ObjBindMethod(this, "QuickKey", "save_gain", "F5"))
        HotIfWinActive()
        Hotkey("F6", ObjBindMethod(this, "ShowPanel"))
        Hotkey(this.Hotkeys.Stop.Chord, ObjBindMethod(this, "DeactivateKey", this.Hotkeys.Stop.Key))
        Hotkey("F9", ObjBindMethod(this, "MarkKey"))
        Hotkey("F10", ObjBindMethod(this, "ProbeMovement"))
        Hotkey("F12", ObjBindMethod(this, "Quit"))
        this.PollCallback := ObjBindMethod(this, "Poll")
        SetTimer(this.PollCallback, this.Config.PollMs)
        this.Gui.Show(background ? "Hide w620" : "w620")
        this.Refresh()
    }

    SelectedProfile() {
        return LabScaledProfile(this.Config.Profiles[this.ProfileIndex], this.Gain)
    }

    BuildStatusGui() {
        this.Overlay := LabStatusOverlay()
        this.StatusGui := this.Overlay.Gui
        this.StatusLabel := this.Overlay.Label
    }

    BuildGui() {
        this.Gui := Gui(, "Recoil Lab - ensaio instrumentado")
        this.Gui.SetFont("s10", "Segoe UI")
        this.Gui.MarginX := 18
        this.Gui.MarginY := 14
        this.Gui.AddText("w580", "Ensaio de entrada | AutoHotkey v2 | versao 1.3.0")
        this.Gui.AddText("xm y+10 w580", "Alvo: " this.Config.TargetExe " | Gatilho: segurar os botoes esquerdo + direito")
        this.StateText := this.Gui.AddText("xm y+12 w580 h24", "DESARMADO")
        this.FeedbackText := this.Gui.AddText("xm y+2 w580 h20", "")
        this.Gui.AddText("xm y+12", "Perfil")
        labels := []
        for profile in this.Config.Profiles
            labels.Push(profile.Label (this.Hotkeys.ByProfile.Has(profile.Name)
                ? " | " this.Hotkeys.ByProfile[profile.Name].Label : ""))
        this.ProfileChoice := this.Gui.AddDropDownList("xm y+4 w580 Choose" this.ProfileIndex, labels)
        this.ProfileChoice.OnEvent("Change", ObjBindMethod(this, "ProfileChanged"))
        this.Gui.AddText("xm y+12", "Modo")
        this.ModeChoice := this.Gui.AddDropDownList("xm y+4 w350 Choose" (this.Mode = "dry_run" ? 1 : 2), ["Simulacao - sem enviar movimento", "Entrada real - SendInput"])
        this.ModeChoice.OnEvent("Change", ObjBindMethod(this, "ApplyControls"))
        this.Gui.AddText("x+16 yp+3", "Ganho (0.1 a 5)")
        this.GainInput := this.Gui.AddEdit("xm y+12 w90", this.Gain)
        this.Gui.AddButton("x+10 w150", "Aplicar ganho").OnEvent("Click", ObjBindMethod(this, "ApplyControls"))
        this.CalibrationHint := this.Gui.AddText("xm y+12 w580", "")
        this.Gui.AddText("xm y+6", "X:")
        this.CalibrationX := this.Gui.AddEdit("x+6 w65", "0")
        this.Gui.AddText("x+12 yp+3", "Y:")
        this.CalibrationY := this.Gui.AddEdit("x+6 yp-3 w65", "0")
        this.Gui.AddButton("x+12 w230", "Aplicar e salvar X/Y").OnEvent("Click", ObjBindMethod(this, "SaveCalibration"))
        this.DetailText := this.Gui.AddEdit("xm y+14 w580 r5 ReadOnly -Wrap", "")
        this.ToggleButton := this.Gui.AddButton("xm y+14 w180 h32", "Armar / desarmar")
        this.ToggleButton.OnEvent("Click", ObjBindMethod(this, "Toggle"))
        this.Gui.AddButton("x+12 w180 h32", "Marcar evento (F9)").OnEvent("Click", ObjBindMethod(this, "Mark"))
        this.Gui.AddButton("x+12 w180 h32", "Encerrar (F12)").OnEvent("Click", ObjBindMethod(this, "Quit"))
        this.Gui.AddButton("xm y+10 w180", "Abrir logs").OnEvent("Click", ObjBindMethod(this, "OpenLogs"))
        this.Gui.AddButton("x+12 w180", "Abrir configuracao").OnEvent("Click", ObjBindMethod(this, "OpenConfig"))
        this.Gui.AddText("xm y+14 w580", "Ctrl+Alt + letra da arma: selecionar e ativar | Ctrl+Alt+D: parar | F12: sair")
        this.Gui.AddText("xm y+8 w580", "Atalho de cada arma na lista acima. F3/F4 ajustam ganho; F5 salva. Ajustes desarmam.")
        this.Gui.AddText("xm y+8 w580", "Teste: segure F10 + botao direito, sem esquerdo. Pulso curto para baixo; desarma.")
        this.Gui.AddText("xm y+8 w580", "Ao armar/entre rajadas, solte o botao esquerdo; pode manter a mira.")
        this.Gui.AddText("xm y+8 w580", "Armas SEM CALIBRACAO usam X/Y=0. Cadencia documentada nao calibra recoil.")
        this.SessionText := this.Gui.AddText("xm y+10 w580", "Sessao: " this.Logger.SessionId)
        this.Gui.OnEvent("Close", ObjBindMethod(this, "Quit"))
        this.Gui.OnEvent("Escape", ObjBindMethod(this, "ShowPanel"))
        this.ShowCalibrationFields()
    }

    ShowCalibrationFields() {
        profile := this.Config.Profiles[this.ProfileIndex]
        this.CalibrationX.Value := profile.Segments[1].Dx
        this.CalibrationY.Value := profile.Segments[1].Dy
        this.CalibrationHint.Value := profile.TriggerMode = "single"
            ? "Ajuste de teste: contagens inteiras por clique fisico (sem disparo automatico)."
            : profile.MotionMode = "elapsed"
                ? "Suavizado: contagens por " profile.IntervalMs " ms, distribuidas pelo tempo decorrido."
                : "Ajuste de teste: contagens por passo de " profile.IntervalMs " ms; nao por bala."
    }

    ProfileChanged(*) {
        if this.Failed || this.Closing
            return
        this.GainInput.Value := this.Config.Profiles[this.ProfileChoice.Value].SavedGain
        this.ApplyControls()
        this.ShowCalibrationFields()
    }

    SaveCalibration(*) {
        if this.Failed || this.Closing
            return
        try {
            profile := this.Config.Profiles[this.ProfileIndex]
            single := profile.TriggerMode = "single"
            try {
                dx := LabNumber(this.CalibrationX.Value, "X", -this.Config.MaxStep, this.Config.MaxStep, single)
                dy := LabNumber(this.CalibrationY.Value, "Y", -this.Config.MaxStep, this.Config.MaxStep, single)
                gain := LabNumber(this.GainInput.Value, "Ganho", 0.1, 5)
                proposal := profile.Clone()
                proposal.Segments := [{UntilMs: profile.Segments[-1].UntilMs, Dx: dx, Dy: dy}]
                LabValidateEffectiveProfile(proposal, gain, this.Config.MaxStep)
            } catch as validationError {
                this.QuickFeedback(validationError.Message, true)
                return
            }
            this.RecordEvents(this.Engine.Disarm("calibration_edit", this.Logger.NowMs()))
            LabSaveCalibration(this.CalibrationPath, profile.Name, dx, dy, gain, this.Config.MaxStep, profile.TriggerMode)
            LabSetCalibration(profile, dx, dy, gain)
            this.RecordCalibrationSnapshot(profile.Name)
            this.ApplyControls()
            this.ShowCalibrationFields()
            this.QuickFeedback("Ajustes aplicados e salvos. " this.ActivationHint())
        } catch as err {
            this.Fail(err)
        }
    }

    RecordCalibrationSnapshot(profileName) {
        snapshotName := "calibration-" LabQpcTicks() ".ini"
        FileCopy(this.CalibrationPath, this.Logger.Dir "\" snapshotName, false)
        this.Logger.Record(LabEvent("calibration_saved", "snapshot=" snapshotName ";status=user_set_unvalidated"),
            this.Mode, profileName, this.Engine.Generation, false, false, false)
    }

    QuickKey(action, key, *) {
        try {
            if !WinActive("ahk_exe " this.Config.TargetExe)
                return
            this.QuickAction(action)
        } finally {
            KeyWait(key)
        }
    }

    ActivationHint() {
        name := this.Config.Profiles[this.ProfileIndex].Name
        return this.Hotkeys.ByProfile.Has(name)
            ? "No jogo, " this.Hotkeys.ByProfile[name].Label " seleciona e ativa."
            : "Este perfil nao tem atalho; configure hotkeys.ini ou use o painel."
    }

    WeaponKey(profileIndex, key, *) {
        try this.SelectWeapon(profileIndex)
        finally KeyWait(key)
    }

    SelectWeapon(profileIndex, focused := unset) {
        if this.Failed || this.Closing
            return false
        focused := this.Smoke && IsSet(focused) ? focused : !!WinActive("ahk_exe " this.Config.TargetExe)
        if !focused
            return false
        try {
            if profileIndex != this.ProfileIndex || !this.Engine.Armed
                LabValidateEffectiveProfile(this.Config.Profiles[profileIndex],
                    profileIndex = this.ProfileIndex ? this.Gain : this.Config.Profiles[profileIndex].SavedGain,
                    this.Config.MaxStep)
        } catch as validationError {
            this.QuickFeedback(validationError.Message, true)
            return false
        }
        try {
            Critical("On")
            try {
                if !this.Smoke
                    focused := !!WinActive("ahk_exe " this.Config.TargetExe)
                change := LabSelectWeapon(this.Engine, this.Config, this.ProfileIndex, this.Gain,
                    profileIndex, this.Logger.NowMs(), focused)
                if !change.Accepted
                    return false
                this.RecordEvents(change.PreviousEvents)
                this.Engine := change.Engine
                this.ProfileIndex := change.ProfileIndex
                this.Gain := change.Gain
                this.ProfileChoice.Choose(this.ProfileIndex)
                this.GainInput.Value := this.Gain
                if change.Changed
                    this.Logger.Record(LabEvent("configuration", "gain=" this.Gain ";motion=" this.Engine.Profile.MotionMode ";source=weapon_hotkey"),
                        this.Mode, this.SelectedProfile().Name, this.Engine.Generation, focused, false, false)
                this.Logger.Record(LabEvent("weapon_selection", "select_and_enable"), this.Mode,
                    this.SelectedProfile().Name, this.Engine.Generation, focused, false, false)
                this.RecordEvents(change.Events)
            } finally {
                Critical("Off")
            }
            this.ShowCalibrationFields()
            this.Logger.Flush()
            this.Refresh()
            if !this.Engine.Armed
                this.QuickFeedback("Limite de sessao atingido; reinicie para um novo ensaio.", true)
            else if this.Mode = "real_input" && !LabProfileHasMovement(this.Engine.Profile)
                this.QuickFeedback("SEM CALIBRACAO: " this.SelectedProfile().Name " tem X/Y=0; nenhum movimento sera enviado.")
            else
                this.QuickFeedback(this.SelectedProfile().Name " ativada. Solte o gatilho antes de disparar.")
            return this.Engine.Armed
        } catch as err {
            this.Fail(err)
            return false
        }
    }

    QuickAction(action) {
        if this.Failed || this.Closing
            return
        try {
            switch action {
                case "gain_down", "gain_up":
                    candidate := Round(this.Gain + (action = "gain_up" ? 0.1 : -0.1), 3)
                    if candidate < 0.1 || candidate > 5 {
                        this.QuickFeedback("Limite de ganho: 0.1 a 5. Ajuste recusado.", true)
                        return
                    }
                    if action = "gain_up" && !this.GainFitsSteps(candidate) {
                        this.QuickFeedback("Limite de movimento atingido (MaxStep=" this.Config.MaxStep "). Aumento recusado.", true)
                        return
                    }
                    this.GainInput.Value := candidate
                    this.ApplyControls()
                    if this.Failed
                        return
                    this.QuickFeedback("Ganho alterado. F5 salva. " this.ActivationHint())
                case "save_gain":
                    if !this.GainFitsSteps(this.Gain) {
                        this.QuickFeedback("Ganho excede MaxStep. Reduza com F3 antes de salvar.", true)
                        return
                    }
                    profile := this.Config.Profiles[this.ProfileIndex]
                    this.RecordEvents(this.Engine.Disarm("quick_" action, this.Logger.NowMs()))
                    LabSaveProfileCalibration(this.CalibrationPath, profile, this.Gain, this.Config.MaxStep)
                    profile.SavedGain := this.Gain
                    profile.RecoilStatus := "user_set_unvalidated"
                    this.RecordCalibrationSnapshot(profile.Name)
                    this.QuickFeedback("Ganho salvo; segmentos preservados. " this.ActivationHint())
                default:
                    throw Error("Acao de atalho desconhecida: " action)
            }
            this.Refresh()
        } catch as err {
            this.Fail(err)
        }
    }

    GainFitsSteps(gain) {
        try return LabValidateEffectiveProfile(this.Config.Profiles[this.ProfileIndex], gain, this.Config.MaxStep)
        catch Error
            return false
    }

    QuickFeedback(message, rejected := false) {
        this.LastFeedback := message
        this.Refresh()
        if this.Smoke
            return
        SetTimer(this.FeedbackCallback, -2500)
        try SoundBeep(rejected ? 500 : (this.Engine.Armed ? 1300 : 800), 35)
    }

    ClearFeedback() {
        this.LastFeedback := ""
        this.Refresh()
    }

    DisplayState() {
        if !this.Smoke && this.Engine.Armed && !WinActive("ahk_exe " this.Config.TargetExe)
            return "ARMADO - aguardando foco no jogo"
        return LabStateLabel(this.Engine.State)
    }

    UpdateStatus() {
        label := this.DisplayState()
        zeroInput := this.Mode = "real_input" && this.Engine.Armed && !LabProfileHasMovement(this.Engine.Profile)
        compactState := this.Failed ? "ERRO" : (zeroInput ? "SEM AJUSTE" : (this.Engine.Armed ? "ARMADO" : "DESARMADO"))
        if this.Mode = "dry_run"
            compactState := "SIM " compactState
        status := compactState " | " this.Config.Profiles[this.ProfileIndex].Name " | ganho " Format("{:.2f}", this.Gain)
        if this.Smoke {
            this.StatusLabel.Value := status
            return
        }
        A_IconTip := "Recoil Lab: " label " | " this.SelectedProfile().Name " | " this.Gain
        target := this.Closing ? 0 : WinActive("ahk_exe " this.Config.TargetExe)
        this.Overlay.Update(target, status, this.Failed || zeroInput ? "FFD166" : (this.Engine.Armed ? "83E3B0" : "D9E2EC"))
    }

    SmokeQuickControls(sessionStart) {
        for binding in this.Hotkeys.Weapons {
            this.SelectWeapon(binding.ProfileIndex, true)
            if this.Failed || this.SelectedProfile().Name != binding.Profile || !this.Engine.Armed
                || this.Mode != "dry_run" || this.Engine.SessionStart != sessionStart
                throw Error("Smoke test: selecionar/ativar perfil alterou modo ou prazo da sessao.")
            generation := this.Engine.Generation
            this.SelectWeapon(binding.ProfileIndex, true)
            if this.Engine.Generation != generation
                throw Error("Smoke test: repetir a arma ativada nao foi idempotente.")
        }
        generation := this.Engine.Generation
        selectedIndex := this.ProfileIndex
        this.SelectWeapon(this.Hotkeys.Weapons[1].ProfileIndex, false)
        if this.Engine.Generation != generation || this.ProfileIndex != selectedIndex
            throw Error("Smoke test: atalho fora de foco alterou o perfil.")
        for index, entry in this.Config.Profiles {
            if entry.Name = "BerylM762" {
                this.SelectWeapon(index, true)
                break
            }
        }
        ; An isolated in-memory curve verifies that quick saving never flattens segments.
        profile := this.Config.Profiles[this.ProfileIndex]
        profile.Segments := [{UntilMs: 500, Dx: 0, Dy: 1}, {UntilMs: 3000, Dx: 1, Dy: 2}]
        this.GainInput.Value := 1
        this.ApplyControls()
        this.QuickAction("gain_up")
        if this.Gain != 1.1 || this.Engine.Armed || this.Mode != "dry_run"
            throw Error("Smoke test: aumento de ganho incorreto.")
        this.SelectWeapon(this.ProfileIndex, true)
        if this.Gain != 1.1 || !this.Engine.Armed
            throw Error("Smoke test: reativar a mesma arma descartou ganho aplicado nao salvo.")
        this.QuickAction("save_gain")
        reloaded := LabLoadCalibrations(ReadLabConfig(this.ConfigPath), this.CalibrationPath)
        saved := reloaded.Profiles[this.ProfileIndex]
        if this.Failed || saved.SavedGain != 1.1 || saved.Segments.Length != 2
            || saved.Segments[1].UntilMs != 500 || saved.Segments[2].Dx != 1 || saved.Segments[2].Dy != 2
            throw Error("Smoke test: salvar ganho alterou a curva.")
        this.QuickAction("gain_down")
        if this.Gain != 1 || this.Engine.Armed || this.Engine.SessionStart != sessionStart
            throw Error("Smoke test: reducao de ganho alterou limites de sessao.")
        profile.Segments[2].Dy := this.Config.MaxStep
        this.QuickAction("gain_up")
        if this.Gain != 1 || this.Engine.Armed || !InStr(this.LastFeedback, "recusado")
            throw Error("Smoke test: ganho saturado nao foi recusado.")
        profile.Segments[2].Dy := 1
        this.GainInput.Value := 0.1
        this.ApplyControls()
        this.QuickAction("gain_down")
        if this.Gain != 0.1 || this.Engine.Armed
            throw Error("Smoke test: limite inferior de ganho incorreto.")
        this.GainInput.Value := 5
        this.ApplyControls()
        this.QuickAction("gain_up")
        if this.Gain != 5 || this.Engine.Armed || this.Mode != "dry_run" || this.Engine.SessionStart != sessionStart
            throw Error("Smoke test: limite superior de ganho incorreto.")
    }

    ApplyControls(*) {
        if this.Failed || this.Closing
            return
        try {
            gain := LabNumber(this.GainInput.Value, "Ganho", 0.1, 5)
            LabValidateEffectiveProfile(this.Config.Profiles[this.ProfileChoice.Value], gain, this.Config.MaxStep)
        }
        catch as validationError {
            this.GainInput.Value := this.Gain
            this.ProfileChoice.Choose(this.ProfileIndex)
            this.ModeChoice.Choose(this.Mode = "dry_run" ? 1 : 2)
            this.ShowCalibrationFields()
            this.QuickFeedback(validationError.Message, true)
            return
        }
        try {
            this.RecordEvents(this.Engine.Disarm("configuration_changed", this.Logger.NowMs()))
            old := this.Engine
            this.Gain := gain
            this.ProfileIndex := this.ProfileChoice.Value
            this.Mode := this.ModeChoice.Value = 1 ? "dry_run" : "real_input"
            this.Engine := RecoilEngine(this.SelectedProfile(), this.Config)
            this.Engine.SessionStart := old.SessionStart
            this.Engine.Generation := old.Generation + 1
            this.Engine.BurstId := old.BurstId
            this.Logger.Record(LabEvent("configuration", "gain=" this.Gain ";motion=" this.Engine.Profile.MotionMode ";api=SendInput"), this.Mode,
                this.SelectedProfile().Name, this.Engine.Generation, false, false, false)
            this.Refresh()
        } catch as err {
            this.Fail(err)
        }
    }

    DeactivateKey(key, *) {
        try {
            this.SetEnabled(false)
            if !this.Failed && !this.Closing
                this.QuickFeedback("Compensacao DESARMADA.")
        } finally {
            KeyWait(key)
        }
    }

    SetEnabled(enabled) {
        if this.Failed || this.Closing
            return
        try {
            this.Logger.Record(LabEvent("activation_command", enabled ? "enable" : "disable"),
                this.Mode, this.SelectedProfile().Name, this.Engine.Generation,
                !!WinActive("ahk_exe " this.Config.TargetExe), GetKeyState("LButton", "P"), GetKeyState("RButton", "P"))
            if enabled && !this.Engine.Armed
                this.RecordEvents(this.Engine.Arm(this.Logger.NowMs()))
            else if !enabled
                this.RecordEvents(this.Engine.Disarm("manual_stop", this.Logger.NowMs()))
            this.Logger.Flush()
            this.Refresh()
        } catch as err {
            this.Fail(err)
        }
    }

    Toggle(*) {
        if this.Failed || this.Closing
            return
        try {
            if this.Engine.Armed
                this.RecordEvents(this.Engine.Disarm("manual_stop", this.Logger.NowMs()))
            else
                this.RecordEvents(this.Engine.Arm(this.Logger.NowMs()))
            this.Refresh()
        } catch as err {
            this.Fail(err)
        }
    }

    MarkKey(*) {
        this.Mark()
        KeyWait("F9")
    }

    Mark(*) {
        if this.Failed || this.Closing
            return
        try {
            this.Marker += 1
            this.Logger.Record(LabEvent("marker", "manual_" this.Marker), this.Mode, this.SelectedProfile().Name,
                this.Engine.Generation, !!WinActive("ahk_exe " this.Config.TargetExe),
                GetKeyState("LButton", "P"), GetKeyState("RButton", "P"))
        } catch as err {
            this.Fail(err)
        }
    }

    ProbeMovement(*) {
        if this.Failed || this.Closing || this.Mode != "real_input"
            return
        try {
            if !WinActive("ahk_exe " this.Config.TargetExe) || !GetKeyState("RButton", "P") || GetKeyState("LButton", "P")
                return
            this.RecordEvents(this.Engine.Disarm("input_probe", this.Logger.NowMs()))
            generation := this.Engine.Generation
            started := this.Logger.NowMs()
            sent := 0
            step := Min(5, this.Config.MaxStep)
            reason := "completed"
            this.Logger.Record(LabEvent("probe_start", "F10+RMB;max_pulses=10;dy=" step),
                "real_input", "InputProbe", generation, true, false, true)
            Loop 10 {
                Critical("On")
                try {
                    current := this.Logger.NowMs()
                    focused := !!WinActive("ahk_exe " this.Config.TargetExe)
                    left := GetKeyState("LButton", "P")
                    right := GetKeyState("RButton", "P")
                    trigger := GetKeyState("F10", "P")
                    if this.Closing || this.Failed || !LabCanProbe(this.Engine, generation, started, current,
                        sent, focused, left, right, trigger) {
                        reason := "interrupted"
                        break
                    }
                    event := LabEvent("probe_move")
                    event.Dy := step
                    event.RawDy := step
                    event.ElapsedMs := current - started
                    accepted := LabAttemptMovement(this.Logger, event, "real_input", "InputProbe", generation,
                        focused, left, right, LabSendMouse)
                    if accepted != 1
                        throw Error("SendInput rejeitou o teste de movimento.")
                    sent += 1
                } finally {
                    Critical("Off")
                }
                if A_Index < 10
                    Sleep(20)
            }
            this.Logger.Record(LabEvent("probe_end", reason ";sent=" sent), "real_input", "InputProbe",
                generation, !!WinActive("ahk_exe " this.Config.TargetExe), GetKeyState("LButton", "P"), GetKeyState("RButton", "P"))
            this.Logger.Flush()
            this.Refresh()
            this.QuickFeedback(this.Engine.Armed ? "Teste encerrado; ativacao mais recente preservada."
                : "Teste encerrado. Compensacao DESARMADA. " this.ActivationHint())
        } catch as err {
            this.Fail(err)
        } finally {
            KeyWait("F10")
        }
    }

    Poll() {
        if this.Closing || this.Failed
            return
        try {
            Critical("On")
            try {
                now := this.Logger.NowMs()
                focused := !!WinActive("ahk_exe " this.Config.TargetExe)
                left := GetKeyState("LButton", "P")
                right := GetKeyState("RButton", "P")
                engineUsed := this.Engine
                modeUsed := this.Mode
                profileUsed := this.SelectedProfile()
                events := engineUsed.Tick(now, focused, left, right)
                generation := engineUsed.Generation
            } finally {
                Critical("Off")
            }
            for event in events {
                if event.Kind = "move" && modeUsed = "real_input" && (event.Dx || event.Dy) {
                    accepted := 0
                    Critical("On")
                    try {
                        current := this.Logger.NowMs()
                        focused := !!WinActive("ahk_exe " this.Config.TargetExe)
                        left := GetKeyState("LButton", "P")
                        right := GetKeyState("RButton", "P")
                        allowed := LabCanSend(this.Engine, generation, now, current, event,
                            this.Config, profileUsed, focused, left, right)
                        if allowed {
                            accepted := LabAttemptMovement(this.Logger, event, modeUsed, profileUsed.Name,
                                generation, focused, left, right, LabSendMouse)
                        }
                    } finally {
                        Critical("Off")
                    }
                    if !allowed {
                        event.Reason := "cancelled_before_send"
                        this.Logger.Record(event, modeUsed, profileUsed.Name, generation, focused, left, right)
                        ; Drop only this stale/cancelled movement. The next Tick handles
                        ; button release, focus and deadlines without disabling a new activation.
                        break
                    }
                    if accepted != 1
                        throw Error("SendInput nao aceitou a entrada. O ensaio foi desarmado; consulte os logs.")
                } else {
                    this.Logger.Record(event, modeUsed, profileUsed.Name, generation, focused, left, right)
                    if this.Engine = engineUsed && this.Engine.Generation = generation
                        this.NotifyEvent(event)
                }
            }
            if now - this.LastHeartbeat >= 5000 {
                this.Logger.Record(LabEvent("heartbeat", "state=" this.Engine.State ";enabled=" this.Engine.Armed),
                    this.Mode, this.SelectedProfile().Name, this.Engine.Generation,
                    !!WinActive("ahk_exe " this.Config.TargetExe), GetKeyState("LButton", "P"), GetKeyState("RButton", "P"))
                this.LastHeartbeat := now
            }
            if now - this.LastFlush >= 1000 {
                this.Logger.Flush()
                this.LastFlush := now
            }
            if now - this.LastUi >= 200 {
                this.Refresh()
                this.LastUi := now
            }
        } catch as err {
            this.Fail(err)
        }
    }

    RecordEvents(events) {
        for event in events {
            this.Logger.Record(event, this.Mode, this.SelectedProfile().Name, this.Engine.Generation,
                !!WinActive("ahk_exe " this.Config.TargetExe), GetKeyState("LButton", "P"), GetKeyState("RButton", "P"))
            this.NotifyEvent(event)
        }
    }

    NotifyEvent(event) {
        if event.Kind = "paused" && event.Reason = "focus_lost"
            this.QuickFeedback("PAUSADO fora do jogo. Ao voltar, solte o gatilho para retomar.")
        else if event.Kind = "resumed"
            this.QuickFeedback("Jogo em foco. Solte o gatilho para retomar.")
        else if event.Kind = "session_expired"
            this.QuickFeedback("Sessao encerrada pelo prazo. Reinicie para um novo ensaio.", true)
    }

    Refresh() {
        state := this.DisplayState()
        this.StateText.Value := state " | " (this.Mode = "dry_run" ? "SIMULACAO" : "ENTRADA REAL")
        this.FeedbackText.Value := this.LastFeedback
        profile := this.SelectedProfile()
        description := (profile.MotionMode = "elapsed" ? "Referencia da taxa: " : "Intervalo solicitado: ")
            . profile.IntervalMs " ms | Ganho: " this.Gain
        originalProfile := this.Config.Profiles[this.ProfileIndex]
        statusName := originalProfile.RecoilStatus = "unmeasured" ? "PENDENTE (X/Y desconhecidos)"
            : originalProfile.RecoilStatus = "user_set_unvalidated" ? "AJUSTE SALVO - validar no ensaio" : "EXEMPLO SINTETICO"
        description .= "`r`nModo: " profile.TriggerMode " / " profile.MotionMode " | " statusName
        if !LabProfileHasMovement(profile)
            description .= "`r`nX/Y=0: sem movimento configurado; este perfil nao compensa recuo."
        description .= "`r`n" this.ActivationHint()
        if originalProfile.FireIntervalMs
            description .= "`r`nIntervalo ENTRE TIROS de referencia: " originalProfile.FireIntervalMs " ms (arredondado)"
        description .= "`r`nLimite por rajada: " this.Config.MaxBurstMs " ms | Sessao: " this.Config.SessionLimitMs / 1000 " s"
        for segment in profile.Segments
            description .= "`r`nAte " segment.UntilMs " ms: X=" segment.Dx ", Y=" segment.Dy
                . (profile.MotionMode = "elapsed" ? " por " profile.IntervalMs " ms de referencia" : " por passo")
        this.DetailText.Value := description
        this.UpdateStatus()
    }

    ShowPanel(*) {
        if !this.Closing {
            if !this.Failed {
                try this.RecordEvents(this.Engine.Disarm("panel_opened", this.Logger.NowMs()))
                catch as err
                    this.Fail(err)
            }
            this.Gui.Show()
            this.Refresh()
        }
    }

    OpenLogs(*) {
        this.ShowPanel()
        Run('explorer.exe "' this.Logger.Dir '"')
    }

    OpenConfig(*) {
        this.ShowPanel()
        Run('notepad.exe "' this.ConfigPath '"')
    }

    Fail(err) {
        if this.Failed
            return
        this.Failed := true
        this.Engine.Disarm("runtime_error", this.Logger.NowMs())
        if this.HasOwnProp("PollCallback")
            SetTimer(this.PollCallback, 0)
        try this.Logger.Flush()
        try {
            this.Logger.Record(LabEvent("error", err.Message), this.Mode, this.SelectedProfile().Name,
                this.Engine.Generation, false, false, false)
            this.Logger.Flush()
        }
        if this.Smoke
            throw err
        MsgBox("Ensaio interrompido: " err.Message "`n`nEncerre e reinicie depois de corrigir o problema.", "Recoil Lab", "Iconx")
        this.Refresh()
    }

    Quit(*) {
        ExitApp()
    }

    OnShutdown(reason, code) {
        if this.Closing
            return
        this.Closing := true
        events := this.Engine.Disarm("shutdown", this.Logger.NowMs())
        if this.HasOwnProp("PollCallback")
            SetTimer(this.PollCallback, 0)
        SetTimer(this.FeedbackCallback, 0)
        this.ClearFeedback()
        this.StatusGui.Destroy()
        try {
            this.RecordEvents(events)
            this.Logger.Close(reason ";exit_code=" code)
        } catch as err {
            try this.Logger.Flush()
            MsgBox("O envio foi interrompido, mas a gravacao final falhou: " err.Message,
                "Recoil Lab - logs incompletos", "Icon!")
        }
    }
}

LabStateLabel(state) {
    names := Map("disabled", "DESARMADO", "wait_release", "ARMADO - solte o gatilho",
        "ready", "ARMADO - aguardando disparo + mira", "burst", "RAJADA",
        "paused_focus", "PAUSADO - fora do jogo", "expired", "SESSAO ENCERRADA PELO LIMITE")
    return names.Has(state) ? names[state] : state
}

LabCanProbe(engine, generation, started, current, sent, focused, left, right, trigger) {
    return !engine.Armed && engine.Generation = generation && focused && !left && right && trigger
        && current >= started && current - started < 500 && sent >= 0 && sent < 10
}

LabCanSend(engine, generation, tickTime, current, event, limits, profile, focused, left, right) {
    return engine.Armed && engine.State = "burst" && engine.Generation = generation
        && focused && left && right && current >= tickTime && current - tickTime <= limits.MaxLateMs
        && current - engine.SessionStart < limits.SessionLimitMs
        && event.ElapsedMs + current - tickTime < Min(limits.MaxBurstMs, profile.Segments[-1].UntilMs)
}

LabSendMouse(dx, dy) {
    packet := LabMouseInput(dx, dy)
    return DllCall("user32\SendInput", "UInt", 1, "Ptr", packet.Ptr, "Int", packet.Size, "UInt")
}

LabAttemptMovement(logger, event, mode, profileName, generation, focused, left, right, sender) {
    logger.RequireCapacity()
    event.SendCallQpc := LabQpcTicks()
    accepted := sender.Call(event.Dx, event.Dy)
    event.SendReturnQpc := LabQpcTicks()
    event.OsInserted := accepted
    event.Reason := accepted = 1 ? "os_accepted_not_game_confirmed" : "os_rejected"
    logger.Record(event, mode, profileName, generation, focused, left, right, true)
    return accepted
}
