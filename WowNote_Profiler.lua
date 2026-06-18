-- WowNote_Profiler.lua
-- Low-overhead, WowNote-only profiler for WoW 3.3.5a.
--
-- The client CPU API may report zero even with scriptProfile enabled. This module
-- therefore measures only instrumented WowNote handlers with debugprofilestop.
-- Global frame duration is retained only as correlation context for visible hitches;
-- no CPU or memory values from other addons are read, stored or displayed.

WowNoteProfiler = WowNoteProfiler or {}
local P = WowNoteProfiler

local ADDON_NAME = "WowNote"
local SAMPLE_INTERVAL = 10.0
local TIMELINE_INTERVAL = 1.0
local TIMELINE_SAMPLE_LIMIT = 300
local TIMELINE_REPORT_LIMIT = 120
local MEMORY_SAMPLE_LIMIT = 120
local HITCH_LIMIT = 30
local REPORT_TIMER_LIMIT = 30
local REPORT_EVENT_LIMIT = 20
local LONG_PAUSE_SECONDS = 1.5
local HITCH_THRESHOLD_MS = 50

local samplerFrame
local profilerFrame
local reportEdit
local statusText
local summaryText
local toggleButton
local detailButton
local reportScroll
local timelineMetricText
local timelinePreviousButton
local timelineNextButton
local uiElapsed = 0
local currentView = "report"
local selectedTimelineMetric = "total"
local ApplyInstrumentationState
local ApplyRuntimeApiState
local UpdateProfilerFrameScript
local EnsureSamplerFrame
local wrappedHandlers = setmetatable({}, { __mode = "k" })
local activeScriptFrames = setmetatable({}, { __mode = "k" })

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffeda55fWowNote Profiler:|r " .. tostring(message or ""))
    end
end

local function NowMs()
    if debugprofilestop then return debugprofilestop() end
    if GetTime then return GetTime() * 1000 end
    return 0
end

local function NowSeconds()
    if GetTime then return GetTime() end
    return 0
end

local function SafeNumber(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback or 0 end
    return value
end

local function FormatNumber(value, decimals)
    value = SafeNumber(value, 0)
    decimals = decimals or 2
    return string.format("%." .. tostring(decimals) .. "f", value)
end

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(SafeNumber(seconds, 0)))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

local function PushRing(ring, value, limit)
    ring.values = ring.values or {}
    ring.index = ring.index or 1
    ring.count = ring.count or 0
    ring.values[ring.index] = value
    ring.index = ring.index + 1
    if ring.index > limit then ring.index = 1 end
    if ring.count < limit then ring.count = ring.count + 1 end
end

local function RingToOrderedList(ring, limit)
    local list = {}
    if not ring or not ring.values or not ring.count or ring.count <= 0 then return list end
    local start = ring.index - ring.count
    while start <= 0 do start = start + limit end
    local i
    for i = 1, ring.count do
        local index = start + i - 1
        while index > limit do index = index - limit end
        list[i] = ring.values[index]
    end
    return list
end

local function FindAddonIndex()
    if not GetNumAddOns or not GetAddOnInfo then return nil end
    local i
    for i = 1, GetNumAddOns() do
        local name = GetAddOnInfo(i)
        if name == ADDON_NAME then return i end
    end
    return nil
end

local function EnsureConfig()
    if type(WowNoteDB) ~= "table" then return nil end
    if type(WowNoteDB.profiler) ~= "table" then WowNoteDB.profiler = {} end
    if WowNoteDB.profiler.idleSafeVersion ~= 2 then
        -- Migrate older profiler versions to a disabled-by-default state once.
        WowNoteDB.profiler.enabled = false
        WowNoteDB.profiler.idleSafeVersion = 2
    elseif WowNoteDB.profiler.enabled == nil then
        WowNoteDB.profiler.enabled = false
    end
    if WowNoteDB.profiler.detailed == nil then WowNoteDB.profiler.detailed = true end
    return WowNoteDB.profiler
end

local function NewTimelineWindow()
    return {
        frameCount = 0,
        maxFrameMs = 0,
        totalWowNoteMs = 0,
        maxWowNoteFrameMs = 0,
        maxWowNoteFrameTopName = nil,
        maxWowNoteFrameTopMs = 0,
        callCount = 0,
        handlerTotals = {},
        handlerCalls = {},
        topSingleName = nil,
        topSingleMs = 0,
        hitches = 0,
        likelyHitches = 0,
        contributedHitches = 0,
    }
end

local function NewData()
    return {
        startedAt = NowSeconds(),
        endedAt = nil,
        frames = {
            currentMs = 0,
            maxMs = 0,
            hitches50 = 0,
            hitches100 = 0,
            hitches250 = 0,
            hitches500 = 0,
            likelyWowNoteHitches = 0,
            contributedWowNoteHitches = 0,
            notAttributedHitches = 0,
            longPauses = 0,
            lastMeasuredMs = 0,
            lastTopMs = 0,
            lastTopName = nil,
        },
        memory = {
            addonInitial = nil,
            addonCurrent = 0,
            addonPeak = 0,
            addonMin = nil,
            history = { values = {}, index = 1, count = 0 },
        },
        timers = {},
        events = {},
        counters = {},
        gauges = {},
        comm = {},
        hitches = {},
        marks = {},
        timeline = { values = {}, index = 1, count = 0 },
        timelineWindow = NewTimelineWindow(),
        timelineAccumulator = 0,
        sampleAccumulator = SAMPLE_INTERVAL,
        currentFrameMeasuredMs = 0,
        currentFrameTopMs = 0,
        currentFrameTopName = nil,
        profilerSampleCount = 0,
        profilerSampleTotalMs = 0,
        profilerSampleMaxMs = 0,
    }
end

P.enabled = P.enabled == true
P.detailed = P.detailed ~= false
P.data = P.data or NewData()
P.addonIndex = P.addonIndex or nil

function P:IsEnabled()
    return self.enabled == true
end

function P:IsDetailed()
    return self.enabled == true and self.detailed == true
end

function P:SampleWowNote(initial)
    if not self:IsEnabled() then return end
    local data = self.data
    self.addonIndex = self.addonIndex or FindAddonIndex()

    local addonMemory = data.memory.addonCurrent or 0
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage and self.addonIndex then
        pcall(UpdateAddOnMemoryUsage)
        local ok, value = pcall(GetAddOnMemoryUsage, self.addonIndex)
        if ok then addonMemory = SafeNumber(value, addonMemory) end
    end
    data.memory.addonCurrent = addonMemory
    if data.memory.addonInitial == nil or initial then data.memory.addonInitial = addonMemory end
    if data.memory.addonMin == nil or addonMemory < data.memory.addonMin then data.memory.addonMin = addonMemory end
    if addonMemory > data.memory.addonPeak then data.memory.addonPeak = addonMemory end
    PushRing(data.memory.history, {
        at = NowSeconds() - data.startedAt,
        addon = addonMemory,
    }, MEMORY_SAMPLE_LIMIT)
