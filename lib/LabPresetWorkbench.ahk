#Include LabPresets.ahk
#Include LabCurvePreview.ahk

; Intent: compare a saved experiment and its context before selecting it.
; Native controls, 8px spacing, white plot, blue X / green Y, amber feedback.
; The catalog and tabs keep calibration details away from the compact game HUD.
class LabPresetWorkbench {
    __New(app) {
        this.App := app
        this.Dirty := false
        this.Loading := false
        this.Draft := LabNewPreset()
        this.School := LabReadSchool(A_ScriptDir "\references\school\school_presets.ini")
        this.Gui := Gui("+Owner" app.Gui.Hwnd " -DPIScale", "PUBG Input Lab - biblioteca de presets")
        this.Gui.SetFont("s" (10 * 96 / A_ScreenDPI), "Segoe UI")
        this.Gui.BackColor := "F3F5F7"
        this.Gui.AddText("x16 y12 w900 h24", "Biblioteca  /  contexto + curva + atalho")
        this.Gui.AddText("x16 y40 w220 h20", "Perfis salvos")
        this.Catalog := this.Gui.AddListBox("x16 y64 w220 h420")
        this.Catalog.OnEvent("Change", ObjBindMethod(this, "Choose"))
        this.Gui.AddButton("x16 y492 w68 h28", "Novo").OnEvent("Click", ObjBindMethod(this, "New"))
        this.Gui.AddButton("x88 y492 w76 h28", "Duplicar").OnEvent("Click", ObjBindMethod(this, "Duplicate"))
        this.Gui.AddButton("x168 y492 w68 h28", "Excluir").OnEvent("Click", ObjBindMethod(this, "Delete"))
        this.Tabs := this.Gui.AddTab3("x252 y40 w684 h480", ["Contexto", "Curva X/Y", "Atalhos e tela", "Referencias SCHOOL"])
        this.Tabs.UseTab(1)
        this.NameEdit := this.Field("Nome do preset", 272, 84, 640)
        this.WeaponEdit := this.Field("Arma", 272, 140, 200)
        this.OpticEdit := this.Field("Mira", 488, 140, 200, ["Padrao", "Aberta", "Red dot", "Holografica", "2x", "3x", "4x", "6x", "8x", "15x"])
        this.ZoomEdit := this.Field("Zoom em uso", 704, 140, 208)
        this.StanceEdit := this.Field("Postura selecionada", 272, 196, 200, ["Em pe", "Agachado", "Deitado"], true)
        this.AttachmentEdit := this.Field("Acessorios", 488, 196, 424)
        this.SensitivityEdit := this.Field("Sensibilidade / DPI / resolucao do ensaio", 272, 252, 640)
        this.GainEdit := this.Field("Ganho", 272, 308, 96)
        this.IntervalEdit := this.Field("Intervalo (ms)", 384, 308, 120)
        this.TriggerEdit := this.Field("Disparo", 520, 308, 184, ["Automatico", "Tiro unico"], true)
        this.MotionEdit := this.Field("Temporizacao", 720, 308, 192, ["Por tempo", "Por passo"], true)
        this.MinTriggerEdit := this.Field("Minimo entre cliques (ms)", 272, 364, 200)
        this.SourceText := this.Gui.AddEdit("x488 y380 w424 h76 ReadOnly")
        this.Gui.AddText("x272 y464 w640 h38", "Contexto selecionado manualmente. Alterar mira/postura identifica outra configuracao; nao aplica um multiplicador universal.")
        this.Tabs.UseTab(2)
        this.CurveList := this.Gui.AddListView("x272 y84 w640 h146 -Multi NoSortHdr", ["Fim acumulado (ms)", "X", "Y"])
        this.CurveList.ModifyCol(1, 220)
        this.CurveList.ModifyCol(2, 190)
        this.CurveList.ModifyCol(3, 190)
        this.CurveList.OnEvent("ItemSelect", ObjBindMethod(this, "CurveSelected"))
        this.EndEdit := this.Field("Fim (ms)", 272, 240, 120)
        this.XEdit := this.Field("X", 408, 240, 96)
        this.YEdit := this.Field("Y", 520, 240, 96)
        this.Gui.AddButton("x632 y256 w88 h28", "Adicionar").OnEvent("Click", ObjBindMethod(this, "CurveAction", "add"))
        this.Gui.AddButton("x728 y256 w88 h28", "Alterar").OnEvent("Click", ObjBindMethod(this, "CurveAction", "edit"))
        this.Gui.AddButton("x824 y256 w88 h28", "Remover").OnEvent("Click", ObjBindMethod(this, "CurveAction", "delete"))
        this.Preview := this.Gui.AddPicture("x272 y300 w640 h150")
        this.CurveInfo := this.Gui.AddText("x272 y460 w640 h44", "X azul / Y verde. Deslocamento por intervalo; eixo horizontal = tempo. A previa nao representa o spray observado no jogo.")
        this.Tabs.UseTab(3)
        this.Gui.AddText("x272 y84 w640 h42", "Ctrl+Alt+D permanece reservado para parar. Uma letra seleciona e ativa um perfil salvo. Troque a associacao para usar uma variante de mira/postura.")
        this.KeyList := this.Gui.AddListView("x272 y132 w640 h160 -Multi NoSortHdr", ["Perfil", "Ctrl+Alt+letra"])
        this.KeyList.ModifyCol(1, 450)
        this.KeyList.ModifyCol(2, 160)
        this.KeyProfile := this.Field("Perfil salvo", 272, 308, 432, [], true)
        this.KeyLetter := this.Field("A-Z / 1-9", 720, 308, 96)
        this.Gui.AddButton("x824 y324 w88 h28", "Associar").OnEvent("Click", ObjBindMethod(this, "BindKey"))
        this.Gui.AddButton("x272 y368 w200 h28", "Remover atalho selecionado").OnEvent("Click", ObjBindMethod(this, "RemoveKey"))
        this.DotCheck := this.Gui.AddCheckbox("x272 y420 w300 h24", "Ponto central (Ctrl+Alt+0)")
        this.DotSize := this.Field("Tamanho (3-9 px)", 592, 404, 136)
        this.DotColor := this.Field("Cor hexadecimal", 744, 404, 168)
        this.Gui.AddButton("x272 y464 w200 h28", "Salvar opcoes visuais").OnEvent("Click", ObjBindMethod(this, "SaveDisplay"))
        this.Tabs.UseTab(4)
        this.Gui.AddText("x272 y84 w640 h54", "26 referencias de FDCaffeine (MIT). Valores externos, nao validados para sua configuracao. O intervalo solicitado de 1 ms nao mede o intervalo real.")
        names := []
        for entry in this.School
            names.Push(entry.Name)
        this.SchoolWeapon := this.Field("Arma de referencia", 272, 148, 300, names, true)
        this.SchoolStance := this.Field("Postura", 592, 148, 320, ["Em pe", "Agachado", "Deitado"], true)
        this.SchoolInterval := this.Field("Intervalo assumido (ms)", 272, 212, 200)
        this.SchoolScale := this.Field("Escala de importacao", 488, 212, 200)
        this.SchoolDuration := this.Field("Duracao (ms)", 704, 212, 208)
        this.SchoolInterval.Value := "16"
        this.SchoolScale.Value := "0.1"
        this.SchoolDuration.Value := "3000"
        this.SchoolWeapon.Choose(1)
        this.SchoolStance.Choose(1)
        this.Gui.AddButton("x272 y284 w280 h32", "Converter em rascunho").OnEvent("Click", ObjBindMethod(this, "ConvertSchool"))
        this.Gui.AddText("x272 y340 w640 h120", "A conversao reconstrói a progressao vertical e registra intervalo assumido e escala. 16 ms e 0.1 sao hipoteses editaveis, nao valores medidos.`n`nRevise a curva e o contexto antes de salvar. Valores acima do limite sao rejeitados. A biblioteca original e sua licenca acompanham o projeto.")
        this.Tabs.UseTab()
        this.Notice := this.Gui.AddText("x16 y532 w920 h36 c815C12", "")
        this.Gui.AddButton("x16 y576 w104 h32", "Importar INI").OnEvent("Click", ObjBindMethod(this, "Import"))
        this.Gui.AddButton("x128 y576 w104 h32", "Exportar INI").OnEvent("Click", ObjBindMethod(this, "Export"))
        this.Gui.AddButton("x488 y576 w200 h32", "Salvar preset").OnEvent("Click", ObjBindMethod(this, "Save"))
        this.Gui.AddButton("x704 y576 w232 h32", "Usar perfil salvo").OnEvent("Click", ObjBindMethod(this, "Use"))
        this.Gui.OnEvent("Close", ObjBindMethod(this, "Close"))
        this.Gui.OnEvent("Escape", ObjBindMethod(this, "Close"))
        for control in [this.NameEdit, this.WeaponEdit, this.OpticEdit, this.ZoomEdit,
            this.StanceEdit, this.AttachmentEdit, this.SensitivityEdit, this.GainEdit,
            this.IntervalEdit, this.TriggerEdit, this.MotionEdit, this.MinTriggerEdit]
            control.OnEvent("Change", ObjBindMethod(this, "Changed"))
        this.RefreshCatalog(app.Config.Profiles[app.ProfileIndex].Name)
    }

