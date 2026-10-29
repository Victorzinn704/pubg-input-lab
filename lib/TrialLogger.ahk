class TrialLogger {
    __New(logRoot, configPath, sourcePaths) {
        this._buffer := []
        this._recovery := []
        this._bufferedCount := 0
        this._maxBuffered := 4096
        this._flushing := false
        this._ending := false
        this._closed := false
        this._sequence := 0
        this._frequency := LabQpcFrequency()
        this._startTicks := LabQpcTicks()
        this._startUtc := LabUtcIso()
        processId := DllCall("Kernel32\GetCurrentProcessId", "UInt")
        this.SessionId := RegExReplace(this._startUtc, "[^0-9TZ]") "-" processId "-" this._startTicks
        this.Dir := RTrim(logRoot, "\/") "\" this.SessionId
        this._csvPath := this.Dir "\events.csv"
        DirCreate(this.Dir "\sources")

        manifest := "session_id=" this.SessionId "`r`n"
            . "start_utc=" this._startUtc "`r`n"
            . "start_qpc_ticks=" this._startTicks "`r`n"
            . "qpc_frequency_hz=" this._frequency "`r`n"
            . "ahk_version=" A_AhkVersion "`r`n"
            . "ahk_executable=" A_AhkPath "`r`n"
            . "os_version=" A_OSVersion "`r`n"
            . "process_id=" processId "`r`n"
            . "process_bits=" (A_PtrSize * 8) "`r`n"
            . "os_64bit=" A_Is64bitOS "`r`n"
            . "utc_clock=GetSystemTimePreciseAsFileTime; formatted to milliseconds`r`n"
            . "elapsed_clock=QueryPerformanceCounter; monotonic elapsed milliseconds`r`n"
            . "evidence_scope=Input records describe attempted input, not reception by the target or anti-cheat detection.`r`n"
            . "planned_units=Signed integer Windows mouse movement arguments; not measured in-game displacement.`r`n"
            . "lag_ms=Step: scheduling delay. Time modes: sample gap exceeding IntervalMs; legacy elapsed discards excess, timeline integrates bounded gaps. Not OS call duration.`r`n"
            . "send_call_qpc_ticks=QPC sampled immediately before the OS input call; blank when unavailable.`r`n"
            . "send_return_qpc_ticks=QPC sampled immediately after the OS input call returns; blank when unavailable.`r`n"
            . "os_inserted_count=Input events accepted by the OS call; blank when unavailable. This is not target reception.`r`n"
            . "end_integrity=session_end indicates orderly logger closure only; it does not prove complete target telemetry.`r`n"
            . "flush_failure_policy=Pending records are restored after an exception; there is no transactional guarantee after a partial filesystem write. Reconcile duplicates or partial rows using sequence numbers.`r`n"
            . "flush_scheduling=Flush is serialized and bounded by 4096 buffered events. Emergency input stop is processed after the current synchronous flush completes; no hard real-time latency guarantee.`r`n"
            . "snapshot_policy=Exact file copies taken when the logger was constructed.`r`n"

        snapshots := [configPath]
        for sourcePath in sourcePaths
            snapshots.Push(sourcePath)
        for index, sourcePath in snapshots {
            SplitPath(sourcePath, &baseName)
            snapshotName := Format("{:03}", index) "-" baseName
            FileCopy(sourcePath, this.Dir "\sources\" snapshotName, false)
            manifest .= "source_" Format("{:03}", index) "=" snapshotName " | " sourcePath "`r`n"
        }
        FileAppend(manifest, this.Dir "\manifest.txt", "UTF-8-RAW")
        header := "seq,utc,qpc_ticks,session_ms,event,mode,profile,generation,burst,elapsed_ms,due_ms,lag_ms,raw_dx,raw_dy,planned_dx,planned_dy,requested_dx,requested_dy,input_attempted,send_call_qpc_ticks,send_return_qpc_ticks,os_inserted_count,reason,target_focused,lmb_physical,rmb_physical`r`n"
        FileAppend(header, this._csvPath, "UTF-8-RAW")
    }

    NowMs() {
        return (LabQpcTicks() - this._startTicks) * 1000.0 / this._frequency
    }

    Record(event, mode, profileName, generation, focused, left, right, attempted := false) {
        this.RequireCapacity()
        ticks := LabQpcTicks()
        utc := LabUtcIso()
        sessionMs := (ticks - this._startTicks) * 1000.0 / this._frequency
        plannedDx := LabEventField(event, "Dx", 0)
        plannedDy := LabEventField(event, "Dy", 0)
        fields := [utc, ticks, LabCsvNumber(sessionMs), LabEventField(event, "Kind", ""),
            mode, profileName, generation, LabEventField(event, "Burst", 0),
            LabCsvNumber(LabEventField(event, "ElapsedMs", 0)),
            LabCsvNumber(LabEventField(event, "DueMs", 0)),
            LabCsvNumber(LabEventField(event, "LagMs", 0)),
            LabCsvNumber(LabEventField(event, "RawDx", 0)),
            LabCsvNumber(LabEventField(event, "RawDy", 0)),
            plannedDx, plannedDy, attempted ? plannedDx : 0, attempted ? plannedDy : 0,
            attempted ? 1 : 0, LabEventField(event, "SendCallQpc", ""),
            LabEventField(event, "SendReturnQpc", ""), LabEventField(event, "OsInserted", ""),
            LabEventField(event, "Reason", ""),
            focused ? 1 : 0, left ? 1 : 0, right ? 1 : 0]
        row := ""
        for field in fields
            row .= "," LabCsvQuote(field)

        previousCritical := A_IsCritical
        Critical("On")
        try {
            this.RequireCapacity()
            this._sequence += 1
            this._buffer.Push(this._sequence row "`r`n")
            this._bufferedCount += 1
        } finally {
            Critical(previousCritical)
        }
    }

    RequireCapacity() {
        if this._ending || this._closed
            throw Error("Cannot append to a closing or closed trial log.")
        if this._bufferedCount >= this._maxBuffered
            throw Error("Trial log buffer reached " this._maxBuffered " events; stop the trial and flush the log.")
        return true
    }

    Flush() {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if this._flushing
                return false
            if this._bufferedCount = 0
                return true
            batches := this._recovery
            batches.Push(this._buffer)
            this._buffer := []
            this._recovery := []
            pendingCount := this._bufferedCount
            this._flushing := true
            try {
                output := ""
                for batch in batches {
                    for row in batch
                        output .= row
                }
                FileAppend(output, this._csvPath, "UTF-8-RAW")
                this._bufferedCount -= pendingCount
            } catch as err {
                this._recovery := batches
                throw err
            } finally {
                this._flushing := false
            }
            return true
        } finally {
            Critical(previousCritical)
        }
    }

    Close(reason) {
        if this._closed
            return
        if !this._ending {
            if this._bufferedCount >= this._maxBuffered && !this.Flush()
                throw Error("Cannot close the full trial log while a flush is already in progress.")
            this.Record(LabEvent("session_end", reason), "", "", 0, false, false, false)
            this._ending := true
        }
        if !this.Flush()
            throw Error("Cannot close the trial log while a flush is already in progress.")
        this._closed := true
    }
}