end

function P:Reset(silent)
    self.data = NewData()
    self.addonIndex = FindAddonIndex()
    if self:IsEnabled() then
        self:SampleWowNote(true)
    else
        self.data.endedAt = self.data.startedAt
    end
    if not silent then Print("WowNote profiler session reset.") end
end

function P:SetEnabled(enabled, silent)
    local wasEnabled = self.enabled == true
    self.enabled = enabled and true or false
    local cfg = EnsureConfig()
    if cfg then cfg.enabled = self.enabled end

    if self.enabled and not wasEnabled then
        self:Reset(true)
    elseif not self.enabled and wasEnabled then
        self.data.endedAt = NowSeconds()
    end
    if self.enabled and EnsureSamplerFrame then EnsureSamplerFrame() end
    if samplerFrame then
        samplerFrame:SetScript("OnUpdate", self.enabled and self._SamplerOnUpdate or nil)
    end
    if ApplyInstrumentationState then ApplyInstrumentationState() end
    if ApplyRuntimeApiState then ApplyRuntimeApiState() end
    if UpdateProfilerFrameScript then UpdateProfilerFrameScript() end

    if not silent then
        if self.enabled then
            Print("enabled; collecting WowNote handlers, WowNote memory and WowNote communication only.")
        else
            Print("disabled; sampler removed and original WowNote handlers restored without timing wrappers.")
        end
    end
    self:RefreshUI(true)
end

function P:SetDetailed(enabled, silent)
    self.detailed = enabled and true or false
    local cfg = EnsureConfig()
    if cfg then cfg.detailed = self.detailed end
    if ApplyInstrumentationState then ApplyInstrumentationState() end
    if not silent then
        Print(self.detailed and "per-handler timing enabled." or "per-handler timing disabled; only lightweight WowNote memory and hitch context remain.")
    end
    self:RefreshUI(true)
end

local function ModuleName(metricName)
    metricName = tostring(metricName or "Unknown")
    return string.match(metricName, "^([^.]+)") or metricName
end

function P:RecordTimer(name, durationMs, scriptType)
    if not self:IsDetailed() then return end
    name = tostring(name or "Unknown")
    durationMs = math.max(0, SafeNumber(durationMs, 0))

    local bucket = self.data.timers[name]
    if not bucket then
        bucket = {
            count = 0,
            totalMs = 0,
            maxMs = 0,
            lastMs = 0,
            over1 = 0,
            over5 = 0,
            over10 = 0,
            scriptType = scriptType,
        }
        self.data.timers[name] = bucket
    end
    bucket.count = bucket.count + 1
    bucket.totalMs = bucket.totalMs + durationMs
    bucket.lastMs = durationMs
    if durationMs > bucket.maxMs then bucket.maxMs = durationMs end
    if durationMs >= 1 then bucket.over1 = bucket.over1 + 1 end
    if durationMs >= 5 then bucket.over5 = bucket.over5 + 1 end
    if durationMs >= 10 then bucket.over10 = bucket.over10 + 1 end

    local data = self.data
    data.currentFrameMeasuredMs = data.currentFrameMeasuredMs + durationMs
    if durationMs > data.currentFrameTopMs then
        data.currentFrameTopMs = durationMs
        data.currentFrameTopName = name
    end

    local window = data.timelineWindow
    window.totalWowNoteMs = window.totalWowNoteMs + durationMs
    window.callCount = window.callCount + 1
    window.handlerTotals[name] = SafeNumber(window.handlerTotals[name], 0) + durationMs
    window.handlerCalls[name] = SafeNumber(window.handlerCalls[name], 0) + 1
    if durationMs > window.topSingleMs then
        window.topSingleMs = durationMs
        window.topSingleName = name
    end
end

function P:RecordEvent(handlerName, eventName, durationMs)
    if not self:IsDetailed() then return end
    eventName = tostring(eventName or "UNKNOWN")
    local key = tostring(handlerName or "Unknown") .. " / " .. eventName
    local bucket = self.data.events[key]
    if not bucket then
        bucket = { count = 0, totalMs = 0, maxMs = 0 }
        self.data.events[key] = bucket
    end
    durationMs = math.max(0, SafeNumber(durationMs, 0))
    bucket.count = bucket.count + 1
    bucket.totalMs = bucket.totalMs + durationMs
    if durationMs > bucket.maxMs then bucket.maxMs = durationMs end
end

function P:AddCounter(name, amount)
    if not self:IsEnabled() then return end
    name = tostring(name or "Unknown")
    self.data.counters[name] = SafeNumber(self.data.counters[name], 0) + SafeNumber(amount, 1)
end

function P:SetGauge(name, value)
    if not self:IsEnabled() then return end
    self.data.gauges[tostring(name or "Unknown")] = SafeNumber(value, 0)
end

function P:RecordComm(direction, route, byteCount, success)
    if not self:IsEnabled() then return end
    local key = tostring(direction or "?") .. " " .. tostring(route or "unknown")
    local bucket = self.data.comm[key]
    if not bucket then
        bucket = { packets = 0, bytes = 0, failed = 0 }
        self.data.comm[key] = bucket
    end
    bucket.packets = bucket.packets + 1
    bucket.bytes = bucket.bytes + math.max(0, SafeNumber(byteCount, 0))
    if success == false then bucket.failed = bucket.failed + 1 end
end

function P:Mark(label)
    if not self:IsEnabled() then Print("Profiler is disabled."); return end
    label = tostring(label or "manual")
    local entry = {
        at = NowSeconds() - self.data.startedAt,
        label = label,
        frameMs = self.data.frames.currentMs,
        wowNoteMs = self.data.frames.lastMeasuredMs,
        addonMemory = self.data.memory.addonCurrent,
        topName = self.data.frames.lastTopName,
        topMs = self.data.frames.lastTopMs,
    }
    table.insert(self.data.marks, entry)
    while table.getn(self.data.marks) > 20 do table.remove(self.data.marks, 1) end
    Print("marker added: " .. label)
end

function P:WrapScript(metricName, scriptType, handler)
    if type(handler) ~= "function" then return handler end
    local cache = wrappedHandlers[handler]
    if not cache then
        cache = {}
        wrappedHandlers[handler] = cache
    end
    local key = tostring(scriptType or "Script") .. "|" .. tostring(metricName or "Unknown")
    if cache[key] then return cache[key] end

    local wrapped = function(...)
        local startMs = NowMs()
        local result = handler(...)
        local durationMs = NowMs() - startMs
        if durationMs < 0 then durationMs = 0 end
        P:RecordTimer(metricName, durationMs, scriptType)
        if scriptType == "OnEvent" then
            P:RecordEvent(metricName, select(2, ...), durationMs)
        end
        return result
    end
    cache[key] = wrapped
    return wrapped