    Field(label, x, y, width, choices := unset, fixed := false) {
        this.Gui.AddText("x" x " y" y " w" width " h18", label)
        options := "x" x " y" (y + 20) " w" width
        return IsSet(choices) ? this.Gui.Add(fixed ? "DropDownList" : "ComboBox", options, choices)
            : this.Gui.AddEdit(options " h24")
    }

    Changed(*) {
        if !this.Loading {
            this.Dirty := true
            this.Notice.Value := "Rascunho alterado. Salve para atualizar o perfil; a selecao em uso permanece desarmada."
        }
    }

    AllowDiscard() {
        return !this.Dirty || (!this.App.Smoke && MsgBox("Descartar as alteracoes deste rascunho?", "Biblioteca", "YesNo Icon?") = "Yes")
    }

    Show(*) {
        this.App.SetEnabled(false)
        this.Gui.Show("w952 h624")
    }

    Close(*) {
        if this.AllowDiscard() {
            this.Dirty := false
            this.Gui.Hide()
        }
    }

    RefreshCatalog(selected := "") {
        labels := []
        selectedIndex := 1
        for index, profile in this.App.Config.Profiles {
            labels.Push(profile.Label)
            if profile.Name = selected
                selectedIndex := index
        }
        this.Catalog.Delete()
        this.Catalog.Add(labels)
        this.Catalog.Choose(selectedIndex)
        this.KeyProfile.Delete()
        this.KeyProfile.Add(labels)
        this.KeyProfile.Choose(selectedIndex)
        this.RefreshKeys()
        this.Load(this.App.Config.Profiles[selectedIndex])
    }

