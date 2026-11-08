-- verify.lua — checker helpers for the list-frame demo.
local verify = {}

--- Rect comparison with an explicit tolerance (layout tweens settle to
--- sub-pixel, not exact). Prints a FAIL line on mismatch.
function verify.rectApprox(name, x, y, w, h, ex, ey, ew, eh, tol)
    tol = tol or 0.75
    local ok = math.abs(x - ex) <= tol and math.abs(y - ey) <= tol
           and math.abs(w - ew) <= tol and math.abs(h - eh) <= tol
    if not ok then
        print(string.format(
            "FAIL [%s] expected(%.2f, %.2f, %.2f, %.2f) got(%.2f, %.2f, %.2f, %.2f)",
            name, ex, ey, ew, eh, x, y, w, h))
        return false
    end
    return true
end

function verify.near(name, got, want, tol)
    tol = tol or 0.75
    if math.abs((got or -1e9) - want) > tol then
        print(string.format("FAIL [%s] expected %.3f got %s", name, want, tostring(got)))
        return false
    end
    return true
end

return verify
