; Deterministic tests: fake timestamps and button states only, no input output.
RunEngineTests() {
    suite := RecoilEngineTestSuite()
    return suite.Run()
}

class RecoilEngineTestSuite {
    __New() {
        this.Assertions := 0
    }

    Run() {
        this.InitialRelease()
        this.ArmWhileFiring()
        this.FocusLoss()
        this.FocusPauseReset()
        this.FocusPauseLifetime()
        this.PartialRelease()
        this.SessionLimit()
        this.BurstLimits()
        this.LimitReleaseLatch()
        this.Scheduler()
        this.SchedulerJitter()
        this.SchedulerStall()
        this.ElapsedStartAndRate()
        this.ElapsedJitter()
        this.ElapsedSegments()
        this.ElapsedStall()
        this.ElapsedSaturation()
        this.ElapsedSafetyReset()
        this.ElapsedMetadata()
        this.Fractions()
        this.StepBound()
        this.GenerationAndShape()
        this.ExactDisarmTime()
        this.SingleHeld()
        this.SingleAdsClicks()
        this.SingleCooldown()
        this.SingleRequiresLeftEdge()
        this.SingleSafetyReset()
        this.ContinuousSafetyReset()
        this.SingleSegmentsAndFractions()
        this.TriggerMetadata()
        this.Validation()
        return this.Assertions
    }

    Engine(segments := 0, interval := 10, maxBurst := 100, session := 1000, maxLate := 15, maxStep := 8) {
        if !IsObject(segments)
            segments := [{UntilMs: 100, Dx: 1, Dy: 2}]
        return RecoilEngine({Name: "deterministic-test", IntervalMs: interval, Segments: segments},
            {MaxBurstMs: maxBurst, SessionLimitMs: session, MaxLateMs: maxLate, MaxStep: maxStep})
    }

    Start(engine, nowMs := 0) {
        engine.Arm(nowMs)
        engine.Tick(nowMs, true, false, false)
        return engine.Tick(nowMs, true, true, true)
    }

    Equal(actual, expected, label) {
        this.Assertions += 1
        if actual != expected
            throw Error(label ": expected [" expected "], received [" actual "].")
    }

    CountKind(events, kind) {
        count := 0
        for event in events
            if event.Kind = kind
                count += 1
        return count
    }

    Movement(events) {
        this.Equal(this.CountKind(events, "move"), 1, "Exactly one planned movement")
        for event in events
            if event.Kind = "move"
                return event
        throw Error("Movement event missing.")
    }

    Shape(events) {
        for event in events {
            for field in ["Kind", "Reason", "Burst", "ElapsedMs", "DueMs", "LagMs", "Dx", "Dy", "RawDx", "RawDy"]
                this.Equal(event.HasOwnProp(field), true, "Event field " field)
        }
    }

    InitialRelease() {
        engine := this.Engine()
        this.Equal(engine.State, "disabled", "Initial state")
        this.Equal(engine.SessionStart, -1, "Session not yet started")
        this.Shape(engine.Arm(0))
        this.Equal(engine.State, "wait_release", "Arming requires release")
        this.Equal(engine.Tick(0, true, true, true).Length, 0, "Initially held buttons cannot fire")
        events := engine.Tick(1, true, false, true)
        this.Shape(events)
        this.Equal(events[1].Reason, "left_released", "Left release readies while aiming")
        this.Equal(this.CountKind(events, "move"), 0, "Release tick never emits movement")
        this.Equal(engine.State, "ready", "Left up enables readiness")
        events := engine.Tick(4, true, true, true)
        this.Shape(events)
        this.Equal(events[1].Kind, "burst_start", "Burst starts before movement")
        movement := this.Movement(events)
        this.Equal(movement.ElapsedMs, 0, "First step elapsed time")
        this.Equal(movement.DueMs, 4, "First step is due immediately")
        this.Equal(movement.LagMs, 0, "First step has no scheduling lag")
        this.Equal(engine.BurstId, 1, "First burst ID")
    }

    ArmWhileFiring() {
        for single in [false, true] {
            engine := single ? this.SingleEngine() : this.Engine()
            engine.Arm(0)
            for nowMs in [0, 10, 20] {
                this.Equal(engine.Tick(nowMs, true, true, true).Length, 0,
                    "Arming with held LMB never emits movement")
                this.Equal(engine.State, "wait_release", "Held LMB keeps initial release latch")
            }
            this.Equal(engine.Tick(21, true, true, false).Length, 0,
                "Releasing only aim cannot clear initial latch")
            this.Equal(engine.Tick(22, true, true, true).Length, 0,
                "Restoring aim cannot fire held trigger after arm")
            events := engine.Tick(23, true, false, true)
            this.Equal(events[1].Reason, "left_released", "Held aim permits readiness after LMB release")
            this.Equal(this.CountKind(events, "move"), 0, "Initial LMB release is not a shot")
            this.Movement(engine.Tick(24, true, true, true))
            this.Equal(engine.BurstId, 1, "Only new trigger press opens initial burst")
        }
    }