    Choose(*) {
        if !this.AllowDiscard() {
            for index, profile in this.App.Config.Profiles {
                if profile.Name = this.Draft.Name
                    this.Catalog.Choose(index)
            }
            return
        }
        if this.Catalog.Value
            this.Load(this.App.Config.Profiles[this.Catalog.Value])
    }

    Load(profile) {
        this.Loading := true
        try {
            this.Draft := LabClonePreset(profile)
            this.NameEdit.Value := this.Draft.Label
            this.WeaponEdit.Value := this.Draft.Weapon
            this.OpticEdit.Text := this.Draft.Optic
            this.ZoomEdit.Value := this.Draft.Zoom
            this.StanceEdit.Choose(this.Draft.Stance)
            this.AttachmentEdit.Value := this.Draft.Attachments
            this.SensitivityEdit.Value := this.Draft.Sensitivity
            this.GainEdit.Value := this.Draft.SavedGain
            this.IntervalEdit.Value := this.Draft.IntervalMs
            this.TriggerEdit.Choose(this.Draft.TriggerMode = "continuous" ? 1 : 2)
            this.MotionEdit.Choose(this.Draft.MotionMode = "elapsed" ? 1 : 2)
            this.MinTriggerEdit.Value := this.Draft.MinTriggerMs
            this.SourceText.Value := (this.Draft.RecoilStatus = "external_unvalidated" ? "Referencia externa - nao validada"
                : "Ajuste de ensaio - nao validado") "`r`nOrigem: " this.Draft.Source
            this.DotCheck.Value := this.App.Preferences.ReticleEnabled
            this.DotSize.Value := this.App.Preferences.ReticleSize
            this.DotColor.Value := this.App.Preferences.ReticleColor
            this.UpdateCurve()
            this.Dirty := false
            this.Notice.Value := SubStr(this.Draft.Name, 1, 5) = "User_" ? "Preset local. Salvar preserva todos os segmentos."
                : "Perfil original protegido. Ao salvar, sera criada uma copia na biblioteca."
        } finally this.Loading := false
    }

