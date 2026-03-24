--[[
    scheduler_probe.lua
    -------------------
    A drop-in replacement for multi:getLoad() based on scheduler tick-slip
    rather than step-count benchmarking.

    THEORY
    ------
    Schedule a repeating timer at a fixed interval T. Each time it fires,
    measure how much later than T it actually arrived. On an idle scheduler
    the slip is near zero. Under load the main loop is busy with other tasks
    between iterations, so ticks are delayed.

    We express load as:

        lag        = actual_interval - target_interval   (seconds)
        lag_ratio  = lag / target_interval               (0 = perfect, 1 = 1 full interval late)
        load%      = clamp(lag_ratio * 100, 0, 100)

    To smooth out single-frame spikes we keep an exponential moving average
    (EMA) of lag_ratio with a configurable smoothing factor.

    WHY THIS IS BETTER THAN THE STEP-COUNT APPROACH
    ------------------------------------------------
    - No calibration baseline that drifts with object count or warm-up
    - No magic exponents or divisors
    - Does not block or create temporary objects on each call
    - Measures actual scheduler responsiveness, not raw throughput
    - Works correctly regardless of which processor calls it
    - A single lightweight TLoop is the only permanent overhead

    USAGE
    -----
        local probe = require("scheduler_probe")
        probe:install(multi)        -- once, at startup

        -- anywhere, non-blocking:
        local load, lagMs = multi:getLoad()
        -- load  : integer 0-100
        -- lagMs : smoothed lag in milliseconds (useful for display)

    OPTIONAL PARAMETERS
    -------------------
        probe:install(multi, {
            interval = 0.05,   -- probe fires every N seconds (default 0.05 = 50ms)
            alpha    = 0.15,   -- EMA smoothing factor 0-1 (default 0.15)
                               -- lower = smoother but slower to react
                               -- higher = more reactive but noisier
            maxLag   = 0.5,    -- lag value (seconds) that maps to 100% load (default 0.5)
                               -- tune this to match your target frame budget
        })
]]

local probe = {}

-- EMA state — written by the TLoop callback, read by getLoad()
-- Both are plain numbers so Lua's assignment is atomic within one thread.
local _emaRatio = 0      -- smoothed lag / maxLag, clamped 0-1
local _lagMs    = 0      -- smoothed lag in milliseconds for display
local _installed = false

function probe:install(multi_obj, opts)
    if _installed then return end
    _installed = true

    opts = opts or {}
    local INTERVAL = opts.interval or 0.05   -- seconds between probes
    local ALPHA    = opts.alpha    or 0.15   -- EMA weight for new sample
    local MAX_LAG  = opts.maxLag   or 0.5    -- seconds of lag = 100% load

    local clock = os.clock

    -- Track when the tick *should* have fired so we can compute slip
    -- relative to the scheduled time, not relative to the previous firing.
    -- This avoids error accumulation over long runs.
    local expectedTime = clock() + INTERVAL

    local tloop = multi_obj:newTLoop(nil, INTERVAL)
    tloop:setName("SchedulerProbe")
    tloop:setPriority("core")  -- run as early as possible each frame

    tloop.OnLoop(function(self, life, dt)
        local now     = clock()
        local lag     = math.max(0, now - expectedTime)   -- never negative
        local ratio   = math.min(lag / MAX_LAG, 1)        -- clamp to [0,1]

        -- Exponential moving average: new = alpha*sample + (1-alpha)*old
        _emaRatio = ALPHA * ratio    + (1 - ALPHA) * _emaRatio
        _lagMs    = ALPHA * lag*1000 + (1 - ALPHA) * _lagMs

        -- Advance expected time by one interval from where it *should* have been,
        -- not from now — prevents the probe from drifting under sustained load.
        expectedTime = expectedTime + INTERVAL
        -- If we fall more than one interval behind (e.g. after a long GC pause),
        -- re-anchor so we don't fire in a catch-up burst.
        if now > expectedTime + INTERVAL then
            expectedTime = now + INTERVAL
        end
    end)

    -- Replace multi:getLoad() with a non-blocking version that just reads the EMA
    function multi_obj:getLoad()
        local pct = math.ceil(_emaRatio * 100)
        return pct, _lagMs
    end

    -- Also expose raw probe state for diagnostics
    function multi_obj:getSchedulerLag()
        return _lagMs, _emaRatio
    end

    return tloop
end

return probe
