#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include ..\lib\LabStatusOverlay.ahk

try {
    overlayTestCount := RunOverlayTests()
    FileAppend("PASS: " overlayTestCount " overlay assertions; synthetic windows, no hooks or input.`n", "*")
    ExitApp(0)
} catch as overlayTestError {
    FileAppend("FAIL: " overlayTestError.Message " | line " overlayTestError.Line "`n" overlayTestError.Stack "`n", "**")
    ExitApp(1)
}

RunOverlayTests() {
    assertions := 0
    DetectHiddenWindows(true)
    small := LabOverlayBounds(150, 250, 640, 480, 0, 0, 1920, 1080)
    OverlayAssertRect(small, 162, 262, "Small client", &assertions)
    full := LabOverlayBounds(0, 0, 1920, 1080, 0, 0, 1920, 1080)
    OverlayAssertRect(full, 12, 12, "Full client", &assertions)
    OverlayAssert(small.Key != full.Key, "Resize must change the geometry key", &assertions)

    moved := LabOverlayBounds(250, 350, 640, 480, 0, 0, 1920, 1080)
    OverlayAssertRect(moved, 262, 362, "Moved client", &assertions)
    OverlayAssert(small.Key != moved.Key, "Movement must change the geometry key", &assertions)
    same := LabOverlayBounds(150, 250, 640, 480, 0, 0, 1920, 1080)
    OverlayAssert(small.Key = same.Key, "Equal geometry must have a stable key", &assertions)

    minimum := LabOverlayBounds(20, 30, 320, 180, 0, 0, 1920, 1080)
    OverlayAssertRect(minimum, 32, 42, "Minimum client", &assertions)
    OverlayAssert(!LabOverlayBounds(0, 0, 319, 480, 0, 0, 1920, 1080),
        "A client narrower than 320 must be hidden", &assertions)
    OverlayAssert(!LabOverlayBounds(0, 0, 640, 179, 0, 0, 1920, 1080),
        "A client shorter than 180 must be hidden", &assertions)
    OverlayAssert(!LabOverlayBounds(0, 0, 0, 0, 0, 0, 1920, 1080),
        "An empty client must be hidden", &assertions)
    OverlayAssert(!LabOverlayBounds(1820, 20, 640, 480, 0, 0, 1920, 1080),
        "Insufficient visible width must be hidden", &assertions)
    OverlayAssert(!LabOverlayBounds(20, 1060, 640, 480, 0, 0, 1920, 1080),
        "Insufficient visible height must be hidden", &assertions)
    OverlayAssert(!LabOverlayBounds(2000, 20, 640, 480, 0, 0, 1920, 1080),
        "A client outside the monitor must be hidden", &assertions)

    negative := LabOverlayBounds(-1900, 20, 640, 480, -1920, 0, 0, 1080)
    OverlayAssertRect(negative, -1888, 32, "Negative-coordinate monitor", &assertions)
    clipped := LabOverlayBounds(-2000, -40, 640, 480, -1920, 0, 0, 1080)
    OverlayAssertRect(clipped, -1908, 12, "Client clipped to monitor", &assertions)
    clippedMoved := LabOverlayBounds(-1990, -40, 640, 480, -1920, 0, 0, 1080)
    OverlayAssert(clipped.X = clippedMoved.X && clipped.Y = clippedMoved.Y,
        "Clipped movement may preserve the visible anchor", &assertions)
    OverlayAssert(clipped.Key != clippedMoved.Key,
        "The key must detect client movement even when the visible anchor is unchanged", &assertions)

    targetOne := 0
    targetTwo := 0
    indicator := 0
    try {
        targetOne := Gui("-Caption +ToolWindow +E0x08000000", "Overlay test target one")
        targetTwo := Gui("-Caption +ToolWindow +E0x08000000", "Overlay test target two")
        indicator := LabStatusOverlay()
        indicator.Label.Value := "TESTE | ARMADO | ganho 1.00"
        OverlayAssert(!indicator.Shown, "The indicator must start hidden", &assertions)
        OverlayAssertHidden(indicator, "New indicator", &assertions)
        styles := WinGetExStyle("ahk_id " indicator.Gui.Hwnd)
        OverlayAssert((styles & 0x20) != 0, "The indicator must allow clicks through", &assertions)
        OverlayAssert((styles & 0x08000000) != 0, "The indicator must not activate", &assertions)

        indicator.Place(targetOne.Hwnd, small, 0)
        OverlayAssertHidden(indicator, "Initial geometry", &assertions)
        indicator.Place(targetOne.Hwnd, small, 299)
        OverlayAssertHidden(indicator, "Before 300 ms", &assertions)
        activeBefore := WinExist("A")
        indicator.Place(targetOne.Hwnd, small, 300)
        OverlayAssertShown(indicator, small, "Stable small client", &assertions)
        OverlayAssert(WinExist("A") = activeBefore, "Showing the indicator must preserve foreground focus", &assertions)
        indicator.Place(targetOne.Hwnd, same, 450)
        OverlayAssertShown(indicator, same, "Unchanged geometry", &assertions)

        indicator.Place(targetOne.Hwnd, full, 500)
        OverlayAssertHidden(indicator, "Resize starts a new stability interval", &assertions)
        indicator.Place(targetOne.Hwnd, full, 799)
        OverlayAssertHidden(indicator, "Resize is not stable early", &assertions)
        indicator.Place(targetOne.Hwnd, full, 800)
        OverlayAssertShown(indicator, full, "Stable full client", &assertions)

        indicator.Place(targetOne.Hwnd, moved, 900)
        OverlayAssertHidden(indicator, "Movement hides the old position", &assertions)
        indicator.Place(targetOne.Hwnd, moved, 1199)
        OverlayAssertHidden(indicator, "Movement is not stable early", &assertions)
        indicator.Place(targetOne.Hwnd, moved, 1200)
        OverlayAssertShown(indicator, moved, "Stable moved client", &assertions)

        indicator.Place(targetTwo.Hwnd, moved, 1300)
        OverlayAssertHidden(indicator, "A reopened target resets stability even at the same coordinates", &assertions)
        indicator.Place(targetTwo.Hwnd, moved, 1599)
        OverlayAssertHidden(indicator, "A new HWND is not stable early", &assertions)
        indicator.Place(targetTwo.Hwnd, moved, 1600)
        OverlayAssertShown(indicator, moved, "Stable reopened target", &assertions)

        indicator.Hide()
        OverlayAssertHidden(indicator, "Focus loss hides the indicator", &assertions)
        indicator.Place(targetTwo.Hwnd, moved, 1700)
        OverlayAssertHidden(indicator, "Focus restoration restarts stability", &assertions)
        indicator.Place(targetTwo.Hwnd, moved, 2000)
        OverlayAssertShown(indicator, moved, "Stable restored focus", &assertions)

        indicator.Place(0, moved, 2100)
        OverlayAssertHidden(indicator, "A missing target hides the indicator", &assertions)
        indicator.Place(targetTwo.Hwnd, moved, 2200)
        OverlayAssertHidden(indicator, "Returning target must stabilize again", &assertions)
        indicator.Place(targetTwo.Hwnd, moved, 2500)
        OverlayAssertShown(indicator, moved, "Target returns", &assertions)

        indicator.Place(targetTwo.Hwnd, 0, 2600)
        OverlayAssertHidden(indicator, "An invalid rectangle hides the indicator", &assertions)
        indicator.Place(targetTwo.Hwnd, small, 2700)
        OverlayAssertHidden(indicator, "Valid geometry must stabilize after invalid geometry", &assertions)
        indicator.Place(targetTwo.Hwnd, small, 3000)
        OverlayAssertShown(indicator, small, "Geometry recovers", &assertions)

        indicator.Hide()
        indicator.Hide()
        OverlayAssertHidden(indicator, "Repeated hiding remains harmless", &assertions)

        targetOne.Show("NA x40 y40 w640 h480")
        WinGetClientPos(&targetX, &targetY, &targetWidth, &targetHeight, "ahk_id " targetOne.Hwnd)
        monitor := DllCall("user32\MonitorFromWindow", "Ptr", targetOne.Hwnd, "UInt", 2, "Ptr")
        monitorInfo := Buffer(40, 0)
        NumPut("UInt", monitorInfo.Size, monitorInfo)
        OverlayAssert(DllCall("user32\GetMonitorInfoW", "Ptr", monitor, "Ptr", monitorInfo, "Int"),
            "Synthetic target must provide native monitor geometry", &assertions)
        nativeRect := LabOverlayBounds(targetX, targetY, targetWidth, targetHeight,
            NumGet(monitorInfo, 4, "Int"), NumGet(monitorInfo, 8, "Int"),
            NumGet(monitorInfo, 12, "Int"), NumGet(monitorInfo, 16, "Int"))
        OverlayAssert(IsObject(nativeRect), "Synthetic target must have enough visible client area", &assertions)
        indicator.Update(targetOne.Hwnd, "TESTE NATIVO | ARMADO", "83E3B0", 4000)
        OverlayAssertHidden(indicator, "Native geometry also waits for stability", &assertions)
        indicator.Update(targetOne.Hwnd, "TESTE NATIVO | ARMADO", "83E3B0", 4300)
        OverlayAssertShown(indicator, nativeRect, "Native target update", &assertions)
        OverlayAssert(indicator.Label.Value = "TESTE NATIVO | ARMADO",
            "Native update must refresh the caption", &assertions)
        longCaption := "TESTE NATIVO | ARMADO | PERFIL COM NOME LONGO | ganho 2.25 | X 0 | Y 3 | texto excedente"
        indicator.Update(targetOne.Hwnd, longCaption, "FFFFFF", 4400)
        OverlayAssertShown(indicator, nativeRect, "Long captions must not resize the indicator", &assertions)
        OverlayAssert(indicator.Label.Value = longCaption,
            "The label must accept an updated caption without changing window bounds", &assertions)
        targetOne.Hide()
        indicator.Update(targetOne.Hwnd, "OCULTO", "FFFFFF", 4500)
        OverlayAssertHidden(indicator, "A hidden native target hides the indicator", &assertions)
        destroyedTargetHwnd := targetOne.Hwnd
        targetOne.Destroy()
        targetOne := 0
        indicator.Update(destroyedTargetHwnd, "ENCERRADO", "FFFFFF", 4600)
        OverlayAssertHidden(indicator, "A destroyed native target is ignored", &assertions)

        indicatorHwnd := indicator.Gui.Hwnd
        indicator.Destroy()
        indicator := 0
        OverlayAssert(!DllCall("user32\IsWindow", "Ptr", indicatorHwnd, "Int"),
            "Destroy must release the indicator window", &assertions)
    } finally {
        if IsObject(indicator)
            indicator.Destroy()
        if IsObject(targetTwo)
            targetTwo.Destroy()
        if IsObject(targetOne)
            targetOne.Destroy()
    }
    return assertions
}