LabQpcTicks() {
    ticks := 0
    if !DllCall("Kernel32\QueryPerformanceCounter", "Int64*", &ticks, "Int")
        throw OSError()
    return ticks
}

LabQpcFrequency() {
    frequency := 0
    if !DllCall("Kernel32\QueryPerformanceFrequency", "Int64*", &frequency, "Int")
        throw OSError()
    return frequency
}

LabUtcIso() {
    fileTime := Buffer(8, 0)
    systemTime := Buffer(16, 0)
    DllCall("Kernel32\GetSystemTimePreciseAsFileTime", "Ptr", fileTime)
    if !DllCall("Kernel32\FileTimeToSystemTime", "Ptr", fileTime, "Ptr", systemTime, "Int")
        throw OSError()
    return Format("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{:03}Z",
        NumGet(systemTime, 0, "UShort"), NumGet(systemTime, 2, "UShort"),
        NumGet(systemTime, 6, "UShort"), NumGet(systemTime, 8, "UShort"),
        NumGet(systemTime, 10, "UShort"), NumGet(systemTime, 12, "UShort"),
        NumGet(systemTime, 14, "UShort"))
}

LabEvent(kind, reason := "") {
    return {Kind: kind, Reason: reason, Burst: 0, ElapsedMs: 0, DueMs: 0,
        LagMs: 0, Dx: 0, Dy: 0, RawDx: 0, RawDy: 0}
}

LabEventField(event, name, fallback) {
    return event.HasOwnProp(name) ? event.%name% : fallback
}

LabCsvNumber(value) {
    return StrReplace(Format("{:.6f}", value), ",", ".")
}

LabCsvQuote(value) {
    return '"' StrReplace(String(value), '"', '""') '"'
}