    ReadDraft(validate := true) {
        profile := LabClonePreset(this.Draft)
        profile.Label := Trim(this.NameEdit.Value)
        profile.Weapon := Trim(this.WeaponEdit.Value)
        profile.Optic := Trim(this.OpticEdit.Text)
        profile.Zoom := Trim(this.ZoomEdit.Value)
        profile.Stance := this.StanceEdit.Text
        profile.Attachments := Trim(this.AttachmentEdit.Value)
        profile.Sensitivity := Trim(this.SensitivityEdit.Value)
        profile.SavedGain := LabNumber(this.GainEdit.Value, "Ganho", 0.1, 5)
        profile.IntervalMs := LabNumber(this.IntervalEdit.Value, "Intervalo", 10, 1000, true)
        profile.TriggerMode := this.TriggerEdit.Value = 1 ? "continuous" : "single"
        profile.MotionMode := this.MotionEdit.Value = 1 ? "elapsed" : "step"
        profile.MinTriggerMs := LabNumber(this.MinTriggerEdit.Value, "Minimo entre cliques", 0, 1000, true)
        if SubStr(profile.Name, 1, 5) != "User_" {
            profile.Name := "User_" LabQpcTicks()
            profile.RecoilStatus := "user_set_unvalidated"
            profile.Source := "Copia local de " this.Draft.Name
        }
        if validate
            LabValidatePreset(profile, this.App.Config.MaxStep)
        return profile
    }

    Save(*) {
        try {
            profile := this.ReadDraft()
            entries := this.App.Library.Clone()
            replaced := false
            for index, saved in entries {
                if saved.Name = profile.Name {
                    entries[index] := profile
                    replaced := true
                    break
                }
            }
            if !replaced
                entries.Push(profile)
            this.App.ApplyLibrary(entries, profile.Name)
            this.RefreshCatalog(profile.Name)
            this.Notice.Value := "Preset salvo com backup. Associar um atalho permite selecionar esta combinacao no jogo."
        } catch as err {
            this.Notice.Value := err.Message
        }
    }

    New(*) {
        if this.AllowDiscard() {
            this.Load(LabNewPreset())
            this.Dirty := true
            this.Tabs.Choose(1)
        }
    }

    Duplicate(*) {
        try {
            profile := this.ReadDraft()
            profile.Name := "User_" LabQpcTicks()
            profile.Label := SubStr(profile.Label, 1, 145) " (copia)"
            this.Load(profile)
            this.Dirty := true
            this.Notice.Value := "Copia em rascunho. Altere contexto e nome, depois salve."
        } catch as err {
            this.Notice.Value := err.Message
        }
    }