end

ApplyInstrumentationState = function()
    local useWrapped = P:IsDetailed()
    local frame, scripts, scriptType, entry
    for frame, scripts in pairs(activeScriptFrames) do
        if frame and frame.SetScript and type(scripts) == "table" then
            for scriptType, entry in pairs(scripts) do
                if type(entry) == "table" then
                    if useWrapped and not entry.wrapped then
                        entry.wrapped = P:WrapScript(entry.name, scriptType, entry.original)
                    end
                    frame:SetScript(scriptType, useWrapped and entry.wrapped or entry.original)
                end
            end
        end
    end
end

function WowNoteProfiler_SetScript(frame, scriptType, metricName, handler)
    if not frame or not frame.SetScript then return end
    local scripts = activeScriptFrames[frame]
    if not scripts then
        scripts = {}
        activeScriptFrames[frame] = scripts
    end
    if type(handler) ~= "function" then
        scripts[scriptType] = nil
        frame:SetScript(scriptType, handler)
        return
    end

    local entry = {
        name = tostring(metricName or "Unknown"),
        original = handler,
        wrapped = nil,
    }
    if P:IsDetailed() then
        entry.wrapped = P:WrapScript(entry.name, scriptType, handler)
    end
    scripts[scriptType] = entry
    frame:SetScript(scriptType, entry.wrapped or entry.original)
end

local function GetActiveScriptNames(scriptType)
    local names = {}
    local seen = {}
    local _, scripts, entry
    local frame
    for frame, scripts in pairs(activeScriptFrames) do
        entry = scripts and scripts[scriptType]
        local name = type(entry) == "table" and entry.name or nil
        local actuallyActive = scriptType ~= "OnUpdate" or not frame.IsShown or frame:IsShown()
        if name and actuallyActive and not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

local function RuntimeRecordComm(direction, route, byteCount, success)
    P:RecordComm(direction, route, byteCount, success)
end

local function RuntimeAddCounter(name, amount)
    P:AddCounter(name, amount)
end

local function RuntimeSetGauge(name, value)
    P:SetGauge(name, value)
end

ApplyRuntimeApiState = function()
    if P:IsEnabled() then
        WowNoteProfiler_RecordComm = RuntimeRecordComm
        WowNoteProfiler_AddCounter = RuntimeAddCounter
        WowNoteProfiler_SetGauge = RuntimeSetGauge
    else
        -- Call sites guard these globals, so nil removes disabled-call overhead.
        WowNoteProfiler_RecordComm = nil
        WowNoteProfiler_AddCounter = nil
        WowNoteProfiler_SetGauge = nil
    end
end

local function AttributionLevel(frameMs, measuredMs, topMs)
    frameMs = SafeNumber(frameMs, 0)
    measuredMs = SafeNumber(measuredMs, 0)
    topMs = SafeNumber(topMs, 0)
    if frameMs < HITCH_THRESHOLD_MS then return "none" end
    local ratio = frameMs > 0 and measuredMs / frameMs or 0
    if measuredMs >= 10 and ratio >= 0.50 then return "likely" end
    if topMs >= 5 or (measuredMs >= 3 and ratio >= 0.15) then return "contributed" end
    return "not_attributed"
end

local function AttributionText(frameMs, measuredMs, topMs, topName)
    local level = AttributionLevel(frameMs, measuredMs, topMs)
    topName = tostring(topName or "none")
    if level == "likely" then return "WowNote likely caused it: " .. topName end
    if level == "contributed" then return "WowNote contributed: " .. topName end
    if level == "not_attributed" then return "not attributed to measured WowNote code" end
    if SafeNumber(measuredMs, 0) >= 5 then return "WowNote spike without >=50 ms hitch: " .. topName end
    return "normal"
end

local function AddHitch(frameMs, measuredMs, topName, topMs)
    local data = P.data
    local level = AttributionLevel(frameMs, measuredMs, topMs)
    if level == "likely" then
        data.frames.likelyWowNoteHitches = data.frames.likelyWowNoteHitches + 1
    elseif level == "contributed" then
        data.frames.contributedWowNoteHitches = data.frames.contributedWowNoteHitches + 1
    else
        data.frames.notAttributedHitches = data.frames.notAttributedHitches + 1
    end
    local entry = {
        at = NowSeconds() - data.startedAt,
        frameMs = frameMs,
        measuredMs = measuredMs,
        topName = topName or "none",
        topMs = topMs or 0,
        level = level,
        combat = InCombatLockdown and InCombatLockdown() and true or false,
        addonMemory = data.memory.addonCurrent,
    }
    table.insert(data.hitches, entry)
    while table.getn(data.hitches) > HITCH_LIMIT do table.remove(data.hitches, 1) end
end

local function PushTimelineWindow(data)
    local window = data.timelineWindow
    if not window or window.frameCount <= 0 then
        data.timelineWindow = NewTimelineWindow()
        return
    end

    local topName
    local topTotalMs = 0
    local name, value
    for name, value in pairs(window.handlerTotals) do
        value = SafeNumber(value, 0)
        if value > topTotalMs then
            topTotalMs = value
            topName = name
        end
    end

    local handlerTotals = {}
    local handlerCalls = {}
    local moduleTotals = {}
    local moduleCalls = {}
    for name, value in pairs(window.handlerTotals) do
        handlerTotals[name] = SafeNumber(value, 0)
        handlerCalls[name] = SafeNumber(window.handlerCalls[name], 0)
        local module = ModuleName(name)
        moduleTotals[module] = SafeNumber(moduleTotals[module], 0) + handlerTotals[name]
        moduleCalls[module] = SafeNumber(moduleCalls[module], 0) + handlerCalls[name]
    end

    PushRing(data.timeline, {
        at = NowSeconds() - data.startedAt,
        maxFrameMs = window.maxFrameMs,
        wowNoteTotalMs = window.totalWowNoteMs,
        wowNoteMaxFrameMs = window.maxWowNoteFrameMs,
        wowNoteCalls = window.callCount,
        handlerTotals = handlerTotals,
        handlerCalls = handlerCalls,
        moduleTotals = moduleTotals,
        moduleCalls = moduleCalls,
        topName = topName or "none",
        topModule = ModuleName(topName or "none"),
        topTotalMs = topTotalMs,
        topSingleName = window.topSingleName or "none",
        topSingleMs = window.topSingleMs,
        maxWowNoteFrameTopName = window.maxWowNoteFrameTopName or "none",
        maxWowNoteFrameTopMs = window.maxWowNoteFrameTopMs,
        hitches = window.hitches,
        likelyHitches = window.likelyHitches,
        contributedHitches = window.contributedHitches,
        addonMemory = data.memory.addonCurrent,
        combat = InCombatLockdown and InCombatLockdown() and true or false,
    }, TIMELINE_SAMPLE_LIMIT)
    data.timelineWindow = NewTimelineWindow()