    FocusLoss() {
        engine := this.Engine()
        engine.Arm(0)
        this.Equal(engine.Tick(0, false, false, false).Length, 0, "May wait without initial target focus")
        this.Equal(engine.State, "wait_release", "No focus remains waiting")
        engine.Tick(1, true, false, false)
        engine.Tick(2, true, true, true)
        events := engine.Tick(3, false, true, true)
        this.Shape(events)
        this.Equal(this.CountKind(events, "move"), 0, "Focus loss emits no movement")
        this.Equal(events.Length, 2, "Active burst stops before one pause event")
        this.Equal(events[1].Kind, "burst_stop", "Focus loss closes active burst")
        this.Equal(events[1].Reason, "focus_lost", "Burst stop records focus loss")
        this.Equal(events[1].ElapsedMs, 1, "Focus stop preserves actual burst duration")
        this.Equal(events[-1].Kind, "paused", "Focus loss emits paused event")
        this.Equal(events[-1].Reason, "focus_lost", "Focus-loss reason")
        this.Equal(engine.State, "paused_focus", "Focus loss pauses")
        this.Equal(engine.Armed, true, "Focus loss preserves enabled intent")
        this.Equal(engine.Generation, 2, "Focus loss invalidates timer generation")
        this.Equal(engine.Tick(4, false, true, true).Length, 0, "Repeated unfocused tick emits nothing")
        this.Equal(engine.Tick(5, false, false, true).Length, 0, "Unfocused trigger release emits nothing")
        this.Equal(engine.Generation, 2, "Continuing pause does not repeatedly invalidate generation")
        events := engine.Tick(6, true, true, true)
        this.Shape(events)
        this.Equal(events.Length, 1, "Return tick emits only resumed")
        this.Equal(events[1].Kind, "resumed", "Restored focus resumes enabled intent")
        this.Equal(events[1].Reason, "focus_restored", "Resume event reason")
        this.Equal(this.CountKind(events, "move"), 0, "Focus return never moves")
        this.Equal(engine.State, "wait_release", "Return with held trigger requires release")
        this.Equal(engine.Generation, 2, "Resume retains the invalidated generation")
        this.Equal(engine.Tick(7, true, true, true).Length, 0, "Held trigger after resume cannot restart")
        events := engine.Tick(8, true, false, true)
        this.Equal(events[1].Reason, "left_released", "LMB release after return readies with held aim")
        movement := this.Movement(engine.Tick(9, true, true, true))
        this.Equal(movement.ElapsedMs, 0, "Resumed shot starts a new burst")
        this.Equal(movement.DueMs, 9, "Resumed shot starts a new deadline")
        this.Equal(engine.BurstId, 2, "Resume never reuses the interrupted burst")
        events := engine.Tick(10, false, true, true)
        this.Equal(events[-1].Kind, "paused", "Second focus loss emits its own pause")
        this.Equal(engine.Generation, 3, "Each distinct loss invalidates once")
        this.Equal(engine.Tick(11, false, true, true).Length, 0, "Second pause also emits once")

        waiting := this.Engine()
        waiting.Arm(0)
        this.Equal(waiting.Tick(0, false, false, false).Length, 0, "Initial unfocused arm does not pause")
        waiting.Tick(1, true, true, true)
        events := waiting.Tick(2, false, true, true)
        this.Equal(events.Length, 1, "Loss before any burst only emits pause")
        this.Equal(events[1].Kind, "paused", "Release-latched engine also pauses")
        this.Equal(waiting.Armed, true, "Pause before first burst preserves intent")
        events := waiting.Tick(3, true, false, true)
        this.Equal(events[1].Kind, "resumed", "Return with already released LMB still emits resumed")
        this.Equal(waiting.State, "wait_release", "Return does not bypass a focused release observation")
        this.Equal(this.CountKind(events, "move"), 0, "Released return tick cannot move")
        waiting.Tick(4, true, false, true)
        this.Movement(waiting.Tick(5, true, true, true))
    }

    FocusPauseReset() {
        engine := this.Engine([{UntilMs: 100, Dx: 0.6, Dy: -0.6}])
        first := this.Movement(this.Start(engine))
        this.Equal(first.Dx, 0, "Initial fractional X retained only inside its burst")
        this.Equal(first.Dy, 0, "Initial fractional Y retained only inside its burst")
        engine.Tick(1, false, true, true)
        this.Equal(engine._burstStart, -1, "Pause clears burst start")
        this.Equal(engine._due, -1, "Pause clears pending deadline")
        this.Equal(engine._residualX, 0, "Pause clears residual X")
        this.Equal(engine._residualY, 0, "Pause clears residual Y")
        this.Equal(engine._singleEmitted, false, "Pause clears pending single completion")
        this.Equal(engine.Tick(199, false, true, true).Length, 0, "Old burst deadline cannot emit during pause")
        events := engine.Tick(200, true, true, true)
        this.Equal(events[1].Kind, "resumed", "Long pause resumes without old burst limit")
        this.Equal(engine.Tick(201, true, false, true)[1].Kind, "ready", "Release readies after long pause")
        first := this.Movement(engine.Tick(202, true, true, true))
        this.Equal(first.ElapsedMs, 0, "New burst does not include paused time")
        this.Equal(first.DueMs, 202, "Old overdue deadline is discarded")
        this.Equal(first.Dx, 0, "Pre-pause fractional X cannot leak into resumed burst")
        this.Equal(first.Dy, 0, "Pre-pause fractional Y cannot leak into resumed burst")
        second := this.Movement(engine.Tick(212, true, true, true))
        this.Equal(second.Dx, 1, "New burst accumulates its own X residual")
        this.Equal(second.Dy, -1, "New burst accumulates its own Y residual")
        this.Equal(engine.SessionStart, 0, "Long pause never refreshes session start")
    }

    FocusPauseLifetime() {
        engine := this.Engine(0, 10, 100, 20)
        this.Start(engine)
        engine.Tick(1, false, true, true)
        this.Equal(engine.Tick(19, false, false, false).Length, 0, "Paused session remains silent before deadline")
        events := engine.Tick(20, false, false, false)
        this.Equal(events.Length, 1, "Paused session expires without a second burst stop")
        this.Equal(events[1].Kind, "session_expired", "Session expires while focus remains absent")
        this.Equal(events[1].Reason, "session_limit", "Paused expiry records session limit")
        this.Equal(engine.State, "expired", "Pause cannot delay terminal session expiry")
        this.Equal(engine.Armed, false, "Expired pause clears enabled intent")
        this.Equal(engine.Generation, 3, "Expiry invalidates paused generation")
        this.Equal(engine.Tick(21, true, false, true).Length, 0, "Focus return cannot resume an expired session")
        this.Equal(engine.Arm(22)[1].Kind, "session_expired", "Manual arm cannot reset paused session expiry")

        manual := this.Engine()
        this.Start(manual)
        manual.Tick(1, false, true, true)
        events := manual.Disarm("manual", 2)
        this.Equal(events.Length, 1, "Manual disable while paused only emits disarmed")
        this.Equal(events[1].Kind, "disarmed", "Manual disable is separate from pause")
        this.Equal(manual.Armed, false, "Manual disable clears preserved intent")
        this.Equal(manual.State, "disabled", "Manual disable leaves paused state")
        this.Equal(manual.Tick(3, true, false, true).Length, 0, "Focus return cannot undo manual disable")
        this.Equal(manual.Tick(4, true, true, true).Length, 0, "New click cannot undo manual disable")
        manual.Arm(5)
        this.Equal(manual.Tick(5, false, false, false).Length, 0, "Explicit arm again waits for first focus")
        manual.Tick(6, true, false, true)
        this.Movement(manual.Tick(7, true, true, true))
    }

