-- verify.lua — helpers for the svg-demo autotest. Kept tiny: the svg checks
-- are structural/pixel based, not layout-invariant based like flex-demo.
local verify = {}

--- Approximate float compare with a tolerance.
function verify.approx(name, got, want, tol)
    tol = tol or 1e-6
    local ok = type(got) == "number" and math.abs(got - want) <= tol
    if not ok then
        print(string.format("FAIL [%s] expected %.6f got %s", name, want, tostring(got)))
    end
    return ok
end

--- Whether a packed color triplet matches within a per-channel tolerance.
function verify.color(name, c, r, g, b, tol)
    tol = tol or 1e-3
    if not c then
        print("FAIL [" .. name .. "] color is nil")
        return false
    end
    local ok = math.abs(c[1] - r) <= tol and math.abs(c[2] - g) <= tol and math.abs(c[3] - b) <= tol
    if not ok then
        print(string.format("FAIL [%s] expected (%.3f,%.3f,%.3f) got (%.3f,%.3f,%.3f)",
            name, r, g, b, c[1], c[2], c[3]))
    end
    return ok
end

return verify
