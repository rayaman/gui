-- verify.lua — invariant checker for the flex demo (plan §8 Phase 2 acceptance).
-- Loads inside the LÖVE demo (examples/flex-demo); also usable from a bare
-- lua/love boot as long as core/flexbox.lua is on package.path.

local verify = {}

local EPS = 1e-9

--- Compare a resolved rect (from getAbsolutes) against an expected rect.
-- Prints a FAIL line to the console on mismatch; returns ok, message.
function verify.rect(name, x, y, w, h, ex, ey, ew, eh)
    local ok = math.abs(x - ex) <= EPS and math.abs(y - ey) <= EPS
           and math.abs(w - ew) <= EPS and math.abs(h - eh) <= EPS
    if not ok then
        local msg = string.format(
            "FAIL [%s] expected(%.6f, %.6f, %.6f, %.6f) got(%.6f, %.6f, %.6f, %.6f)",
            name, ex, ey, ew, eh, x, y, w, h)
        print(msg)
        return false, msg
    end
    return true, "PASS [" .. name .. "]"
end

--- The write-back invariant: every managed element's getAbsolutes() must equal
--- its last __flexComputed (tolerance 1e-9). Delegates to the engine verifier.
function verify.invariant(flexbox, tree)
    local fails = flexbox.debugVerifySubtree(tree, EPS)
    return fails
end

return verify