end

function P._SamplerOnUpdate(self, elapsed)
    local sampleStart = NowMs()
    local data = P.data
    elapsed = SafeNumber(elapsed, 0)
    local frameMs = elapsed * 1000

    local measuredMs = data.currentFrameMeasuredMs
    local topMs = data.currentFrameTopMs
    local topName = data.currentFrameTopName
    data.currentFrameMeasuredMs = 0
    data.currentFrameTopMs = 0
    data.currentFrameTopName = nil

    data.frames.currentMs = frameMs
    data.frames.lastMeasuredMs = measuredMs
    data.frames.lastTopMs = topMs
    data.frames.lastTopName = topName

    if elapsed > 0 and elapsed <= LONG_PAUSE_SECONDS then
        if frameMs > data.frames.maxMs then data.frames.maxMs = frameMs end
        local window = data.timelineWindow
        window.frameCount = window.frameCount + 1
        if frameMs > window.maxFrameMs then window.maxFrameMs = frameMs end
        if measuredMs > window.maxWowNoteFrameMs then
            window.maxWowNoteFrameMs = measuredMs
            window.maxWowNoteFrameTopName = topName
            window.maxWowNoteFrameTopMs = topMs
        end

        if frameMs >= 50 then data.frames.hitches50 = data.frames.hitches50 + 1 end
        if frameMs >= 100 then data.frames.hitches100 = data.frames.hitches100 + 1 end
        if frameMs >= 250 then data.frames.hitches250 = data.frames.hitches250 + 1 end
        if frameMs >= 500 then data.frames.hitches500 = data.frames.hitches500 + 1 end
        if frameMs >= HITCH_THRESHOLD_MS then
            window.hitches = window.hitches + 1
            local level = AttributionLevel(frameMs, measuredMs, topMs)
            if level == "likely" then window.likelyHitches = window.likelyHitches + 1 end
            if level == "contributed" then window.contributedHitches = window.contributedHitches + 1 end
            AddHitch(frameMs, measuredMs, topName, topMs)
        end
    elseif elapsed > LONG_PAUSE_SECONDS then
        data.frames.longPauses = data.frames.longPauses + 1
    end

    data.timelineAccumulator = data.timelineAccumulator + elapsed
    if data.timelineAccumulator >= TIMELINE_INTERVAL then
        data.timelineAccumulator = data.timelineAccumulator - TIMELINE_INTERVAL
        PushTimelineWindow(data)
    end

    data.sampleAccumulator = data.sampleAccumulator + elapsed
    if data.sampleAccumulator >= SAMPLE_INTERVAL then
        data.sampleAccumulator = data.sampleAccumulator - SAMPLE_INTERVAL
        P:SampleWowNote(false)
        if profilerFrame and profilerFrame:IsShown() then P:RefreshUI(true) end
    end

    local sampleCost = NowMs() - sampleStart
    if sampleCost < 0 then sampleCost = 0 end
    data.profilerSampleCount = data.profilerSampleCount + 1
    data.profilerSampleTotalMs = data.profilerSampleTotalMs + sampleCost
    if sampleCost > data.profilerSampleMaxMs then data.profilerSampleMaxMs = sampleCost end
end

local function BuildSortedBuckets(source, sortKey)
    local list = {}
    local name, bucket
    for name, bucket in pairs(source or {}) do
        table.insert(list, { name = name, bucket = bucket })
    end
    table.sort(list, function(a, b)
        local av = SafeNumber(a.bucket[sortKey], 0)
        local bv = SafeNumber(b.bucket[sortKey], 0)
        if av == bv then return a.name < b.name end
        return av > bv
    end)
    return list
end

local function BuildModuleBuckets()
    local modules = {}
    local handlerName, bucket
    for handlerName, bucket in pairs(P.data.timers or {}) do
        local module = ModuleName(handlerName)
        local target = modules[module]
        if not target then
            target = { count = 0, totalMs = 0, maxMs = 0, over5 = 0, over10 = 0 }
            modules[module] = target
        end
        target.count = target.count + SafeNumber(bucket.count, 0)
        target.totalMs = target.totalMs + SafeNumber(bucket.totalMs, 0)
        target.over5 = target.over5 + SafeNumber(bucket.over5, 0)
        target.over10 = target.over10 + SafeNumber(bucket.over10, 0)
        if SafeNumber(bucket.maxMs, 0) > target.maxMs then target.maxMs = SafeNumber(bucket.maxMs, 0) end
    end
    return modules
end

local function MemoryRate()
    local history = RingToOrderedList(P.data.memory.history, MEMORY_SAMPLE_LIMIT)
    if table.getn(history) < 2 then return 0 end
    local first = history[1]
    local last = history[table.getn(history)]
    local seconds = SafeNumber(last.at, 0) - SafeNumber(first.at, 0)
    if seconds <= 0 then return 0 end
    return (SafeNumber(last.addon, 0) - SafeNumber(first.addon, 0)) / seconds
end


local function CaptureDuration(data)
    data = data or P.data
    local finish = data.endedAt or NowSeconds()
    return math.max(0.001, finish - SafeNumber(data.startedAt, finish))
end

local function InternalTotalMs()
    local total = 0
    local _, bucket
    for _, bucket in pairs(P.data.timers or {}) do total = total + SafeNumber(bucket.totalMs, 0) end
    return total
end

local function TimelineBar(valueMs, maxValueMs)
    valueMs = math.max(0, SafeNumber(valueMs, 0))
    maxValueMs = math.max(0.001, SafeNumber(maxValueMs, valueMs))
    local blocks = math.floor((valueMs / maxValueMs) * 20 + 0.5)
    blocks = math.max(0, math.min(20, blocks))
    return string.rep("#", blocks) .. string.rep(".", 20 - blocks)
end

local function TimelineAttribution(sample)
    if not sample then return "normal" end
    if SafeNumber(sample.likelyHitches, 0) > 0 then
        return "WowNote likely caused hitch: " .. tostring(sample.maxWowNoteFrameTopName or sample.topSingleName or "none")
    end
    if SafeNumber(sample.contributedHitches, 0) > 0 then
        return "WowNote contributed to hitch: " .. tostring(sample.maxWowNoteFrameTopName or sample.topSingleName or "none")
    end
    if SafeNumber(sample.hitches, 0) > 0 then
        return "hitch not attributed to measured WowNote code"
    end
    if SafeNumber(sample.wowNoteMaxFrameMs, 0) >= 5 then
        return "WowNote spike: " .. tostring(sample.maxWowNoteFrameTopName or sample.topSingleName or "none")
    end
    return "normal"
