#Include LabStatusOverlay.ahk
#Include LabConfig.ahk

class LabReticle extends LabStatusOverlay {
    __New() {
        this.Gui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20 +E0x08000000", "Recoil Lab - ponto")
        this.Gui.BackColor := "E85D6A"
        this.Shown := false
        this.PendingKey := ""
        this.StableSince := 0
        this.Color := "E85D6A"
        this.Size := 5
    }

    Update(target, enabled, size := 5, color := "E85D6A", now := A_TickCount) {
        if !enabled || !target {
            this.Hide()
            return
        }
        size := LabNumber(size, "Tamanho do ponto", 3, 9, true)
        if !RegExMatch(color, "^[A-Fa-f0-9]{6}$")
            throw Error("Cor do ponto invalida.")
        if this.Color != color || this.Size != size {
            this.Hide()
            this.Gui.BackColor := color
            this.Color := color
            this.Size := size
        }
        try {
            if !DllCall("IsWindowVisible", "Ptr", target, "Int") || WinGetMinMax(target) = -1 {
                this.Hide()
                return
            }
            WinGetClientPos(&x, &y, &w, &h, target)
            this.Place(target, LabReticleBounds(x, y, w, h, size), now)
        } catch TargetError {
            this.Hide()
        }
    }
}

LabReticleBounds(x, y, w, h, size) {
    if w < 320 || h < 180
        return 0
    return {X: x + (w - size) // 2, Y: y + (h - size) // 2, W: size, H: size,
        Key: x "," y "," w "," h "," size}
}
