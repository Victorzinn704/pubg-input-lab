; Optional visual QA for synthetic windows only. No hooks, keyboard or mouse input.
LabCaptureWorkbench(bench, folder) {
    bench.Gui.Show("NA w952 h624")
    try {
        for index, name in ["context", "curve", "hotkeys", "references"] {
            bench.Tabs.Choose(index)
            WinRedraw(bench.Gui.Hwnd)
            Sleep(60)
            LabCaptureWindow(bench.Gui.Hwnd, folder "\workbench-" name ".bmp")
        }
    } finally bench.Gui.Hide()
}

LabCaptureWindow(hwnd, path) {
    rect := Buffer(16)
    DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect)
    width := NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")
    height := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")
    sourceDC := DllCall("GetWindowDC", "Ptr", hwnd, "Ptr")
    dc := DllCall("gdi32\CreateCompatibleDC", "Ptr", sourceDC, "Ptr")
    bitmap := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", sourceDC, "Int", width, "Int", height, "Ptr")
    old := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
    try {
        if !DllCall("PrintWindow", "Ptr", hwnd, "Ptr", dc, "UInt", 2)
            throw Error("Visual QA: PrintWindow falhou.")
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", old)
        info := Buffer(40, 0)
        NumPut("UInt", 40, "Int", width, "Int", -height, "UShort", 1, "UShort", 32, info)
        pixels := Buffer(width * height * 4)
        if !DllCall("gdi32\GetDIBits", "Ptr", dc, "Ptr", bitmap, "UInt", 0, "UInt", height,
            "Ptr", pixels, "Ptr", info, "UInt", 0)
            throw Error("Visual QA: GetDIBits falhou.")
        header := Buffer(14, 0)
        NumPut("UShort", 0x4D42, header)
        NumPut("UInt", 54 + pixels.Size, header, 2)
        NumPut("UInt", 54, header, 10)
        captureFile := FileOpen(path, "w")
        try {
            captureFile.RawWrite(header)
            captureFile.RawWrite(info)
            captureFile.RawWrite(pixels)
        } finally captureFile.Close()
    } finally {
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", old)
        DllCall("gdi32\DeleteObject", "Ptr", bitmap)
        DllCall("gdi32\DeleteDC", "Ptr", dc)
        DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", sourceDC)
    }
}
