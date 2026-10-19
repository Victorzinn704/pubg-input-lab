class LabStatusOverlay {
    __New() {
        this.Gui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20 +E0x08000000", "Recoil Lab - estado")
        this.Gui.BackColor := "18212B"
        this.Gui.MarginX := 0
        this.Gui.MarginY := 0
        ; Keep a compact font even when the desktop uses enlarged text scaling.
        this.Gui.SetFont("s" (9 * 96 / A_ScreenDPI) " cD9E2EC", "Segoe UI")
        this.Label := this.Gui.AddText("x8 y5 w264 h17 +0x4000 -Wrap", "DESARMADO")
        this.Shown := false
        this.PendingKey := ""
        this.StableSince := 0
        this.Color := ""
        WinSetTransparent(205, this.Gui)
    }

    Update(target, caption, color, now := A_TickCount) {
        if this.Label.Value != caption
            this.Label.Value := caption
        if this.Color != color {
            this.Label.SetFont("c" color)
            this.Color := color
        }
        try {
            if !target || !DllCall("IsWindowVisible", "Ptr", target, "Int") || WinGetMinMax(target) = -1 {
                this.Hide()
                return
            }
            WinGetClientPos(&x, &y, &width, &height, target)
            monitor := DllCall("MonitorFromWindow", "Ptr", target, "UInt", 2, "Ptr")
            info := Buffer(40, 0)
            NumPut("UInt", info.Size, info)
            if !DllCall("GetMonitorInfoW", "Ptr", monitor, "Ptr", info, "Int") {
                this.Hide()
                return
            }
            rect := LabOverlayBounds(x, y, width, height,
                NumGet(info, 4, "Int"), NumGet(info, 8, "Int"), NumGet(info, 12, "Int"), NumGet(info, 16, "Int"))
            this.Place(target, rect, now)
        } catch TargetError {
            ; A window can disappear between the focus check and geometry read.
            this.Hide()
        }
    }

    Place(target, rect, now) {
        if !target || !rect {
            this.Hide()
            return
        }
        key := target "|" rect.Key
        if this.PendingKey != key {
            this.Hide()
            this.PendingKey := key
            this.StableSince := now
            return
        }
        ; Hide during launch/resolution changes instead of flashing at the old position.
        if now - this.StableSince < 300
            return
        if !this.Shown {
            this.Gui.Show("NA x" rect.X " y" rect.Y " w" rect.W " h" rect.H)
            this.Shown := true
        }
    }

    Hide() {
        if this.Shown
            this.Gui.Hide()
        this.Shown := false
        this.PendingKey := ""
        this.StableSince := 0
    }

    Destroy() {
        this.Gui.Destroy()
    }
}

LabOverlayBounds(x, y, width, height, screenLeft, screenTop, screenRight, screenBottom) {
    if width < 320 || height < 180
        return 0
    left := Max(x, screenLeft)
    top := Max(y, screenTop)
    right := Min(x + width, screenRight)
    bottom := Min(y + height, screenBottom)
    if right - left < 304 || bottom - top < 50
        return 0
    return {X: left + 12, Y: top + 12, W: 280, H: 26,
        Key: x "," y "," width "," height "," left "," top "," right "," bottom}
}