OverlayAssertRect(rect, x, y, label, &assertions) {
    OverlayAssert(IsObject(rect), label " must produce a rectangle", &assertions)
    OverlayAssert(rect.X = x && rect.Y = y, label " must anchor to the visible client corner", &assertions)
    OverlayAssert(rect.W = 280 && rect.H = 26, label " must keep the compact fixed size", &assertions)
    OverlayAssert(Type(rect.Key) = "String" && rect.Key != "", label " must provide a geometry key", &assertions)
}

OverlayAssertHidden(indicator, label, &assertions) {
    OverlayAssert(!indicator.Shown, label " must clear the shown state", &assertions)
    OverlayAssert(!DllCall("user32\IsWindowVisible", "Ptr", indicator.Gui.Hwnd, "Int"),
        label " must hide the native window", &assertions)
}

OverlayAssertShown(indicator, rect, label, &assertions) {
    OverlayAssert(indicator.Shown, label " must set the shown state", &assertions)
    OverlayAssert(DllCall("user32\IsWindowVisible", "Ptr", indicator.Gui.Hwnd, "Int"),
        label " must show the native window", &assertions)
    WinGetClientPos(&x, &y, &width, &height, "ahk_id " indicator.Gui.Hwnd)
    OverlayAssert(x = rect.X && y = rect.Y, label " must use current physical coordinates", &assertions)
    OverlayAssert(width = 280 && height = 26, label " must stay 280x26 physical pixels", &assertions)
    OverlayAssert(WinExist("A") != indicator.Gui.Hwnd, label " must not become the foreground window", &assertions)
}

OverlayAssert(condition, label, &assertions) {
    assertions += 1
    if !condition
        throw Error(label)
}