    Delete(*) {
        try {
            if SubStr(this.Draft.Name, 1, 5) != "User_"
                throw Error("Perfis originais nao sao excluidos pela biblioteca.")
            if this.App.Hotkeys.ByProfile.Has(this.Draft.Name)
                throw Error("Remova ou altere o atalho deste preset antes de excluir.")
            if !this.App.Smoke && MsgBox("Excluir o preset salvo '" this.Draft.Label "'?", "Biblioteca", "YesNo Icon?") != "Yes"
                return
            entries := []
            for profile in this.App.Library {
                if profile.Name != this.Draft.Name
                    entries.Push(profile)
            }
            this.App.ApplyLibrary(entries, this.App.BaseProfiles[1].Name)
            this.RefreshCatalog()
            this.Notice.Value := "Preset removido. A revisao anterior esta no arquivo .bak."
        } catch as err {
            this.Notice.Value := err.Message
        }
    }

    Use(*) {
        if this.Dirty {
            this.Notice.Value := "Salve o rascunho antes de usar."
            return
        }
        for index, profile in this.App.Config.Profiles {
            if profile.Name = this.Draft.Name {
                this.App.ProfileChoice.Choose(index)
                this.App.ProfileChanged()
                this.Gui.Hide()
                this.App.ShowPanel()
                return
            }
        }
        this.Notice.Value := "Este rascunho ainda nao foi salvo."
    }

    UpdateCurve() {
        this.CurveList.Delete()
        for segment in this.Draft.Segments
            this.CurveList.Add(, segment.UntilMs, Format("{:g}", segment.Dx), Format("{:g}", segment.Dy))
        this.Preview.Value := "HBITMAP:" LabCurveBitmap(this.Draft, 640, 150)
        this.EndEdit.Value := this.Draft.Segments[-1].UntilMs
        this.XEdit.Value := Format("{:g}", this.Draft.Segments[-1].Dx)
        this.YEdit.Value := Format("{:g}", this.Draft.Segments[-1].Dy)
        this.CurveInfo.Value := "X azul / Y verde | duracao " this.Draft.Segments[-1].UntilMs " ms | ganho " Format("{:g}", this.Draft.SavedGain)
            . "`nDeslocamento por intervalo. Escala vertical automatica; esta previa nao mede o spray no jogo."
    }

    CurveSelected(control, item, selected) {
        if !selected || item > this.Draft.Segments.Length
            return
        segment := this.Draft.Segments[item]
        this.EndEdit.Value := segment.UntilMs
        this.XEdit.Value := Format("{:g}", segment.Dx)
        this.YEdit.Value := Format("{:g}", segment.Dy)
    }

    CurveAction(action, *) {
        try {
            candidate := this.ReadDraft(false)
            row := this.CurveList.GetNext()
            if action != "add" && !row
                throw Error("Selecione uma linha da curva.")
            if action = "delete" {
                if candidate.Segments.Length = 1
                    throw Error("Mantenha pelo menos um segmento.")
                candidate.Segments.RemoveAt(row)
            } else {
                segment := {UntilMs: LabNumber(this.EndEdit.Value, "Fim", 1, 10000, true),
                    Dx: LabNumber(this.XEdit.Value, "X", -this.App.Config.MaxStep, this.App.Config.MaxStep),
                    Dy: LabNumber(this.YEdit.Value, "Y", -this.App.Config.MaxStep, this.App.Config.MaxStep)}
                if action = "add"
                    candidate.Segments.Push(segment)
                else
                    candidate.Segments[row] := segment
            }
            LabValidatePreset(candidate, this.App.Config.MaxStep)
            this.Draft.Segments := candidate.Segments
            this.Draft.SavedGain := candidate.SavedGain
            this.UpdateCurve()
            this.Changed()
        } catch as err {
            this.Notice.Value := err.Message
        }
    }

    RefreshKeys() {
        this.KeyList.Delete()
        this.KeyNames := []
        for binding in this.App.Hotkeys.Weapons {
            this.KeyList.Add(, this.App.Config.Profiles[binding.ProfileIndex].Label, StrUpper(binding.Key))
            this.KeyNames.Push(binding.Profile)
        }
    }