    PartialRelease() {
        engine := this.Engine()
        this.Start(engine)
        events := engine.Tick(1, true, false, true)
        this.Shape(events)
        this.Equal(events[1].Reason, "button_released", "Either release stops burst")
        this.Equal(events[-1].Reason, "left_released", "Observed LMB release also readies continuous mode")
        this.Equal(this.CountKind(events, "move"), 0, "Release tick emits no movement")
        this.Equal(engine.State, "ready", "Aim may remain held between bursts")
        this.Movement(engine.Tick(2, true, true, true))
        this.Equal(engine.BurstId, 2, "Second burst increments ID")
        engine.Tick(3, true, false, true)
        this.Movement(engine.Tick(4, true, true, true))
        this.Equal(engine.BurstId, 3, "Repeated LMB presses with held aim create distinct bursts")
        events := engine.Tick(5, true, true, false)
        this.Equal(events[1].Reason, "button_released", "Releasing aim also stops compensation")
        this.Equal(engine.State, "wait_release", "Held trigger after aim release keeps latch")
        this.Equal(engine.Tick(6, true, true, true).Length, 0, "Restoring aim cannot restart held trigger")
        this.Equal(engine.Tick(7, true, true, false).Length, 0, "Repeated aim release does not count as trigger release")
        engine.Tick(8, true, false, true)
        this.Equal(engine.State, "ready", "Observed trigger release clears latch with aim held")
        this.Movement(engine.Tick(9, true, true, true))
        this.Equal(engine.BurstId, 4, "New trigger press restarts after aim interruption")
        engine.Tick(10, true, false, false)
        this.Equal(engine.State, "ready", "Both buttons up also immediately readies next burst")
    }

    SessionLimit() {
        engine := this.Engine(0, 10, 100, 35, 100)
        this.Start(engine, 100)
        engine.Disarm("manual")
        this.Equal(engine.SessionStart, 100, "Disarm keeps session start")
        engine.Arm(110)
        this.Equal(engine.SessionStart, 100, "Rearming does not refresh session")
        engine.Tick(110, true, false, true)
        engine.Tick(111, true, true, true)
        this.Movement(engine.Tick(134, true, true, true))
        events := engine.Tick(135, true, true, true)
        this.Shape(events)
        this.Equal(events[-1].Kind, "session_expired", "Exact session boundary expires")
        this.Equal(this.CountKind(events, "move"), 0, "Expiry suppresses all moves")
        this.Equal(engine.State, "expired", "Expired state")
        this.Equal(engine.Armed, false, "Expiry clears armed flag")
        engine.Disarm("manual")
        this.Equal(engine.State, "expired", "Disarm cannot reset expiry")
        this.Shape(engine.Arm(136))
        this.Equal(engine.State, "expired", "Rearm cannot reset expiry")
        this.Equal(engine.Tick(137, true, true, true).Length, 0, "Expired ticks remain inert")
        waiting := this.Engine(0, 10, 100, 20)
        waiting.Arm(0)
        waiting.Tick(20, false, false, false)
        this.Equal(waiting.State, "expired", "Session also expires while waiting for focus")
        toggled := this.Engine(0, 10, 100, 20)
        toggled.Arm(0)
        toggled.Disarm("manual")
        toggled.Arm(20)
        this.Equal(toggled.State, "expired", "Disabled time counts against session limit")
    }

    BurstLimits() {
        engine := this.Engine([{UntilMs: 40, Dx: 1, Dy: 1}], 10, 25)
        this.Start(engine)
        this.Movement(engine.Tick(24, true, true, true))
        events := engine.Tick(25, true, true, true)
        this.Equal(events[1].Reason, "burst_limit", "Configured burst cap applies before next due time")
        this.Equal(this.CountKind(events, "move"), 0, "No step at exact burst limit")
        this.Equal(engine.State, "wait_release", "Burst limit latches release")
        shorter := this.Engine([{UntilMs: 15, Dx: 1, Dy: 1}], 10, 100)
        this.Start(shorter)
        events := shorter.Tick(15, true, true, true)
        this.Equal(events[1].Reason, "burst_limit", "Last segment bounds maximum burst")
    }

    LimitReleaseLatch() {
        for stopCase in ["burst_limit", "scheduler_late"] {
            engine := stopCase = "burst_limit" ? this.Engine(0, 10, 25) : this.Engine(0, 10, 100, 1000, 5)
            this.Start(engine)
            stopTime := stopCase = "burst_limit" ? 25 : 16
            events := engine.Tick(stopTime, true, true, true)
            this.Equal(events[1].Reason, stopCase, "Expected stop establishes release latch")
            this.Equal(engine.State, "wait_release", "Stopped burst waits for trigger release")
            this.Equal(engine.Tick(stopTime + 1, true, true, true).Length, 0,
                "Holding both buttons cannot restart a stopped burst")
            this.Equal(engine.Tick(stopTime + 2, true, true, false).Length, 0,
                "Aim release does not clear a stopped burst latch")
            this.Equal(engine.Tick(stopTime + 3, true, true, true).Length, 0,
                "Aim restoration cannot restart after limit or stall")
            this.Equal(engine.BurstId, 1, "No automatic restart creates another burst")
            events := engine.Tick(stopTime + 4, true, false, true)
            this.Equal(events[1].Reason, "left_released", "Trigger release readies after limit or stall")
            this.Equal(this.CountKind(events, "move"), 0, "Recovery release emits no movement")
            this.Movement(engine.Tick(stopTime + 5, true, true, true))
            this.Equal(engine.BurstId, 2, "Only new trigger starts after limit or stall")
        }
    }

    Scheduler() {
        engine := this.Engine([{UntilMs: 10, Dx: 1, Dy: 1}, {UntilMs: 100, Dx: 2, Dy: 3}], 10, 100, 1000, 5)
        this.Start(engine)
        this.Equal(engine.Tick(9, true, true, true).Length, 0, "No early movement")
        movement := this.Movement(engine.Tick(15, true, true, true))
        this.Equal(movement.LagMs, 5, "Allowed lag recorded")
        this.Equal(movement.DueMs, 10, "Original due time recorded")
        this.Equal(movement.RawDx, 2, "Segment chosen using actual elapsed time")
        this.Equal(movement.RawDy, 3, "Second-segment vertical movement")
        this.Equal(engine.Tick(19, true, true, true).Length, 0, "No movement before next cadence slot")
        movement := this.Movement(engine.Tick(20, true, true, true))
        this.Equal(movement.DueMs, 20, "Small jitter preserves the cadence")
        movement := this.Movement(engine.Tick(35, true, true, true))
        this.Equal(movement.DueMs, 30, "Repeated small jitter does not accumulate")
        events := engine.Tick(46, true, true, true)
        this.Equal(events[1].Reason, "scheduler_late", "Excessive delay stops burst")
        this.Equal(events[1].LagMs, 6, "Excessive delay recorded")
        this.Equal(this.CountKind(events, "move"), 0, "Late tick emits no catch-up movement")
        this.Equal(engine.State, "wait_release", "Scheduler fault requires release")
    }

