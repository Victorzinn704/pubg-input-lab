; Pure state machine. This file never reads or generates operating-system input.
class RecoilEngine {
    __New(profile, limits) {
        this._Validate(profile, limits)
        this.Profile := {Name: profile.Name, IntervalMs: profile.IntervalMs, Segments: [],
            TriggerMode: profile.HasOwnProp("TriggerMode") ? profile.TriggerMode : "continuous",
            MotionMode: profile.HasOwnProp("MotionMode") ? profile.MotionMode : "step",
            MinTriggerMs: profile.HasOwnProp("MinTriggerMs") ? profile.MinTriggerMs : 0}
        for segment in profile.Segments
            this.Profile.Segments.Push({UntilMs: segment.UntilMs, Dx: segment.Dx, Dy: segment.Dy})
        this.Limits := {MaxBurstMs: limits.MaxBurstMs, SessionLimitMs: limits.SessionLimitMs,
            MaxLateMs: limits.MaxLateMs, MaxStep: limits.MaxStep}
        this._burstLimit := Min(limits.MaxBurstMs, profile.Segments[-1].UntilMs)
        this.State := "disabled"
        this.Generation := 0
        this.BurstId := 0
        this.SessionStart := -1
        this.Armed := false
        this._hasFocused := false
        this._lastNow := -1
        this._lastTriggerMs := -1
        this._leftWasDown := false
        this._ResetBurst()
    }

    Arm(nowMs) {
        this._ObserveTime(nowMs)
        this.Generation += 1
        if this.SessionStart < 0
            this.SessionStart := nowMs
        if this.State = "expired" || nowMs - this.SessionStart >= this.Limits.SessionLimitMs
            return this._Expire(nowMs, false)
        events := []
        if this.State = "burst"
            events.Push(this._StopBurst("rearmed", nowMs))
        this._ResetBurst()
        this.Armed := true
        this.State := "wait_release"
        this._hasFocused := false
        events.Push(this._Event("armed", "release_required"))
        return events
    }

    Disarm(reason, nowMs := unset) {
        if IsSet(nowMs)
            this._ObserveTime(nowMs)
        this.Generation += 1
        events := []
        if this.State = "burst"
            events.Push(this._StopBurst(reason, this._lastNow))
        this.Armed := false
        if this.State != "expired"
            this.State := "disabled"
        this._hasFocused := false
        this._ResetBurst()
        events.Push(this._Event("disarmed", reason))
        return events
    }