    BindKey(*) {
        try {
            if !this.KeyProfile.Value
                throw Error("Selecione um perfil salvo.")
            name := this.App.Config.Profiles[this.KeyProfile.Value].Name
            key := StrUpper(Trim(this.KeyLetter.Value))
            text := "[Weapons]`n"
            for binding in this.App.Hotkeys.Weapons {
                if binding.Profile != name {
                    if StrUpper(binding.Key) = key
                        throw Error("Letra em uso por " binding.Profile ". Remova essa associacao antes de trocar.")
                    text .= binding.Profile "=" StrUpper(binding.Key) "`n"
                }
            }
            text .= name "=" key "`n"
            this.App.ApplyHotkeyText(text)
            this.RefreshKeys()
            this.Notice.Value := "Atalho salvo e aplicado. Ctrl+Alt+D continua sendo a parada global."
        } catch as err {
            this.Notice.Value := err.Message
        }
    }

    RemoveKey(*) {
        try {
            row := this.KeyList.GetNext()
            if !row
                throw Error("Selecione uma associacao.")
            name := this.KeyNames[row]
            text := "[Weapons]`n"
            for binding in this.App.Hotkeys.Weapons {
                if binding.Profile != name
                    text .= binding.Profile "=" StrUpper(binding.Key) "`n"
            }
            this.App.ApplyHotkeyText(text)
            this.RefreshKeys()
            this.Notice.Value := "Associacao removida; perfil preservado."
        } catch as err {
            this.Notice.Value := err.Message
        }
    }

    SaveDisplay(*) {
        try {
            prefs := {ReticleEnabled: this.DotCheck.Value, ReticleSize: this.DotSize.Value, ReticleColor: Trim(this.DotColor.Value)}
            this.App.SavePreferences(prefs)
            this.Notice.Value := "Ponto salvo. Visivel somente com o jogo em foco e geometria estavel."
        } catch as err {
            this.Notice.Value := err.Message
        }
    }

    ConvertSchool(*) {
        if !this.AllowDiscard()
            return
        try {
            converted := LabConvertSchool(this.School[this.SchoolWeapon.Value], this.SchoolStance.Text,
                this.SchoolInterval.Value, this.SchoolScale.Value, this.SchoolDuration.Value, this.App.Config.MaxStep)
            this.Load(converted)
            this.Dirty := true
            this.Tabs.Choose(2)
            this.Notice.Value := "Referencia convertida em rascunho; origem, escala e tempo registrados. Revise antes de salvar."
        } catch as err {
            this.Notice.Value := err.Message
        }
    }

    Import(*) {
        if !this.AllowDiscard()
            return
        path := FileSelect(1, , "Importar biblioteca", "Biblioteca INI (*.ini)")
        if path = ""
            return
        try {
            entries := LabImportPresets(this.App.Library, LabReadLibrary(path, this.App.Config.MaxStep), this.App.Config.MaxStep)
            this.App.ApplyLibrary(entries, entries.Length ? entries[-1].Name : this.App.BaseProfiles[1].Name)
            this.RefreshCatalog(entries.Length ? entries[-1].Name : "")
            this.Notice.Value := "Importacao concluida. IDs repetidos foram copiados sem substituir os existentes."
        } catch as err {
            this.Notice.Value := err.Message
        }
    }

    Export(*) {
        if this.Dirty {
            this.Notice.Value := "Salve o preset antes de exportar."
            return
        }
        path := FileSelect("S16", "preset.ini", "Exportar preset selecionado", "Biblioteca INI (*.ini)")
        if path = ""
            return
        try {
            LabWriteLibrary(path, [this.ReadDraft()], this.App.Config.MaxStep)
            this.Notice.Value := "Preset exportado com contexto, origem e curva. Revise dados pessoais antes de compartilhar."
        } catch as err {
            this.Notice.Value := err.Message
        }
    }
}
