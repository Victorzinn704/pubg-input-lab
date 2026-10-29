; Native bitmap preview: X blue, Y green, zero line gray. No input side effects.
LabCurveBitmap(profile, width := 620, height := 150) {
    dc := DllCall("gdi32\CreateCompatibleDC", "Ptr", 0, "Ptr")
    if !dc
        throw Error("Nao foi possivel criar a previa.")
    info := Buffer(40, 0)
    NumPut("UInt", 40, "Int", width, "Int", -height, "UShort", 1, "UShort", 24, info)
    pixels := 0
    bitmap := DllCall("gdi32\CreateDIBSection", "Ptr", dc, "Ptr", info, "UInt", 0,
        "Ptr*", &pixels, "Ptr", 0, "UInt", 0, "Ptr")
    if !bitmap {
        DllCall("gdi32\DeleteDC", "Ptr", dc)
        throw Error("Nao foi possivel alocar a previa.")
    }
    oldBitmap := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
    try {
        DllCall("gdi32\PatBlt", "Ptr", dc, "Int", 0, "Int", 0, "Int", width, "Int", height, "UInt", 0x00FF0062)
        peak := 1.0
        for segment in profile.Segments
            peak := Max(peak, Abs(segment.Dx * profile.SavedGain), Abs(segment.Dy * profile.SavedGain))
        center := height // 2
        LabDrawPolyline(dc, [{X: 8, Y: center}, {X: width - 8, Y: center}], 0xB5B5B5, 1)
        duration := profile.Segments[-1].UntilMs
        for axis, color in Map("Dx", 0xCA782F, "Dy", 0x609B28) {
            points := []
            start := 0
            for segment in profile.Segments {
                y := Round(center - segment.%axis% * profile.SavedGain / peak * (center - 10))
                points.Push({X: Round(8 + start / duration * (width - 16)), Y: y})
                points.Push({X: Round(8 + segment.UntilMs / duration * (width - 16)), Y: y})
                start := segment.UntilMs
            }
            LabDrawPolyline(dc, points, color, 2)
        }
    } catch as err {
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldBitmap)
        DllCall("gdi32\DeleteObject", "Ptr", bitmap)
        throw err
    } finally {
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldBitmap)
        DllCall("gdi32\DeleteDC", "Ptr", dc)
    }
    return bitmap ; Ownership is transferred to Gui.Picture via HBITMAP:handle.
}

LabDrawPolyline(dc, points, color, width) {
    pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", width, "UInt", color, "Ptr")
    if !pen
        throw Error("Nao foi possivel desenhar a curva.")
    old := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", pen, "Ptr")
    try {
        for point in points {
            if A_Index = 1
                DllCall("gdi32\MoveToEx", "Ptr", dc, "Int", point.X, "Int", point.Y, "Ptr", 0)
            else
                DllCall("gdi32\LineTo", "Ptr", dc, "Int", point.X, "Int", point.Y)
        }
    } finally {
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", old)
        DllCall("gdi32\DeleteObject", "Ptr", pen)
    }
}