    Tick(nowMs, focused, leftPhysical, rightPhysical) {
        this._ObserveTime(nowMs)
        if !this.Armed
            return []
        if nowMs - this.SessionStart >= this.Limits.SessionLimitMs
            return this._Expire(nowMs)
        if !focused {
            if !this._hasFocused || this.State = "paused_focus"
                return []
            return this._PauseFocus(nowMs)
        }
        this._hasFocused := true
        if this.State = "paused_focus" {
            ; Returning focus preserves intent, never a pending shot or movement.
            ; Observe a released trigger on a later focused tick before readiness.
            this.State := "wait_release"
            this._leftWasDown := leftPhysical
            return [this._Event("resumed", "focus_restored")]
        }

        leftPressed := leftPhysical && !this._leftWasDown
        this._leftWasDown := leftPhysical
        if this.State = "burst" && this._singleEmitted {
            ; Keep burst active for the emitting tick's pre-send guard; close it here.
            events := [this._StopBurst("single_pulse", nowMs)]
            if !leftPhysical {
                this.State := "ready"
                events.Push(this._Event("ready", "left_released"))
            }
            return events
        }

        if this.State = "wait_release" {
            if !leftPhysical {
                this.State := "ready"
                return [this._Event("ready", "left_released")]
            }
            return []
        }

        events := []
        if this.State = "ready" {
            if !leftPhysical || !rightPhysical
                return events
            if this.Profile.TriggerMode = "single" {
                if !leftPressed
                    return events
                if this._lastTriggerMs >= 0 && nowMs - this._lastTriggerMs < this.Profile.MinTriggerMs {
                    ; Consume this press rather than firing later when the cooldown ends.
                    this.State := "wait_release"
                    return [this._Event("trigger_rejected", "cooldown", 0,
                        this._lastTriggerMs + this.Profile.MinTriggerMs)]
                }
                this._lastTriggerMs := nowMs
            }
            this.BurstId += 1
            this.State := "burst"
            this._burstStart := nowMs
            this._lastMotion := nowMs
            this._due := nowMs + (this.Profile.MotionMode = "elapsed" ? this.Profile.IntervalMs : 0)
            this._residualX := 0.0
            this._residualY := 0.0
            events.Push(this._Event("burst_start", "buttons_held", 0, nowMs))
        }

        elapsed := nowMs - this._burstStart
        if !leftPhysical || !rightPhysical {
            events.Push(this._StopBurst("button_released", nowMs))
            if !leftPhysical {
                this.State := "ready"
                events.Push(this._Event("ready", "left_released"))
            }
            return events
        }
        if elapsed >= this._burstLimit {
            events.Push(this._StopBurst("burst_limit", nowMs))
            return events
        }
        if this.Profile.MotionMode = "elapsed"
            return this._ElapsedMove(nowMs, elapsed, events)
        if nowMs < this._due
            return events
        lag := nowMs - this._due
        if lag > this.Limits.MaxLateMs {
            events.Push(this._StopBurst("scheduler_late", nowMs))
            return events
        }

        ; Use actual elapsed time, never a queued count of missed intervals.
        for segment in this.Profile.Segments {
            if elapsed < segment.UntilMs {
                rawX := segment.Dx
                rawY := segment.Dy
                break
            }
        }
        events.Push(this._QuantizedMove(rawX, rawY, elapsed, this._due, lag))
        if this.Profile.TriggerMode = "single"
            this._singleEmitted := true
        ; Preserve cadence across small jitter; discard missed intervals after a stall.
        ; Never replay movements or emit more than one movement in a tick.
        this._due := lag < this.Profile.IntervalMs
            ? this._due + this.Profile.IntervalMs : nowMs + this.Profile.IntervalMs
        return events
    }

    _ElapsedMove(nowMs, elapsed, events) {
        ; Sample-driven integration: no initial pulse or queued catch-up movements.
        delta := nowMs - this._lastMotion
        if delta <= 0
            return events
        lag := Max(0, delta - this.Profile.IntervalMs)
        if lag > this.Limits.MaxLateMs {
            events.Push(this._StopBurst("scheduler_late", nowMs))
            return events
        }
        windowStart := elapsed - Min(delta, this.Profile.IntervalMs)
        rawX := 0.0
        rawY := 0.0
        segmentStart := 0
        for segment in this.Profile.Segments {
            duration := Max(0, Min(elapsed, segment.UntilMs) - Max(windowStart, segmentStart))
            rawX += segment.Dx * duration / this.Profile.IntervalMs
            rawY += segment.Dy * duration / this.Profile.IntervalMs
            segmentStart := segment.UntilMs
            if segmentStart >= elapsed
                break
        }
        ; Drop older elapsed time permanently, retaining only sub-count rounding residue.
        this._lastMotion := nowMs
        this._due := nowMs + this.Profile.IntervalMs
        events.Push(this._QuantizedMove(rawX, rawY, elapsed, nowMs - lag, lag))
        return events
    }

    _QuantizedMove(rawX, rawY, elapsed, due, lag) {
        boundedX := Max(-this.Limits.MaxStep, Min(this.Limits.MaxStep, rawX + this._residualX))
        boundedY := Max(-this.Limits.MaxStep, Min(this.Limits.MaxStep, rawY + this._residualY))
        dx := boundedX < 0 ? Ceil(boundedX) : Floor(boundedX)
        dy := boundedY < 0 ? Ceil(boundedY) : Floor(boundedY)
        this._residualX := boundedX - dx
        this._residualY := boundedY - dy
        return this._Event("move", "scheduled", elapsed, due, lag, dx, dy, rawX, rawY)
    }