end

local function GetTimelineMetricOptions()
    local options = {
        { key = "total", label = "Total WowNote", kind = "total" },
    }
    local modules = BuildSortedBuckets(BuildModuleBuckets(), "totalMs")
    local i
    for i = 1, table.getn(modules) do
        table.insert(options, {
            key = "module:" .. modules[i].name,
            label = "Module: " .. modules[i].name,
            kind = "module",
            name = modules[i].name,
        })
    end
    local timers = BuildSortedBuckets(P.data.timers, "totalMs")
    for i = 1, table.getn(timers) do
        table.insert(options, {
            key = "handler:" .. timers[i].name,
            label = "Handler: " .. timers[i].name,
            kind = "handler",
            name = timers[i].name,
        })
    end
    return options
end

local function ResolveTimelineMetric()
    local options = GetTimelineMetricOptions()
    local i
    for i = 1, table.getn(options) do
        if options[i].key == selectedTimelineMetric then return options[i], i, options end
    end
    selectedTimelineMetric = "total"
    return options[1], 1, options
end

local function SelectTimelineMetric(delta)
    local _, index, options = ResolveTimelineMetric()
    if table.getn(options) <= 0 then return end
    index = index + (tonumber(delta) or 0)
    if index < 1 then index = table.getn(options) end
    if index > table.getn(options) then index = 1 end
    selectedTimelineMetric = options[index].key
end

local function TimelineMetricValue(sample, metric)
    if metric.kind == "module" then
        return SafeNumber(sample.moduleTotals and sample.moduleTotals[metric.name], 0),
            SafeNumber(sample.moduleCalls and sample.moduleCalls[metric.name], 0)
    elseif metric.kind == "handler" then
        return SafeNumber(sample.handlerTotals and sample.handlerTotals[metric.name], 0),
            SafeNumber(sample.handlerCalls and sample.handlerCalls[metric.name], 0)
    end
    return SafeNumber(sample.wowNoteTotalMs, 0), SafeNumber(sample.wowNoteCalls, 0)
end

function P:BuildTimelineReport(limit)
    local samples = RingToOrderedList(self.data.timeline, TIMELINE_SAMPLE_LIMIT)
    local count = table.getn(samples)
    limit = math.min(tonumber(limit) or TIMELINE_REPORT_LIMIT, count)
    local first = math.max(1, count - limit + 1)
    local metric = ResolveTimelineMetric()
    local maxValue = 0
    local i
    for i = first, count do
        local value = TimelineMetricValue(samples[i], metric)
        if value > maxValue then maxValue = value end
    end
    local lines = {
        "WowNote-only Profiler Timeline",
        "Selected value: " .. tostring(metric.label),
        "Each row summarizes one second. The bar is scaled to the highest selected value in the visible range (max " .. FormatNumber(maxValue, 3) .. " ms).",
        "Frame duration is shown only to correlate a visible hitch with WowNote's own measured handlers.",
        "Use the < and > buttons above the report to switch between total, module and individual handler values.",
        "",
    }
    if count == 0 then
        table.insert(lines, "No timeline samples recorded. Enable the profiler and reproduce the issue.")
        return table.concat(lines, "\n")
    end
    for i = first, count do
        local sample = samples[i]
        local valueMs, calls = TimelineMetricValue(sample, metric)
        table.insert(lines, string.format(
            "+%6.1fs | selected %8.3f ms | calls %4d | WN total %8.3f ms | top %-32s %7.3f ms | frame max %7.2f ms | %s | %s",
            sample.at or 0,
            valueMs,
            calls,
            sample.wowNoteTotalMs or 0,
            tostring(sample.topName or "none"),
            sample.topTotalMs or 0,
            sample.maxFrameMs or 0,
            TimelineBar(valueMs, maxValue),
            TimelineAttribution(sample)))
    end
    return table.concat(lines, "\n")
end

function P:BuildSummary()
    local data = self.data
    local uptime = CaptureDuration(data)
    local internalMs = InternalTotalMs()
    local internalMsPerSecond = internalMs / uptime
    local profilerAvg = data.profilerSampleCount > 0 and data.profilerSampleTotalMs / data.profilerSampleCount or 0
    local activeOnUpdates = GetActiveScriptNames("OnUpdate")
    local modules = BuildSortedBuckets(BuildModuleBuckets(), "totalMs")
    local topModule = modules[1]

    local lines = {}
    table.insert(lines, "Status: " .. (self.enabled and "ON" or "OFF")
        .. " | handler timing: " .. (self.detailed and "ON" or "OFF")
        .. " | capture: " .. FormatDuration(uptime))
    table.insert(lines, "Scope: WowNote handlers, WowNote memory and WowNote communication only; no foreign-addon values are displayed.")
    table.insert(lines, "Measured WowNote time: " .. FormatNumber(internalMs, 2) .. " ms total"
        .. " | " .. FormatNumber(internalMsPerSecond, 3) .. " ms/s"
        .. " | approx. " .. FormatNumber(internalMsPerSecond / 10, 3) .. "% of one CPU core")
    if topModule then
        table.insert(lines, "Top WowNote module: " .. topModule.name
            .. " | total " .. FormatNumber(topModule.bucket.totalMs, 3) .. " ms"
            .. " | max call " .. FormatNumber(topModule.bucket.maxMs, 3) .. " ms")
    else
        table.insert(lines, "Top WowNote module: no handler samples yet")
    end
    table.insert(lines, "Last WowNote frame work: " .. FormatNumber(data.frames.lastMeasuredMs, 3) .. " ms"
        .. " | top " .. tostring(data.frames.lastTopName or "none")
        .. " " .. FormatNumber(data.frames.lastTopMs, 3) .. " ms")
    table.insert(lines, "WowNote-attributed hitches: likely " .. data.frames.likelyWowNoteHitches
        .. " | contributed " .. data.frames.contributedWowNoteHitches
        .. " | not attributed " .. data.frames.notAttributedHitches)
    table.insert(lines, "Frame context: max " .. FormatNumber(data.frames.maxMs, 2) .. " ms"
        .. " | >=50/100/250/500 ms " .. data.frames.hitches50 .. "/" .. data.frames.hitches100
        .. "/" .. data.frames.hitches250 .. "/" .. data.frames.hitches500)
    table.insert(lines, "WowNote memory: " .. FormatNumber(data.memory.addonCurrent / 1024, 2) .. " MB"
        .. " | delta " .. FormatNumber((data.memory.addonCurrent - SafeNumber(data.memory.addonInitial, data.memory.addonCurrent)) / 1024, 2) .. " MB"
        .. " | peak " .. FormatNumber(data.memory.addonPeak / 1024, 2) .. " MB"
        .. " | trend " .. FormatNumber(MemoryRate(), 2) .. " KB/s")
    table.insert(lines, "Active WowNote OnUpdate handlers: " .. tostring(table.getn(activeOnUpdates))
        .. " | profiler overhead avg/max " .. FormatNumber(profilerAvg, 4)
        .. "/" .. FormatNumber(data.profilerSampleMaxMs, 3) .. " ms/frame")
    return table.concat(lines, "\n")
