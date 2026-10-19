RunLoggerTests(configPath) {
    assertionCount := 0
    SplitPath(A_LineFile, , &testDirectory)
    scratchRoot := testDirectory "\artifacts\logger-" LabQpcTicks()
    DirCreate(scratchRoot)
    fixture := scratchRoot "\unicode-fixture.txt"
    FileAppend("name=João`n", fixture, "UTF-8-RAW")
    logger := TrialLogger(scratchRoot, configPath, [A_LineFile, fixture])
    LoggerTestAssert(logger.RequireCapacity(), "New logger has no capacity", &assertionCount)
    SplitPath(configPath, &configName)
    LoggerTestAssert(DirExist(logger.Dir "\sources"), "Snapshot directory missing", &assertionCount)
    LoggerTestAssert(FileRead(logger.Dir "\sources\001-" configName, "UTF-8")
        = FileRead(configPath, "UTF-8"), "Config snapshot changed", &assertionCount)
    LoggerTestAssert(FileRead(logger.Dir "\sources\003-unicode-fixture.txt", "UTF-8")
        = FileRead(fixture, "UTF-8"), "Unicode source snapshot changed", &assertionCount)
    LoggerTestAssert(RegExMatch(LabUtcIso(), "^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$"),
        "UTC format incorrect", &assertionCount)

    event := LabEvent("move", 'reason, "quoted"' "`nnext line")
    event.Dx := 2
    event.Dy := -3
    event.RawDx := 2.25
    event.RawDy := -3.75
    logger.Record(event, "dry", "João", 1, true, true, true)
    event.SendCallQpc := 100
    event.SendReturnQpc := 200
    event.OsInserted := 1
    logger.Record(event, "output", "João", 1, true, true, true, true)
    LoggerTestAssert(logger.Flush(), "Initial flush failed", &assertionCount)

    originalCsv := logger._csvPath
    logger.Record(LabEvent("before_failure"), "dry", "p", 2, false, false, false)
    logger._csvPath := logger.Dir "\sources"
    failed := false
    try logger.Flush()
    catch
        failed := true
    LoggerTestAssert(failed, "Expected IO failure missing", &assertionCount)
    LoggerTestAssert(logger._bufferedCount = 1, "Failed flush lost event count", &assertionCount)
    logger.Record(LabEvent("after_failure"), "dry", "p", 2, false, false, false)
    logger._csvPath := originalCsv
    LoggerTestAssert(logger.Flush(), "Recovery flush failed", &assertionCount)

    logger._maxBuffered := 2
    logger.Record(LabEvent("capacity_1"), "dry", "p", 2, false, false, false)
    logger.Record(LabEvent("capacity_2"), "dry", "p", 2, false, false, false)
    overflowed := false
    try logger.Record(LabEvent("capacity_3"), "dry", "p", 2, false, false, false)
    catch
        overflowed := true
    LoggerTestAssert(overflowed, "Buffer bound not enforced", &assertionCount)
    LoggerTestAssert(logger._bufferedCount = 2, "Overflow changed buffer", &assertionCount)
    logger.Flush()
    elapsedBeforeSleep := logger.NowMs()
    Sleep(20)
    LoggerTestAssert(logger.NowMs() > elapsedBeforeSleep, "QPC elapsed did not advance", &assertionCount)
    logger.Close("test_complete")
    logger.Close("duplicate")
    LoggerTestAssert(logger._closed, "Close state incorrect", &assertionCount)
    afterClose := false
    try logger.Record(LabEvent("bad"), "dry", "p", 2, false, false, false)
    catch
        afterClose := true
    LoggerTestAssert(afterClose, "Closed logger accepted event", &assertionCount)

    csvBuffer := FileRead(originalCsv, "RAW")
    LoggerTestAssert(!(NumGet(csvBuffer, 0, "UChar") = 0xEF
        && NumGet(csvBuffer, 1, "UChar") = 0xBB
        && NumGet(csvBuffer, 2, "UChar") = 0xBF), "Unexpected UTF-8 BOM", &assertionCount)
    rows := LoggerTestParseCsv(FileRead(originalCsv, "UTF-8"))
    LoggerTestAssert(rows.Length = 8, "Expected header and seven event rows", &assertionCount)
    LoggerTestAssert(rows[1].Length = 26, "Unexpected CSV column count", &assertionCount)
    for index, row in rows
        LoggerTestAssert(row.Length = 26, "Row " index " has mismatched columns", &assertionCount)
    dry := LoggerTestRowMap(rows[1], rows[2])
    sent := LoggerTestRowMap(rows[1], rows[3])
    LoggerTestAssert(dry["requested_dx"] = "0" && dry["requested_dy"] = "0",
        "Dry run claimed attempted movement", &assertionCount)
    LoggerTestAssert(dry["planned_dx"] = "2" && dry["planned_dy"] = "-3",
        "Planned movement lost", &assertionCount)
    LoggerTestAssert(sent["requested_dx"] = "2" && sent["requested_dy"] = "-3",
        "Attempted coordinates incorrect", &assertionCount)
    LoggerTestAssert(dry["send_call_qpc_ticks"] = "" && dry["send_return_qpc_ticks"] = ""
        && dry["os_inserted_count"] = "", "Absent OS timing should remain blank", &assertionCount)
    LoggerTestAssert(sent["send_call_qpc_ticks"] = "100" && sent["send_return_qpc_ticks"] = "200"
        && sent["os_inserted_count"] = "1", "OS call evidence lost", &assertionCount)
    LoggerTestAssert(dry["reason"] = 'reason, "quoted"' "`nnext line",
        "CSV quoting or newline roundtrip failed", &assertionCount)
    LoggerTestAssert(dry["profile"] = "João", "Unicode roundtrip failed", &assertionCount)
    LoggerTestAssert(dry["raw_dx"] = "2.250000" && dry["raw_dy"] = "-3.750000",
        "Invariant numerical format changed", &assertionCount)
    LoggerTestAssert(rows[4][5] = "before_failure" && rows[5][5] = "after_failure",
        "Recovery changed event order", &assertionCount)
    LoggerTestAssert(rows[8][5] = "session_end", "Session end missing", &assertionCount)
    for index, row in rows {
        if index > 1
            LoggerTestAssert(row[1] = index - 1, "Sequence gap or duplicate", &assertionCount)
    }
    fullLogger := TrialLogger(scratchRoot, configPath, [])
    fullLogger._maxBuffered := 2
    fullLogger.Record(LabEvent("full_1"), "dry", "p", 0, false, false, false)
    fullLogger.Record(LabEvent("full_2"), "dry", "p", 0, false, false, false)
    fullCapacityRejected := false
    try fullLogger.RequireCapacity()
    catch
        fullCapacityRejected := true
    LoggerTestAssert(fullCapacityRejected, "RequireCapacity accepted a full buffer", &assertionCount)
    fullLogger.Close("full_buffer_close")
    fullRows := LoggerTestParseCsv(FileRead(fullLogger.Dir "\events.csv", "UTF-8"))
    LoggerTestAssert(fullRows.Length = 4, "Full-buffer close lost records", &assertionCount)
    LoggerTestAssert(fullRows[4][5] = "session_end", "Full-buffer close omitted end marker", &assertionCount)
    LoggerTestAssert(fullLogger._closed, "Full-buffer close did not finish", &assertionCount)
    closedCapacityRejected := false
    try fullLogger.RequireCapacity()
    catch
        closedCapacityRejected := true
    LoggerTestAssert(closedCapacityRejected, "RequireCapacity accepted a closed logger", &assertionCount)
    FileAppend("PASS " assertionCount " assertions`r`n", scratchRoot "\result.txt", "UTF-8-RAW")
    return assertionCount
}

LoggerTestAssert(condition, message, &assertionCount) {
    if !condition
        throw Error("Logger test failed: " message)
    assertionCount += 1
}

LoggerTestRowMap(header, row) {
    result := Map()
    for index, key in header
        result[key] := row[index]
    return result
}

LoggerTestParseCsv(text) {
    rows := []
    row := []
    value := ""
    inQuotes := false
    index := 1
    while index <= StrLen(text) {
        char := SubStr(text, index, 1)
        if char = '"' {
            if inQuotes && SubStr(text, index + 1, 1) = '"' {
                value .= '"'
                index += 1
            } else {
                inQuotes := !inQuotes
            }
        } else if char = "," && !inQuotes {
            row.Push(value)
            value := ""
        } else if char = "`n" && !inQuotes {
            row.Push(value)
            rows.Push(row)
            row := []
            value := ""
        } else if char != "`r" || inQuotes {
            value .= char
        }
        index += 1
    }
    if inQuotes
        throw Error("Logger CSV contains an unterminated quoted field.")
    if row.Length || value != "" {
        row.Push(value)
        rows.Push(row)
    }
    return rows
}