    _PauseFocus(nowMs) {
        ; Invalidate the previous sending generation before producing stop events.
        this.Generation += 1
        events := []
        if this.State = "burst"
            events.Push(this._StopBurst("focus_lost", nowMs))
        this._ResetBurst()
        this._leftWasDown := false
        this.State := "paused_focus"
        events.Push(this._Event("paused", "focus_lost"))
        return events
    }

    _Expire(nowMs, bumpGeneration := true) {
        events := []
        if this.State = "burst"
            events.Push(this._StopBurst("session_limit", nowMs))
        if bumpGeneration
            this.Generation += 1
        this.Armed := false
        this.State := "expired"
        this._hasFocused := false
        this._ResetBurst()
        events.Push(this._Event("session_expired", "session_limit"))
        return events
    }

    _StopBurst(reason, nowMs) {
        event := this._Event("burst_stop", reason, nowMs - this._burstStart,
            this._due, Max(0, nowMs - this._due))
        this.State := "wait_release"
        this._ResetBurst()
        return event
    }

    _ResetBurst() {
        this._burstStart := -1
        this._lastMotion := -1
        this._due := -1
        this._residualX := 0.0
        this._residualY := 0.0
        this._singleEmitted := false
    }

    _Event(kind, reason := "", elapsed := 0, due := 0, lag := 0, dx := 0, dy := 0, rawDx := 0, rawDy := 0) {
        return {Kind: kind, Reason: reason, Burst: this.BurstId, ElapsedMs: elapsed,
            DueMs: due, LagMs: lag, Dx: dx, Dy: dy, RawDx: rawDx, RawDy: rawDy}
    }

    _ObserveTime(nowMs) {
        if !IsNumber(nowMs) || nowMs < 0 || nowMs < this._lastNow
            throw ValueError("Engine time must be nonnegative and monotonic.")
        this._lastNow := nowMs
    }

    _Validate(profile, limits) {
        if profile.HasOwnProp("MotionMode") {
            if profile.MotionMode != "step" && profile.MotionMode != "elapsed"
                throw ValueError("MotionMode must be step or elapsed.")
            if profile.MotionMode = "elapsed" && profile.HasOwnProp("TriggerMode") && profile.TriggerMode = "single"
                throw ValueError("Elapsed motion requires continuous trigger mode.")
        }
        if profile.HasOwnProp("TriggerMode") && profile.TriggerMode != "continuous" && profile.TriggerMode != "single"
            throw ValueError("TriggerMode must be continuous or single.")
        if profile.HasOwnProp("MinTriggerMs") && (!IsNumber(profile.MinTriggerMs) || profile.MinTriggerMs < 0)
            throw ValueError("MinTriggerMs must be nonnegative.")
        if !IsNumber(profile.IntervalMs) || profile.IntervalMs <= 0
            throw ValueError("IntervalMs must be positive.")
        if !(profile.Segments is Array) || profile.Segments.Length = 0
            throw ValueError("At least one profile segment is required.")
        previousEnd := 0
        for segment in profile.Segments {
            if !IsNumber(segment.UntilMs) || segment.UntilMs <= previousEnd
                throw ValueError("Segment end times must increase strictly from zero.")
            if !IsNumber(segment.Dx) || !IsNumber(segment.Dy)
                throw ValueError("Segment movements must be numeric.")
            previousEnd := segment.UntilMs
        }
        if !IsNumber(limits.MaxBurstMs) || limits.MaxBurstMs <= 0
            throw ValueError("MaxBurstMs must be positive.")
        if !IsNumber(limits.SessionLimitMs) || limits.SessionLimitMs <= 0
            throw ValueError("SessionLimitMs must be positive.")
        if !IsNumber(limits.MaxLateMs) || limits.MaxLateMs < 0
            throw ValueError("MaxLateMs must be nonnegative.")
        if !IsNumber(limits.MaxStep) || limits.MaxStep < 1
            throw ValueError("MaxStep must be at least one pixel per axis.")
    }
}
