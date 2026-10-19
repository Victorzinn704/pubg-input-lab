; One normal runtime per Windows session, independent of its installation path.
; Caller retains the returned handle until shutdown. Tests use unique names.
LabClaimInstance(name := "Local\RecoilLab.Instance.v1", notify := true) {
    if Type(name) != "String" || Trim(name) = ""
        throw ValueError("O nome da instancia deve ser uma string nao vazia.")
    handle := DllCall("kernel32\CreateMutexW", "Ptr", 0, "Int", false, "WStr", name, "Ptr")
    creationError := A_LastError
    if !handle
        throw Error("Nao foi possivel reservar a instancia do Recoil Lab. Win32=" creationError)
    if creationError != 183 ; ERROR_ALREADY_EXISTS
        return handle

    ; Opening an existing mutex also returns a handle; do not keep the duplicate alive.
    if !DllCall("kernel32\CloseHandle", "Ptr", handle, "Int")
        throw Error("Nao foi possivel fechar a reserva duplicada. Win32=" A_LastError)
    if notify
        LabNotifyExistingInstance()
    return 0
}

LabNotifyExistingInstance() {
    previousHidden := A_DetectHiddenWindows
    previousMatch := A_TitleMatchMode
    try {
        DetectHiddenWindows(true)
        SetTitleMatchMode(3)
        ; The first instance may still be creating its hidden control panel.
        hwnd := WinWait("Recoil Lab - ensaio instrumentado ahk_class AutoHotkeyGUI", , 1)
        if !hwnd
            return false
        PostMessage(0x8001, 0, 0, , "ahk_id " hwnd)
        return true
    } catch {
        ; A disappearing window or unavailable notification never permits another runtime.
        return false
    } finally {
        DetectHiddenWindows(previousHidden)
        SetTitleMatchMode(previousMatch)
    }
}