    SchedulerJitter() {
        engine := this.Engine([{UntilMs: 3000, Dx: 0, Dy: 3}], 20, 3000, 10000, 100)
        engine.Arm(0)
        engine.Tick(0, true, false, false)
        totalMoves := 0
        totalDy := 0
        lastDue := -1
        Loop 64 {
            ; Simulate a 15.625 ms polling clock over the half-open window [0, 1000).
            events := engine.Tick((A_Index - 1) * 15.625, true, true, true)
            moves := this.CountKind(events, "move")
            this.Equal(moves <= 1, true, "Jitter tick never queues multiple movements")
            totalMoves += moves
            for event in events {
                if event.Kind = "move" {
                    totalDy += event.Dy
                    lastDue := event.DueMs
                }
            }
        }
        this.Equal(totalMoves, 50, "20 ms cadence retains 50 movements per second")
        this.Equal(totalDy, 150, "Jitter does not reduce the configured movement rate")
        this.Equal(lastDue, 980, "Final cadence slot remains anchored to burst start")
    }

    SchedulerStall() {
        engine := this.Engine([{UntilMs: 3000, Dx: 0, Dy: 3}], 20, 3000, 10000, 100)
        this.Start(engine)
        movement := this.Movement(engine.Tick(99, true, true, true))
        this.Equal(movement.DueMs, 20, "Delayed movement retains its original deadline")
        this.Equal(movement.LagMs, 79, "Stall delay is recorded")
        this.Equal(engine.Tick(100, true, true, true).Length, 0, "No catch-up at next original slot after stall")
        this.Equal(engine.Tick(118, true, true, true).Length, 0, "Stall starts a full new interval")
        movement := this.Movement(engine.Tick(119, true, true, true))
        this.Equal(movement.DueMs, 119, "Cadence resumes from the actual stalled tick")

        boundary := this.Engine([{UntilMs: 3000, Dx: 0, Dy: 3}], 20, 3000, 10000, 100)
        this.Start(boundary)
        this.Movement(boundary.Tick(40, true, true, true))
        this.Equal(boundary.Tick(59, true, true, true).Length, 0, "A whole missed interval also resynchronizes")
        movement := this.Movement(boundary.Tick(60, true, true, true))
        this.Equal(movement.DueMs, 60, "Exact interval stall resumes at its new deadline")

        late := this.Engine([{UntilMs: 3000, Dx: 0, Dy: 3}], 20, 3000, 10000, 100)
        this.Start(late)
        events := late.Tick(121, true, true, true)
        this.Equal(events[1].Reason, "scheduler_late", "Stall beyond MaxLateMs still stops the burst")
        this.Equal(events[1].LagMs, 101, "Excessive stall records its delay")
        this.Equal(this.CountKind(events, "move"), 0, "Excessive stall cannot emit a movement")
    }

    ElapsedEngine(segments := 0, interval := 20, maxBurst := 3000, session := 10000,
        maxLate := 100, maxStep := 12) {
        if !IsObject(segments)
            segments := [{UntilMs: 3000, Dx: 0, Dy: 4.5}]
        return RecoilEngine({Name: "elapsed-test", IntervalMs: interval, Segments: segments,
            MotionMode: "elapsed", TriggerMode: "continuous"},
            {MaxBurstMs: maxBurst, SessionLimitMs: session, MaxLateMs: maxLate, MaxStep: maxStep})
    }

    ElapsedStartAndRate() {
        for pollMs in [10, 15.625] {
            engine := this.ElapsedEngine()
            events := this.Start(engine)
            this.Shape(events)
            this.Equal(events.Length, 1, "Elapsed start only opens the burst")
            this.Equal(events[1].Kind, "burst_start", "Elapsed start is recorded")
            this.Equal(this.CountKind(events, "move"), 0, "Elapsed start has no instantaneous dose")
            this.Equal(engine.Tick(0, true, true, true).Length, 0,
                "A repeated timestamp contributes no elapsed dose")
            totalDy := 0
            maxDy := 0
            Loop Round(1000 / pollMs) {
                movement := this.Movement(engine.Tick(A_Index * pollMs, true, true, true))
                this.Equal(movement.Dx, 0, "Elapsed vertical profile does not add horizontal movement")
                totalDy += movement.Dy
                maxDy := Max(maxDy, movement.Dy)
            }
            this.Equal(totalDy, 225, "4.5 counts per 20 ms integrates to 225 counts per second")
            this.Equal(maxDy, pollMs = 10 ? 3 : 4,
                "Normal polling divides the nominal dose into smaller integer packets")
        }
    }

    ElapsedJitter() {
        engine := this.ElapsedEngine([{UntilMs: 3000, Dx: -4.5, Dy: 4.5}])
        this.Start(engine)
        nowMs := 0
        totalX := 0
        totalY := 0
        ; Each cycle is exactly 40 ms; every delta is within the 20 ms integration cap.
        Loop 25 {
            for delta in [6.25, 13.75, 15.625, 4.375] {
                nowMs += delta
                movement := this.Movement(engine.Tick(nowMs, true, true, true))
                totalX += movement.Dx
                totalY += movement.Dy
                this.Equal(Abs(totalY - nowMs * 4.5 / 20) < 1, true,
                    "Healthy jitter preserves cumulative dose within one count")
                this.Equal(totalX, -totalY, "Elapsed quantization is symmetric for negative rates")
                this.Equal(movement.Dy <= Ceil(delta * 4.5 / 20), true,
                    "A short tick cannot receive an entire nominal interval dose")
            }
        }
        this.Equal(nowMs, 1000, "Jitter trace covers exactly one second")
        this.Equal(totalY, 225, "Jitter does not change one-second integrated dose")
        this.Equal(totalX, -225, "Negative integrated dose retains the same magnitude")
    }

    ElapsedSegments() {
        engine := this.ElapsedEngine([{UntilMs: 10, Dx: 2, Dy: 4},
            {UntilMs: 20, Dx: -2, Dy: -4}, {UntilMs: 100, Dx: 4, Dy: 8}])
        this.Start(engine)
        movement := this.Movement(engine.Tick(15, true, true, true))
        this.Equal(movement.RawDx, 0.5, "Crossing a sign change integrates both segment durations")
        this.Equal(movement.RawDy, 1, "First crossing uses 10 ms positive and 5 ms negative")
        this.Equal(movement.Dx, 0, "Fractional segment integral is retained")
        movement := this.Movement(engine.Tick(25, true, true, true))
        this.Equal(movement.RawDx, 0.5, "Next crossing integrates 5 ms from each adjacent segment")
        this.Equal(movement.RawDy, 1, "Later segment does not replace the entire integration window")
        this.Equal(movement.Dx, 1, "Fractional integrals survive segment boundaries")
        movement := this.Movement(engine.Tick(45, true, true, true))
        this.Equal(movement.RawDx, 4, "A full interval within one segment retains its nominal dose")
        this.Equal(movement.RawDy, 8, "Uncrossed full interval keeps the segment vertical dose")

        recent := this.ElapsedEngine([{UntilMs: 10, Dx: 80, Dy: 80},
            {UntilMs: 100, Dx: 2, Dy: 2}])
        this.Start(recent)
        movement := this.Movement(recent.Tick(40, true, true, true))
        this.Equal(movement.RawDy, 2, "Stall integrates the recent window, not an obsolete early phase")
    }

