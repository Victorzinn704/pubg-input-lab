; Native Windows panel for quick between-session selection.
; Domain: weapon, stance, curve, trial, source. Palette: paper F3F5F7,
; graphite 263442, muted steel 526273, amber 815C12, blue 245A81, green 25734C.
; Signature: weapon -> variant -> explicit readiness. Replaces the flat catalog,
; mixed calibration controls and wall of logs with three purpose-specific tabs.
; Intent: select confidently, see the exact active variant, then return to the game.
; Depth: subtle surface shifts; native controls preserve keyboard navigation.
; Typography: Segoe UI, 10pt body / 15pt title; spacing on an 8px grid.
class LabMainPanel {
    static Build(app) {
        ; Stable title is also the existing-instance notification endpoint.
        app.Gui := Gui(, "Recoil Lab - ensaio instrumentado")
        app.Gui.SetFont("s10 c263442", "Segoe UI")
        app.Gui.BackColor := "F3F5F7"
        app.Gui.MarginX := 24
        app.Gui.MarginY := 16
        app.Gui.SetFont("s15 Bold")
        app.Gui.AddText("x24 y16 w570 h28", "Recoil Lab")
        app.Gui.SetFont("s9 Norm c526273")
        app.Gui.AddText("x24 y48 w570 h20", "PUBG Input Lab | versao 1.5.0 | perfis e ensaios")
        app.Gui.SetFont("s10 c263442")
        app.StateText := app.Gui.AddText("x24 y80 w570 h24", "DESARMADO")
        app.FeedbackText := app.Gui.AddText("x24 y108 w570 h38 c815C12", "")
        app.PanelTabs := app.Gui.AddTab3("x16 y152 w588 h416", ["Usar", "Ajustar", "Diagnostico"])
        app.PanelTabs.UseTab(1)
        app.Gui.AddText("x32 y192 w552 h20", "Arma / modo de disparo")
        app.WeaponChoice := app.Gui.AddDropDownList("x32 y216 w552", [])
        app.WeaponChoice.OnEvent("Change", ObjBindMethod(app, "WeaponChoiceChanged"))
        app.Gui.AddText("x32 y256 w552 h20", "Variante salva")
        app.VariantChoice := app.Gui.AddDropDownList("x32 y280 w552", [])
        app.VariantChoice.OnEvent("Change", ObjBindMethod(app, "VariantChoiceChanged"))
        app.ProfileChoice := app.Gui.AddDropDownList("x32 y280 w552 Hidden", [])
        app.ProfileSummary := app.Gui.AddText("x32 y328 w552 h120", "")
        app.ToggleButton := app.Gui.AddButton("x32 y464 w264 h32", "Armar perfil")
        app.ToggleButton.OnEvent("Click", ObjBindMethod(app, "Toggle"))
        app.Gui.AddButton("x312 y464 w272 h32", "Editar na biblioteca").OnEvent("Click", ObjBindMethod(app, "OpenLibrary"))
        app.Gui.AddText("x32 y512 w552 h38 c526273", "No jogo: Ctrl+. / Ctrl+, alternam variantes. Ctrl+Alt+D desliga.`nF6 abre este painel e desarma; F3/F4 ajustam ganho; F5 salva.")
        app.PanelTabs.UseTab(2)
        app.Gui.AddText("x32 y192 w552 h20", "Modo de execucao")
        app.ModeChoice := app.Gui.AddDropDownList("x32 y216 w552 Choose" (app.Mode = "dry_run" ? 1 : 2),
            ["Simulacao - registrar sem mover", "Entrada real - ensaio com movimento"])
        app.ModeChoice.OnEvent("Change", ObjBindMethod(app, "ApplyControls"))
        app.Gui.AddText("x32 y264 w552 h20", "Ganho do perfil selecionado (0.1 a 5)")
        app.GainInput := app.Gui.AddEdit("x32 y288 w112 h28", app.Gain)
        app.Gui.AddButton("x160 y288 w192 h28", "Aplicar ganho").OnEvent("Click", ObjBindMethod(app, "ApplyControls"))
        app.Gui.AddButton("x368 y288 w216 h28", "Salvar ganho (F5)").OnEvent("Click", (*) => app.QuickAction("save_gain"))
        app.CalibrationHint := app.Gui.AddText("x32 y336 w552 h44", "")
        app.Gui.AddText("x32 y392 w24 h24", "X")
        app.CalibrationX := app.Gui.AddEdit("x64 y388 w80 h28", "0")
        app.Gui.AddText("x160 y392 w24 h24", "Y")
        app.CalibrationY := app.Gui.AddEdit("x192 y388 w80 h28", "0")
        app.Gui.AddButton("x288 y388 w296 h28", "Salvar ajuste constante").OnEvent("Click", ObjBindMethod(app, "SaveConstantFromPanel"))
        app.Gui.AddButton("x32 y448 w264 h32", "Editar curva e contexto").OnEvent("Click", ObjBindMethod(app, "OpenLibrary"))
        app.Gui.AddButton("x312 y448 w272 h32", "Criar variante por tempo").OnEvent("Click", ObjBindMethod(app, "CreateTimelineVariant"))
        app.Gui.AddText("x32 y504 w552 h42 c526273", "Alterar ajustes desarma o perfil. A biblioteca preserva curvas completas;`nX/Y acima servem apenas para ajustes constantes.")
        app.PanelTabs.UseTab(3)
        app.DetailText := app.Gui.AddEdit("x32 y192 w552 h244 ReadOnly -Wrap", "")
        app.Gui.AddButton("x32 y452 w168 h32", "Abrir logs").OnEvent("Click", ObjBindMethod(app, "OpenLogs"))
        app.Gui.AddButton("x216 y452 w176 h32", "Marcar evento (F9)").OnEvent("Click", ObjBindMethod(app, "Mark"))
        app.Gui.AddButton("x408 y452 w176 h32", "Configuracao base").OnEvent("Click", ObjBindMethod(app, "OpenConfig"))
        app.SessionText := app.Gui.AddText("x32 y500 w552 h48 c526273", "Sessao: " app.Logger.SessionId)
        app.PanelTabs.UseTab()
        app.Gui.AddText("x24 y584 w384 h36 c526273", "Alvo: " app.Config.TargetExe " | disparo + mira pressionados`nPerfil salvo nao equivale a resultado medido.")
        app.Gui.AddButton("x432 y584 w160 h32", "Encerrar (F12)").OnEvent("Click", ObjBindMethod(app, "Quit"))
        app.Gui.OnEvent("Close", ObjBindMethod(app, "Quit"))
        app.Gui.OnEvent("Escape", ObjBindMethod(app, "ShowPanel"))
        app.RefreshProfileChoices()
        app.ShowCalibrationFields()
    }
}