end

function P:BuildReport()
    local data = self.data
    local uptime = CaptureDuration(data)
    local lines = {
        "WowNote-only Internal Profiler Report",
        "Addon version: " .. tostring(GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version") or "unknown"),
        self:BuildSummary(),
        "",
        "Top WowNote modules by total measured time:",
    }

    local i
    local modules = BuildSortedBuckets(BuildModuleBuckets(), "totalMs")
    if table.getn(modules) == 0 then table.insert(lines, "  No module samples recorded.") end
    for i = 1, table.getn(modules) do
        local item = modules[i]
        local bucket = item.bucket
        local avg = bucket.count > 0 and bucket.totalMs / bucket.count or 0
        table.insert(lines, string.format("%2d. %s | calls %d | total %.3f ms | avg %.4f ms | max %.3f ms | >=5 ms %d | >=10 ms %d",
            i, item.name, bucket.count, bucket.totalMs, avg, bucket.maxMs, bucket.over5 or 0, bucket.over10 or 0))
    end

    table.insert(lines, "")
    table.insert(lines, "Top WowNote handlers by total measured time:")
    local timers = BuildSortedBuckets(data.timers, "totalMs")
    local timerCount = math.min(table.getn(timers), REPORT_TIMER_LIMIT)
    if timerCount == 0 then table.insert(lines, "  No detailed handler samples recorded.") end
    for i = 1, timerCount do
        local item = timers[i]
        local bucket = item.bucket
        local avg = bucket.count > 0 and bucket.totalMs / bucket.count or 0
        table.insert(lines, string.format("%2d. %s | calls %d | total %.3f ms | avg %.4f ms | max %.3f ms | >=5 ms %d | >=10 ms %d",
            i, item.name, bucket.count, bucket.totalMs, avg, bucket.maxMs, bucket.over5 or 0, bucket.over10 or 0))
    end

    table.insert(lines, "")
    table.insert(lines, "Top WowNote handlers by maximum single call:")
    local timersByMax = BuildSortedBuckets(data.timers, "maxMs")
    local maxTimerCount = math.min(table.getn(timersByMax), 15)
    if maxTimerCount == 0 then table.insert(lines, "  No detailed handler samples recorded.") end
    for i = 1, maxTimerCount do
        local item = timersByMax[i]
        local bucket = item.bucket
        local avg = bucket.count > 0 and bucket.totalMs / bucket.count or 0
        table.insert(lines, string.format("%2d. %s | max %.3f ms | avg %.4f ms | calls %d | total %.3f ms",
            i, item.name, bucket.maxMs, avg, bucket.count, bucket.totalMs))
    end

    table.insert(lines, "")
    table.insert(lines, "WowNote event routes:")
    local events = BuildSortedBuckets(data.events, "count")
    local eventCount = math.min(table.getn(events), REPORT_EVENT_LIMIT)
    if eventCount == 0 then table.insert(lines, "  No event samples recorded.") end
    for i = 1, eventCount do
        local item = events[i]
        local bucket = item.bucket
        table.insert(lines, string.format("%2d. %s | count %d | total %.3f ms | max %.3f ms",
            i, item.name, bucket.count, bucket.totalMs, bucket.maxMs))
    end

    table.insert(lines, "")
    table.insert(lines, "Active instrumented WowNote OnUpdate handlers:")
    local activeOnUpdates = GetActiveScriptNames("OnUpdate")
    if table.getn(activeOnUpdates) == 0 then table.insert(lines, "  None.") end
    for i = 1, table.getn(activeOnUpdates) do table.insert(lines, "  " .. activeOnUpdates[i]) end

    table.insert(lines, "")
    table.insert(lines, "WowNote communication counters:")
    local comm = BuildSortedBuckets(data.comm, "bytes")
    if table.getn(comm) == 0 then table.insert(lines, "  No instrumented WowNote communication recorded.") end
    for i = 1, table.getn(comm) do
        local item = comm[i]
        table.insert(lines, string.format("  %s | packets %d | bytes %d | failed %d",
            item.name, item.bucket.packets, item.bucket.bytes, item.bucket.failed))
    end

    table.insert(lines, "")
    table.insert(lines, "WowNote counters and gauges:")
    local counterNames = {}
    local name
    for name in pairs(data.counters) do table.insert(counterNames, name) end
    table.sort(counterNames)
    for i = 1, table.getn(counterNames) do
        name = counterNames[i]
        table.insert(lines, "  " .. name .. " = " .. tostring(data.counters[name]))
    end
    local gaugeNames = {}
    for name in pairs(data.gauges) do table.insert(gaugeNames, name) end
    table.sort(gaugeNames)
    for i = 1, table.getn(gaugeNames) do
        name = gaugeNames[i]
        table.insert(lines, "  " .. name .. " = " .. tostring(data.gauges[name]))
    end
    if table.getn(counterNames) == 0 and table.getn(gaugeNames) == 0 then table.insert(lines, "  No custom WowNote counters recorded.") end

    table.insert(lines, "")
    table.insert(lines, "Recent one-second WowNote timeline:")
    local timeline = RingToOrderedList(data.timeline, TIMELINE_SAMPLE_LIMIT)
    local timelineStart = math.max(1, table.getn(timeline) - 29)
    if table.getn(timeline) == 0 then table.insert(lines, "  No timeline samples recorded.") end
    for i = timelineStart, table.getn(timeline) do
        local sample = timeline[i]
        table.insert(lines, string.format("  +%.1fs | WN total %.3f ms | max/frame %.3f ms | calls %d | top %s %.3f ms | frame max %.2f ms | %s",
            sample.at or 0, sample.wowNoteTotalMs or 0, sample.wowNoteMaxFrameMs or 0, sample.wowNoteCalls or 0,
            sample.topName or "none", sample.topTotalMs or 0, sample.maxFrameMs or 0, TimelineAttribution(sample)))
    end

    table.insert(lines, "")
    table.insert(lines, "Recent frame hitches with WowNote attribution (newest last):")
    if table.getn(data.hitches) == 0 then table.insert(lines, "  No >=50 ms frame hitches recorded.") end
    for i = 1, table.getn(data.hitches) do
        local hitch = data.hitches[i]
        table.insert(lines, string.format("  +%.1fs | frame %.2f ms | measured WowNote %.3f ms | top %s %.3f ms | %s | combat %s | WowNote memory %.2f MB",
            hitch.at, hitch.frameMs, hitch.measuredMs, hitch.topName, hitch.topMs,
            AttributionText(hitch.frameMs, hitch.measuredMs, hitch.topMs, hitch.topName),
            hitch.combat and "yes" or "no", hitch.addonMemory / 1024))
    end

    table.insert(lines, "")
    table.insert(lines, "Manual markers:")
    if table.getn(data.marks) == 0 then table.insert(lines, "  No manual markers.") end
    for i = 1, table.getn(data.marks) do
        local mark = data.marks[i]
        table.insert(lines, string.format("  +%.1fs | %s | frame %.2f ms | measured WowNote %.3f ms | memory %.2f MB | top %s %.3f ms",
            mark.at, mark.label, mark.frameMs, mark.wowNoteMs or 0, mark.addonMemory / 1024, mark.topName or "none", mark.topMs or 0))
    end

    table.insert(lines, "")
    table.insert(lines, "Interpretation: only measured WowNote code is attributed. A high frame duration with little measured WowNote time is explicitly not blamed on WowNote. No per-addon CPU or memory values from other addons are read, stored or shown.")
    table.insert(lines, "Session duration: " .. FormatDuration(uptime))
    return table.concat(lines, "\n")
end

local function MakeButton(parent, text, width, x, y, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(24)
    button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function CreateProfilerFrame()
    if profilerFrame then return end
    profilerFrame = CreateFrame("Frame", "WowNoteProfilerFrame", UIParent)
    profilerFrame:SetWidth(790)
    profilerFrame:SetHeight(620)
    profilerFrame:SetPoint("CENTER")
    profilerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    if profilerFrame.SetToplevel then profilerFrame:SetToplevel(true) end
    profilerFrame:SetFrameLevel(120)
    profilerFrame:SetMovable(true)
    profilerFrame:EnableMouse(true)
    profilerFrame:RegisterForDrag("LeftButton")
    profilerFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    profilerFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    profilerFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    profilerFrame:Hide()

    local title = profilerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", profilerFrame, "TOPLEFT", 18, -16)
    title:SetText("WowNote-only Internal Profiler")

    local close = CreateFrame("Button", nil, profilerFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", profilerFrame, "TOPRIGHT", -4, -4)

    statusText = profilerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", profilerFrame, "TOPLEFT", 22, -45)
    statusText:SetWidth(740)
    statusText:SetJustifyH("LEFT")

    summaryText = profilerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryText:SetPoint("TOPLEFT", profilerFrame, "TOPLEFT", 22, -66)
    summaryText:SetWidth(746)
    summaryText:SetHeight(174)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetJustifyV("TOP")

    timelineMetricText = profilerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timelineMetricText:SetPoint("TOPLEFT", profilerFrame, "TOPLEFT", 22, -230)
    timelineMetricText:SetWidth(570)
    timelineMetricText:SetJustifyH("LEFT")

    timelinePreviousButton = CreateFrame("Button", nil, profilerFrame, "UIPanelButtonTemplate")
    timelinePreviousButton:SetWidth(54)
    timelinePreviousButton:SetHeight(22)
    timelinePreviousButton:SetPoint("TOPRIGHT", profilerFrame, "TOPRIGHT", -82, -222)
    timelinePreviousButton:SetText("<")
    timelinePreviousButton:SetScript("OnClick", function()
        SelectTimelineMetric(-1)
        if reportEdit then reportEdit:ClearFocus() end
        P:RefreshUI(true, true)
    end)

    timelineNextButton = CreateFrame("Button", nil, profilerFrame, "UIPanelButtonTemplate")
    timelineNextButton:SetWidth(54)
    timelineNextButton:SetHeight(22)
    timelineNextButton:SetPoint("LEFT", timelinePreviousButton, "RIGHT", 4, 0)
    timelineNextButton:SetText(">")
    timelineNextButton:SetScript("OnClick", function()
        SelectTimelineMetric(1)
        if reportEdit then reportEdit:ClearFocus() end
        P:RefreshUI(true, true)
    end)

    reportScroll = CreateFrame("ScrollFrame", "WowNoteProfilerScrollFrame", profilerFrame, "UIPanelScrollFrameTemplate")
    reportScroll:SetPoint("TOPLEFT", profilerFrame, "TOPLEFT", 22, -252)
    reportScroll:SetPoint("BOTTOMRIGHT", profilerFrame, "BOTTOMRIGHT", -42, 58)

    reportEdit = CreateFrame("EditBox", "WowNoteProfilerReportEdit", reportScroll)
    reportEdit:SetMultiLine(true)
    reportEdit:SetAutoFocus(false)
    reportEdit:SetFontObject(ChatFontNormal)
    reportEdit:SetWidth(714)
    reportEdit:SetHeight(3000)
    if reportEdit.SetTextInsets then reportEdit:SetTextInsets(4, 4, 4, 4) end
    reportEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    reportScroll:SetScrollChild(reportEdit)

    toggleButton = MakeButton(profilerFrame, "Enable", 88, 22, 22, function()
        P:SetEnabled(not P.enabled)
    end)
    detailButton = MakeButton(profilerFrame, "Timing ON", 92, 116, 22, function()
        P:SetDetailed(not P.detailed)
    end)
    MakeButton(profilerFrame, "Reset", 72, 214, 22, function()
        P:Reset(false)
        P:RefreshUI(true)
    end)
    MakeButton(profilerFrame, "Refresh", 78, 292, 22, function()
        if P:IsEnabled() then P:SampleWowNote(false) end
        P:RefreshUI(true)
    end)
    MakeButton(profilerFrame, "Full report", 94, 376, 22, function()
        currentView = "report"
        if reportEdit then reportEdit:ClearFocus() end
        P:RefreshUI(true, true)
    end)
    MakeButton(profilerFrame, "Timeline", 82, 476, 22, function()
        currentView = "timeline"
        if reportEdit then reportEdit:ClearFocus() end
        P:RefreshUI(true, true)
    end)
    MakeButton(profilerFrame, "Select", 94, 564, 22, function()
        if reportEdit then reportEdit:ClearFocus() end
        P:RefreshUI(true, true)
        reportEdit:SetFocus()
        reportEdit:HighlightText()
    end)
    MakeButton(profilerFrame, "Mark", 78, 664, 22, function() P:Mark("UI marker") end)

    profilerFrame:SetScript("OnShow", function()
        uiElapsed = 0
        if UpdateProfilerFrameScript then UpdateProfilerFrameScript() end
        P:RefreshUI(true)
    end)
    profilerFrame:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)
end

local function ProfilerFrameOnUpdate(_, elapsed)
    uiElapsed = uiElapsed + SafeNumber(elapsed, 0)
    if uiElapsed >= 1.0 then
        uiElapsed = 0
        P:RefreshUI(false)
    end
end

UpdateProfilerFrameScript = function()
    if not profilerFrame then return end
    if profilerFrame:IsShown() and P:IsEnabled() then
        profilerFrame:SetScript("OnUpdate", ProfilerFrameOnUpdate)
    else
        profilerFrame:SetScript("OnUpdate", nil)
    end
end

function P:RefreshUI(refreshReport, forceReport)
    if not profilerFrame or not profilerFrame:IsShown() then return end
    if statusText then
        statusText:SetText("Profiler " .. (self.enabled and "enabled" or "disabled: zero sampler and timing-wrapper load")
            .. " | WowNote-only scope | view " .. currentView)
    end
    if toggleButton then toggleButton:SetText(self.enabled and "Disable" or "Enable") end
    if detailButton then detailButton:SetText(self.detailed and "Timing ON" or "Timing OFF") end
    if summaryText then summaryText:SetText(self:BuildSummary()) end

    local isTimeline = currentView == "timeline"
    local metric = ResolveTimelineMetric()
    if timelineMetricText then
        timelineMetricText:SetText(isTimeline and ("Timeline value: " .. tostring(metric.label)) or "")
        if isTimeline then timelineMetricText:Show() else timelineMetricText:Hide() end
    end
    if timelinePreviousButton then
        if isTimeline then timelinePreviousButton:Show() else timelinePreviousButton:Hide() end
    end
    if timelineNextButton then
        if isTimeline then timelineNextButton:Show() else timelineNextButton:Hide() end
    end

    if refreshReport ~= false and reportEdit and (forceReport or not reportEdit:HasFocus()) then
        local text = isTimeline and self:BuildTimelineReport(TIMELINE_REPORT_LIMIT) or self:BuildReport()
        local lineCount = 1
        string.gsub(text, "\n", function() lineCount = lineCount + 1 end)
        local minimumHeight = reportScroll and reportScroll:GetHeight() or 300
        reportEdit:SetHeight(math.max(minimumHeight, lineCount * 14 + 24))
        reportEdit:SetText(text)
        reportEdit:SetCursorPosition(0)
        reportEdit:ClearFocus()
        if reportScroll and reportScroll.SetVerticalScroll then reportScroll:SetVerticalScroll(0) end
    end
end

function P:Open()
    CreateProfilerFrame()
    profilerFrame:Show()
    if profilerFrame.Raise then profilerFrame:Raise() end
    self:RefreshUI(true)
end

function P:PrintCompactReport()
    local data = self.data
    local uptime = CaptureDuration(data)
    local internalMs = InternalTotalMs()
    Print("capture " .. FormatDuration(uptime)
        .. ", measured WowNote " .. FormatNumber(internalMs, 2) .. " ms total / "
        .. FormatNumber(internalMs / uptime, 3) .. " ms/s.")
    Print("WowNote-attributed hitches likely/contributed/not-attributed "
        .. data.frames.likelyWowNoteHitches .. "/" .. data.frames.contributedWowNoteHitches
        .. "/" .. data.frames.notAttributedHitches .. ".")
    Print("WowNote memory " .. FormatNumber(data.memory.addonCurrent / 1024, 2) .. " MB, delta "
        .. FormatNumber((data.memory.addonCurrent - SafeNumber(data.memory.addonInitial, data.memory.addonCurrent)) / 1024, 2)
        .. " MB, trend " .. FormatNumber(MemoryRate(), 2) .. " KB/s.")

    local modules = BuildSortedBuckets(BuildModuleBuckets(), "totalMs")
    local max = math.min(5, table.getn(modules))
    local i
    for i = 1, max do
        local item = modules[i]
        Print("module " .. i .. ": " .. item.name .. " total " .. FormatNumber(item.bucket.totalMs, 3)
            .. " ms, max " .. FormatNumber(item.bucket.maxMs, 3) .. " ms, calls " .. item.bucket.count .. ".")
    end
end

function P:HandleSlash(raw)
    raw = tostring(raw or "")
    raw = string.gsub(raw, "^%s+", "")
    raw = string.gsub(raw, "%s+$", "")
    local lower = string.lower(raw)
    if lower == "" or lower == "open" then
        self:Open()
    elseif lower == "on" or lower == "enable" then
        self:SetEnabled(true)
    elseif lower == "off" or lower == "disable" then
        self:SetEnabled(false)
    elseif lower == "detailed on" or lower == "detail on" or lower == "timing on" then
        self:SetDetailed(true)
    elseif lower == "detailed off" or lower == "detail off" or lower == "timing off" then
        self:SetDetailed(false)
    elseif lower == "reset" then
        self:Reset(false)
    elseif lower == "report" or lower == "summary" then
        self:PrintCompactReport()
    elseif lower == "timeline" or lower == "history" or lower == "verlauf" then
        currentView = "timeline"
        self:Open()
        if reportEdit then reportEdit:ClearFocus() end
        self:RefreshUI(true, true)
    elseif string.sub(lower, 1, 5) == "mark " then
        self:Mark(string.sub(raw, 6))
    elseif lower == "mark" then
        self:Mark("manual")
    else
        Print("Commands: /wn profile, on, off, reset, report, timeline, mark <text>, detailed on/off")
    end
end

function WowNote_OpenProfiler()
    P:Open()
end

function WowNote_ProfilerHandleSlash(raw)
    P:HandleSlash(raw)
end

SLASH_WOWNOTEPROFILER1 = "/wnprofile"
SlashCmdList["WOWNOTEPROFILER"] = function(msg) P:HandleSlash(msg) end

EnsureSamplerFrame = function()
    if samplerFrame then return samplerFrame end
    -- Created only when profiling is enabled. Since all addon files are loaded by
    -- then, this frame normally runs after WowNote's worker frames and improves
    -- same-frame hitch attribution while leaving the disabled state frame-free.
    samplerFrame = CreateFrame("Frame")
    P.samplerFrame = samplerFrame
    return samplerFrame
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        local cfg = EnsureConfig()
        if cfg then
            P.enabled = cfg.enabled == true
            P.detailed = cfg.detailed ~= false
        end
        P.addonIndex = FindAddonIndex()
        P:SetEnabled(P.enabled, true)
    elseif event == "PLAYER_LOGIN" then
        local cfg = EnsureConfig()
        if cfg then
            P.enabled = cfg.enabled == true
            P.detailed = cfg.detailed ~= false
        end
        if P:IsEnabled() then P:Reset(true) end
        P:SetEnabled(P.enabled, true)
    end
end)

P:SetEnabled(P.enabled, true)