    ElapsedStall() {
        engine := this.ElapsedEngine()
        this.Start(engine)
        this.Equal(this.Movement(engine.Tick(10, true, true, true)).Dy, 2,
            "Initial half interval retains a quarter-count residue")
        movement := this.Movement(engine.Tick(50, true, true, true))
        this.Equal(movement.RawDy, 4.5, "A 40 ms stall contributes at most one 20 ms interval")
        this.Equal(movement.Dy, 4, "Capped stall does not replay omitted dose")
        this.Equal(movement.LagMs, 20, "Allowed elapsed stall records delay beyond its interval")
        movement := this.Movement(engine.Tick(60, true, true, true))
        this.Equal(movement.RawDy, 2.25, "Next tick contains only its new 10 ms window")
        this.Equal(movement.Dy, 3, "Only sub-count residue survives the discarded stall")
        this.Equal(engine.Tick(60, true, true, true).Length, 0,
            "Repeated timestamp cannot drain a backlog")

        boundary := this.ElapsedEngine()
        this.Start(boundary)
        movement := this.Movement(boundary.Tick(120, true, true, true))
        this.Equal(movement.RawDy, 4.5, "Exact MaxLateMs boundary permits only the capped window")
        this.Equal(movement.LagMs, 100, "Exact allowed elapsed lateness is recorded")

        late := this.ElapsedEngine()
        this.Start(late)
        events := late.Tick(121, true, true, true)
        this.Equal(events[1].Reason, "scheduler_late", "Excessive elapsed stall stops the burst")
        this.Equal(events[1].LagMs, 101, "Elapsed failure reports lateness beyond IntervalMs")
        this.Equal(this.CountKind(events, "move"), 0, "Excessive stall emits no movement")
        this.Equal(late.Tick(122, true, true, true).Length, 0, "Held trigger cannot resume a stalled burst")
        late.Tick(123, true, false, true)
        this.Equal(this.CountKind(late.Tick(124, true, true, true), "move"), 0,
            "Recovered burst starts without an old stalled dose")
        this.Equal(this.Movement(late.Tick(134, true, true, true)).Dy, 2,
            "Recovered burst integrates only its own elapsed time")
    }

    ElapsedSaturation() {
        engine := this.ElapsedEngine([{UntilMs: 10, Dx: 100, Dy: -100},
            {UntilMs: 100, Dx: 0.25, Dy: -0.25}], 20, 3000, 10000, 100, 3)
        this.Start(engine)
        movement := this.Movement(engine.Tick(10, true, true, true))
        this.Equal(movement.RawDx, 50, "Elapsed raw dose is integrated before clipping")
        this.Equal(movement.Dx, 3, "Integrated positive dose respects MaxStep")
        this.Equal(movement.Dy, -3, "Integrated negative dose respects MaxStep")
        totalX := 0
        totalY := 0
        for nowMs in [30, 50, 70, 90] {
            movement := this.Movement(engine.Tick(nowMs, true, true, true))
            totalX += movement.Dx
            totalY += movement.Dy
            this.Equal(Abs(movement.Dx) <= 1, true, "Saturated X never leaks into later intervals")
            this.Equal(Abs(movement.Dy) <= 1, true, "Saturated Y never leaks into later intervals")
        }
        this.Equal(totalX, 1, "Only four new quarter-count X doses accumulate after saturation")
        this.Equal(totalY, -1, "Only four new quarter-count Y doses accumulate after saturation")
    }

    ElapsedSafetyReset() {
        for interruption in ["focus", "left", "right", "rearm", "disarm"] {
            engine := this.ElapsedEngine([{UntilMs: 3000, Dx: 0.5, Dy: -0.5}])
            this.Start(engine)
            first := this.Movement(engine.Tick(10, true, true, true))
            this.Equal(first.Dx, 0, "A quarter count exists before interruption")
            switch interruption {
                case "focus":
                    events := engine.Tick(11, false, true, true)
                    this.Equal(engine.State, "paused_focus", "Elapsed focus loss pauses the engine")
                    this.Equal(engine.Tick(100, true, true, true)[1].Kind, "resumed",
                        "Elapsed focus return preserves the release latch")
                case "left":
                    events := engine.Tick(11, true, false, true)
                case "right":
                    events := engine.Tick(11, true, true, false)
                    this.Equal(engine.Tick(100, true, true, true).Length, 0,
                        "Restoring aim cannot resume an interrupted held trigger")
                case "rearm":
                    events := engine.Arm(11)
                    this.Equal(engine.Tick(100, true, true, true).Length, 0,
                        "Rearming with held trigger cannot continue elapsed integration")
                case "disarm":
                    events := engine.Disarm("manual", 11)
                    engine.Arm(100)
            }
            this.Equal(this.CountKind(events, "move"), 0, "Interruption never flushes a partial dose")
            engine.Tick(101, true, false, true)
            this.Equal(this.CountKind(engine.Tick(102, true, true, true), "move"), 0,
                "Every resumed burst starts without an impulse")
            totalX := 0
            totalY := 0
            for nowMs in [112, 122, 132] {
                movement := this.Movement(engine.Tick(nowMs, true, true, true))
                totalX += movement.Dx
                totalY += movement.Dy
            }
            this.Equal(totalX, 0, "Old X residue and interrupted time never cross burst boundaries")
            this.Equal(totalY, 0, "Old Y residue and interrupted time never cross burst boundaries")
            movement := this.Movement(engine.Tick(142, true, true, true))
            this.Equal(movement.Dx, 1, "Fresh burst accumulates exactly four new quarter counts")
            this.Equal(movement.Dy, -1, "Fresh negative accumulation is symmetric")
            this.Equal(engine.SessionStart, 0, "Elapsed resets do not extend the session lifetime")
        }

        for deadline in ["burst", "session"] {
            engine := deadline = "burst" ? this.ElapsedEngine(0, 20, 20)
                : this.ElapsedEngine(0, 20, 3000, 20)
            this.Start(engine)
            this.Movement(engine.Tick(10, true, true, true))
            events := engine.Tick(20, true, true, true)
            this.Equal(this.CountKind(events, "move"), 0, "Exact deadline cannot emit remaining elapsed dose")
            this.Equal(events[1].Reason, deadline = "burst" ? "burst_limit" : "session_limit",
                "Elapsed integration preserves lifetime limits")
        }
    }

    ElapsedMetadata() {
        this.Equal(this.Engine().Profile.MotionMode, "step", "Missing motion mode preserves the existing scheduler")
        profile := {Name: "elapsed-copy", IntervalMs: 20, MotionMode: "elapsed",
            TriggerMode: "continuous", Segments: [{UntilMs: 3000, Dx: 0, Dy: 4.5}]}
        limits := {MaxBurstMs: 3000, SessionLimitMs: 10000, MaxLateMs: 100, MaxStep: 12}
        engine := RecoilEngine(profile, limits)
        profile.MotionMode := "step"
        this.Equal(engine.Profile.MotionMode, "elapsed", "Elapsed mode is copied independently of the caller")
        for mode in ["invalid", "", 1] {
            profile.MotionMode := mode
            threw := false
            try RecoilEngine(profile, limits)
            catch ValueError
                threw := true
            this.Equal(threw, true, "Unknown motion mode is rejected")
        }
        profile.MotionMode := "elapsed"
        profile.TriggerMode := "single"
        threw := false
        try RecoilEngine(profile, limits)
        catch ValueError
            threw := true
        this.Equal(threw, true, "Elapsed integration cannot change single-shot semantics")
    }

    Fractions() {
        engine := this.Engine([{UntilMs: 100, Dx: 0.25, Dy: -0.75}])
        samples := [this.Movement(this.Start(engine))]
        for nowMs in [10, 20, 30]
            samples.Push(this.Movement(engine.Tick(nowMs, true, true, true)))
        sumX := 0
        sumY := 0
        for movement in samples {
            sumX += movement.Dx
            sumY += movement.Dy
            this.Equal(movement.RawDx, 0.25, "Raw fractional X retained")
            this.Equal(movement.RawDy, -0.75, "Raw fractional Y retained")
        }
        this.Equal(sumX, 1, "Positive fractions accumulate")
        this.Equal(sumY, -3, "Negative fractions accumulate")
        this.Equal(samples[1].Dx, 0, "Zero integer X remains a planned event")
        this.Equal(samples[1].Dy, 0, "Negative fraction truncates toward zero")
        engine.Tick(40, true, false, true)
        engine.Tick(41, true, false, false)
        for index, nowMs in [42, 52, 62, 72] {
            movement := this.Movement(engine.Tick(nowMs, true, true, true))
            this.Equal(movement.Dx, samples[index].Dx, "X sequence repeats after burst reset")
            this.Equal(movement.Dy, samples[index].Dy, "Y sequence repeats after burst reset")
        }
        reverse := this.Engine([{UntilMs: 100, Dx: -0.25, Dy: 0.75}])
        reverseSamples := [this.Movement(this.Start(reverse))]
        for nowMs in [10, 20, 30]
            reverseSamples.Push(this.Movement(reverse.Tick(nowMs, true, true, true)))
        for index, movement in reverseSamples {
            this.Equal(movement.Dx, -samples[index].Dx, "Negative X is symmetric")
            this.Equal(movement.Dy, -samples[index].Dy, "Positive Y is symmetric")
        }
    }

    StepBound() {
        engine := this.Engine([{UntilMs: 10, Dx: 100, Dy: -100}, {UntilMs: 100, Dx: 0.25, Dy: -0.25}],
            10, 100, 1000, 15, 3)
        movement := this.Movement(this.Start(engine))
        this.Equal(movement.Dx, 3, "Positive step capped")
        this.Equal(movement.Dy, -3, "Negative step capped")
        this.Equal(movement.RawDx, 100, "Unclamped raw X recorded")
        this.Equal(movement.RawDy, -100, "Unclamped raw Y recorded")
        movement := this.Movement(engine.Tick(10, true, true, true))
        this.Equal(movement.Dx, 0, "Discarded saturation is not carried into X residual")
        this.Equal(movement.Dy, 0, "Discarded saturation is not carried into Y residual")
        for nowMs in [20, 30, 40, 50, 60, 70, 80, 90] {
            movement := this.Movement(engine.Tick(nowMs, true, true, true))
            this.Equal(Abs(movement.Dx) <= 3, true, "Every X step respects bound")
            this.Equal(Abs(movement.Dy) <= 3, true, "Every Y step respects bound")
        }
    }

    GenerationAndShape() {
        engine := this.Engine()
        this.Equal(engine.Generation, 0, "Initial callback generation")
        this.Start(engine)
        this.Equal(engine.Generation, 1, "Arm changes generation")
        this.Shape(engine.Arm(1))
        this.Equal(engine.Generation, 2, "Repeated arm invalidates prior generation")
        this.Equal(engine.State, "wait_release", "Repeated arm restores release latch")
        this.Shape(engine.Disarm("test_stop"))
        this.Equal(engine.Generation, 3, "Disarm changes generation")
        engine.Disarm("test_stop")
        this.Equal(engine.Generation, 4, "Repeated disarm still invalidates callbacks")
    }

    ExactDisarmTime() {
        engine := this.Engine()
        this.Start(engine, 100)
        events := engine.Disarm("manual", 107)
        this.Shape(events)
        this.Equal(events[1].Kind, "burst_stop", "Exact manual stop records burst end")
        this.Equal(events[1].ElapsedMs, 7, "Manual stop records time between timer ticks")
        this.Equal(events[1].DueMs, 110, "Manual stop retains next planned due time")
        this.Equal(engine.State, "disabled", "Exact manual stop disarms")
        this.Equal(engine.Generation, 2, "Exact manual stop invalidates callback generation")
        threw := false
        try engine.Disarm("manual", 106)
        catch ValueError
            threw := true
        this.Equal(threw, true, "Exact disarm rejects backwards timestamps")
        this.Equal(engine.Generation, 2, "Rejected timestamp does not alter generation")
    }

    SingleEngine(minTrigger := 0, segments := 0, session := 1000) {
        if !IsObject(segments)
            segments := [{UntilMs: 100, Dx: 1, Dy: 2}]
        return RecoilEngine({Name: "single-test", IntervalMs: 10, Segments: segments,
            TriggerMode: "single", MinTriggerMs: minTrigger},
            {MaxBurstMs: 100, SessionLimitMs: session, MaxLateMs: 15, MaxStep: 8})
    }

    SingleHeld() {
        engine := this.SingleEngine()
        engine.Arm(0)
        this.Equal(engine.Tick(0, true, true, true).Length, 0, "Single initially held buttons suppressed")
        events := engine.Tick(1, true, false, true)
        this.Equal(events[1].Reason, "left_released", "Single initial arm accepts held aim")
        this.Equal(this.CountKind(events, "move"), 0, "Single initial release emits no movement")
        events := engine.Tick(3, true, true, true)
        this.Shape(events)
        this.Equal(events[1].Kind, "burst_start", "Single pulse opens burst before move")
        this.Movement(events)
        this.Equal(engine.State, "burst", "Single emitting tick satisfies state guard")
        this.Equal(engine.Armed, true, "Single emitting tick remains armed")
        events := engine.Tick(4, true, true, true)
        this.Shape(events)
        this.Equal(events.Length, 1, "Single next tick closes burst only")
        this.Equal(events[1].Kind, "burst_stop", "Single emits stop event")
        this.Equal(events[1].Reason, "single_pulse", "Single completion reason")
        this.Equal(events[1].ElapsedMs, 1, "Single stop records next observation time")
        this.Equal(engine.State, "wait_release", "Held single press waits for release")
        for nowMs in [5, 10, 50, 150]
            this.Equal(engine.Tick(nowMs, true, true, true).Length, 0, "Held single never repeats")
        this.Equal(engine.BurstId, 1, "Held press creates one burst")
    }

    SingleAdsClicks() {
        engine := this.SingleEngine()
        this.Movement(this.Start(engine, 0))
        events := engine.Tick(1, true, false, true)
        this.Shape(events)
        this.Equal(events[1].Reason, "single_pulse", "LMB release completes pulse")
        this.Equal(events[-1].Reason, "left_released", "Same observed release readies single mode")
        this.Equal(engine.State, "ready", "ADS may remain held between clicks")
        this.Movement(engine.Tick(2, true, true, true))
        this.Equal(engine.State, "burst", "Second pulse remains guard eligible")
        engine.Tick(3, true, true, true)
        this.Equal(engine.State, "wait_release", "Second held pulse waits")
        engine.Tick(4, true, false, true)
        this.Equal(engine.State, "ready", "Release after completion also readies")
        this.Movement(engine.Tick(5, true, true, true))
        this.Equal(engine.BurstId, 3, "Three physical clicks produce three bursts")
    }

    SingleCooldown() {
        engine := this.SingleEngine(100)
        this.Start(engine)
        engine.Tick(1, true, false, true)
        events := engine.Tick(30, true, true, true)
        this.Shape(events)
        this.Equal(events.Length, 1, "Early press has one rejection event")
        this.Equal(events[1].Kind, "trigger_rejected", "Early press is rejected")
        this.Equal(events[1].Reason, "cooldown", "Cooldown rejection reason")
        this.Equal(events[1].DueMs, 100, "Cooldown deadline is recorded")
        this.Equal(engine.BurstId, 1, "Rejected press does not open a burst")
        this.Equal(engine.State, "wait_release", "Rejected press is consumed")
        for nowMs in [99, 100, 110]
            this.Equal(engine.Tick(nowMs, true, true, true).Length, 0, "Early hold never creates delayed pulse")
        engine.Tick(111, true, false, true)
        this.Movement(engine.Tick(112, true, true, true))
        engine.Tick(113, true, false, true)
        this.Movement(engine.Tick(212, true, true, true))
        this.Equal(engine.BurstId, 3, "Exact cooldown boundary accepts a new physical click")

        rearmed := this.SingleEngine(100)
        this.Start(rearmed)
        rearmed.Disarm("manual", 1)
        rearmed.Arm(2)
        rearmed.Tick(2, true, false, false)
        events := rearmed.Tick(3, true, true, true)
        this.Equal(events[1].Kind, "trigger_rejected", "Rearming cannot reset single cooldown")
        this.Equal(events[1].DueMs, 100, "Cooldown persists across manual disarm")

        paused := this.SingleEngine(100)
        this.Start(paused)
        paused.Tick(1, false, true, true)
        this.Equal(paused._singleEmitted, false, "Focus pause clears a pending single pulse")
        events := paused.Tick(2, true, true, true)
        this.Equal(events.Length, 1, "Single held-trigger return only emits resumed")
        this.Equal(events[1].Kind, "resumed", "Single held-trigger return resumes intent")
        this.Equal(this.CountKind(events, "move"), 0, "Single return never repeats interrupted pulse")
        this.Equal(paused.Tick(3, true, true, true).Length, 0, "Single held trigger remains blocked after return")
        paused.Tick(4, true, false, true)
        events := paused.Tick(5, true, true, true)
        this.Equal(events[1].Kind, "trigger_rejected", "Focus pause cannot reset single cooldown")
        this.Equal(events[1].DueMs, 100, "Single cooldown deadline survives pause")
        this.Equal(paused.Tick(100, true, true, true).Length, 0, "Holding rejected press never fires after pause")
        paused.Tick(101, true, false, true)
        this.Movement(paused.Tick(102, true, true, true))
        this.Equal(paused.BurstId, 2, "Only a new valid click after pause starts another single pulse")
    }

    SingleRequiresLeftEdge() {
        engine := this.SingleEngine()
        engine.Arm(0)
        engine.Tick(0, true, false, false)
        this.Equal(engine.Tick(1, true, true, false).Length, 0, "LMB without ADS produces no pulse")
        this.Equal(engine.Tick(2, true, true, true).Length, 0, "Adding ADS to held LMB is not a new press")
        engine.Tick(3, true, false, true)
        this.Movement(engine.Tick(4, true, true, true))
        engine.Tick(5, true, true, false)
        this.Equal(engine.State, "wait_release", "Dropping ADS leaves LMB release requirement")
        this.Equal(engine.Tick(6, true, true, true).Length, 0, "Restoring ADS cannot replay same LMB press")
        engine.Tick(7, true, false, false)
        this.Movement(engine.Tick(8, true, true, true))
    }

    SingleSafetyReset() {
        engine := this.SingleEngine()
        this.Start(engine)
        engine.Tick(1, true, true, true)
        events := engine.Tick(2, false, false, true)
        this.Equal(events[-1].Reason, "focus_lost", "Single focus loss pauses even while release-latched")
        this.Equal(engine.State, "paused_focus", "Single preserves armed intent on focus loss")
        this.Equal(engine.Tick(3, true, false, true)[1].Kind, "resumed", "Single focus restoration emits resumed")
        this.Equal(engine.State, "wait_release", "Single return does not immediately ready")
        events := engine.Tick(4, true, false, true)
        this.Equal(events[1].Reason, "left_released", "Focus resume accepts released trigger with held aim")
        this.Equal(this.CountKind(events, "move"), 0, "Focus resume release cannot fire")
        this.Movement(engine.Tick(6, true, true, true))
        events := engine.Disarm("manual", 7)
        this.Equal(events[1].Kind, "burst_stop", "Manual stop closes pending single burst")
        this.Equal(events[1].Reason, "manual", "Manual reason takes priority over single completion")
        engine.Arm(8)
        events := engine.Tick(8, true, false, true)
        this.Equal(events[1].Reason, "left_released", "Manual rearm accepts held aim")
        this.Equal(this.CountKind(events, "move"), 0, "Manual rearm release cannot fire")
        this.Movement(engine.Tick(10, true, true, true))
        events := engine.Tick(11, false, true, true)
        this.Equal(events[1].Reason, "focus_lost", "Focus loss before completion closes pending pulse safely")
        this.Equal(this.CountKind(events, "move"), 0, "Focus loss cannot repeat a pulse")

        expired := this.SingleEngine(0, 0, 10)
        this.Start(expired, 0)
        events := expired.Tick(10, true, true, true)
        this.Equal(events[1].Reason, "session_limit", "Session expiry precedes pending pulse completion")
        this.Equal(expired.State, "expired", "Single respects session cap")
        this.Equal(this.CountKind(events, "move"), 0, "Expired single emits no extra pulse")
    }

    ContinuousSafetyReset() {
        engine := this.Engine(0, 10, 100, 50)
        this.Start(engine)
        events := engine.Tick(1, false, true, true)
        this.Equal(events[-1].Reason, "focus_lost", "Continuous focus loss pauses")
        this.Equal(engine.Generation, 2, "Continuous focus loss invalidates generation")
        this.Equal(engine.Tick(2, true, false, true)[1].Kind, "resumed", "Released trigger on return only resumes")
        this.Equal(engine.Tick(3, true, true, true).Length, 0, "Resumed engine still requires trigger release")
        engine.Tick(4, true, false, true)
        this.Movement(engine.Tick(5, true, true, true))
        this.Equal(engine.SessionStart, 0, "Focus resume keeps original session deadline")
        this.Equal(engine.Generation, 2, "Focus resume retains pause generation")
        engine.Disarm("profile_changed", 6)
        this.Equal(engine.Tick(7, true, false, true).Length, 0, "Configuration disarm cannot auto-arm on release")
        engine.Arm(8)
        this.Equal(engine.Tick(8, true, true, true).Length, 0, "Configuration rearm cannot send from held trigger")
        engine.Tick(9, true, false, true)
        this.Movement(engine.Tick(10, true, true, true))
        this.Equal(engine.SessionStart, 0, "Configuration disarm keeps original session deadline")
        events := engine.Tick(50, true, false, true)
        this.Equal(events[-1].Kind, "session_expired", "Session expiry precedes release readiness")
        this.Equal(engine.Armed, false, "Expired continuous engine cannot remain armed")
        this.Equal(this.CountKind(events, "move"), 0, "Expiry with held aim emits no movement")
    }

    SingleSegmentsAndFractions() {
        engine := this.SingleEngine(0, [{UntilMs: 1, Dx: 100, Dy: -100},
            {UntilMs: 100, Dx: 2, Dy: 3}])
        first := this.Movement(this.Start(engine))
        this.Equal(first.RawDx, 100, "Single uses first segment")
        this.Equal(first.Dx, 8, "Single obeys positive movement bound")
        this.Equal(first.Dy, -8, "Single obeys negative movement bound")
        this.Equal(this.CountKind(engine.Tick(50, true, true, true), "move"), 0,
            "Single never advances to later segments")
        fractional := this.SingleEngine(0, [{UntilMs: 100, Dx: 0.5, Dy: -0.5}])
        first := this.Movement(this.Start(fractional))
        fractional.Tick(1, true, false, true)
        second := this.Movement(fractional.Tick(2, true, true, true))
        this.Equal(first.Dx, 0, "Single fractional movement truncates")
        this.Equal(second.Dx, 0, "Single X fractions do not carry between clicks")
        this.Equal(second.Dy, 0, "Single Y fractions do not carry between clicks")
    }

    TriggerMetadata() {
        legacy := this.Engine()
        this.Equal(legacy.Profile.TriggerMode, "continuous", "Missing trigger mode is backward compatible")
        this.Equal(legacy.Profile.MinTriggerMs, 0, "Missing cooldown defaults to zero")
        profile := {Name: "copy-test", IntervalMs: 10, TriggerMode: "single", MinTriggerMs: 150,
            Segments: [{UntilMs: 100, Dx: 1, Dy: 2}]}
        limits := {MaxBurstMs: 100, SessionLimitMs: 1000, MaxLateMs: 15, MaxStep: 8}
        engine := RecoilEngine(profile, limits)
        profile.TriggerMode := "continuous"
        profile.MinTriggerMs := 0
        profile.Segments[1].Dy := 7
        this.Equal(engine.Profile.TriggerMode, "single", "Trigger mode is copied")
        this.Equal(engine.Profile.MinTriggerMs, 150, "Cooldown metadata is copied")
        this.Equal(this.Movement(this.Start(engine)).Dy, 2, "Segment remains independent of caller mutation")
        for mode in ["invalid", "", 1] {
            profile.TriggerMode := mode
            threw := false
            try RecoilEngine(profile, limits)
            catch ValueError
                threw := true
            this.Equal(threw, true, "Unknown trigger mode rejected")
        }
        profile.TriggerMode := "single"
        for cooldown in [-1, "invalid"] {
            profile.MinTriggerMs := cooldown
            threw := false
            try RecoilEngine(profile, limits)
            catch ValueError
                threw := true
            this.Equal(threw, true, "Invalid minimum trigger interval rejected")
        }
    }

    Validation() {
        threw := false
        try this.Engine([{UntilMs: 10, Dx: 1, Dy: 1}, {UntilMs: 10, Dx: 1, Dy: 1}])
        catch ValueError
            threw := true
        this.Equal(threw, true, "Non-increasing segment boundaries rejected")
        threw := false
        try this.Engine(0, 0)
        catch ValueError
            threw := true
        this.Equal(threw, true, "Zero interval rejected")
        engine := this.Engine()
        engine.Arm(10)
        threw := false
        try engine.Tick(9, true, false, false)
        catch ValueError
            threw := true
        this.Equal(threw, true, "Backwards timestamps rejected")
    }
}
