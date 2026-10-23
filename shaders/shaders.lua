local shaders = {}
function NewShader(name, shader, opt_args)
    local uniforms = {}
    local opt_args = opt_args or {}
    for typ, uname in shader:gmatch("extern%s+(%w+)%s+(%w+)%s*;") do
        if uname ~= "time" and uname ~= "size"  then
            table.insert(uniforms, "Argument \"" .. uname .. "\" is expected to be: \"" .. typ .. "\"")
            opt_args[uname] = true
        end
    end
    if #opt_args > 0 or #uniforms > 0 then
        opt_args.source = love.graphics.newShader(shader)
        shaders[name] = opt_args
        if opt_args.usage == nil then
            opt_args.usage = function() return table.concat(uniforms,"\n").."\n" end
        end
    else
        shaders[name] = love.graphics.newShader(shader)
    end
end

function GetShaderUniforms(name)
    local source = shaders[name]  -- we need the source not the compiled shader
    local uniforms = {}
    for type, uname in source:gmatch("extern%s+(%w+)%s+(%w+)%s*;") do
        uniforms[uname] = type
    end
    return uniforms
end

-- ─────────────────────────────────────────────
-- GLOW  (original – kept for reference)
-- Uniforms: vec2 size, float time
-- ─────────────────────────────────────────────
NewShader("glow", [[
    extern float time;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 pixel = Texel(tex, tc);
        float pulse = 0.15 * sin(time * 3.0) + 0.85;
        return vec4(pixel.rgb * pulse, pixel.a) * color;
    }
]])

-- ─────────────────────────────────────────────
-- GRAYSCALE
-- Converts the sprite to grayscale (good for disabled/inactive state).
-- Uniforms: float grayScale  (0.0 = full color, 1.0 = full gray)
-- ─────────────────────────────────────────────
NewShader("grayscale", [[
    extern float amount;
    vec4 effect(vec4 col, Image tex, vec2 tc, vec2 sc) {
        vec4  pixel = Texel(tex, tc) * col;
        float gray  = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
        float a     = clamp(amount, 0.0, 1.0);
        vec3  mixed = pixel.rgb * (1.0 - a) + vec3(gray) * a;
        return vec4(mixed, pixel.a);
    }
]])


-- ─────────────────────────────────────────────
-- CHROMATIC ABERRATION
-- Uniforms: float amount  (try 0.003 – 0.012)
-- ─────────────────────────────────────────────
NewShader("chromatic_aberration", [[
    extern float amount;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 r = Texel(tex, tc + vec2(amount, 0.0));
        vec4 g = Texel(tex, tc);
        vec4 b = Texel(tex, tc + vec2(-amount, 0.0));
        vec4 pixel = vec4(r.r, g.g, b.b, g.a) * color;
        return pixel;
    }
]])

-- ─────────────────────────────────────────────
-- GAUSSIAN BLUR  (single-pass, 9-tap)
-- Run twice with {1,0} then {0,1} for full 2D blur.
-- Uniforms: vec2 direction  ({1,0} or {0,1}), vec2 size
-- ─────────────────────────────────────────────
NewShader("blur", [[
    extern vec2 direction;
    extern vec2 size;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec2 px     = direction / size;
        vec4 result = vec4(0.0);
        result += Texel(tex, tc - px * 4.0) * 0.0162;
        result += Texel(tex, tc - px * 3.0) * 0.0540;
        result += Texel(tex, tc - px * 2.0) * 0.1216;
        result += Texel(tex, tc - px * 1.0) * 0.1945;
        result += Texel(tex, tc           ) * 0.2270;
        result += Texel(tex, tc + px * 1.0) * 0.1945;
        result += Texel(tex, tc + px * 2.0) * 0.1216;
        result += Texel(tex, tc + px * 3.0) * 0.0540;
        result += Texel(tex, tc + px * 4.0) * 0.0162;
        return result * color;
    }
]])

-- ─────────────────────────────────────────────
-- SCANLINES
-- Uniforms: float strength (0.0-1.0), float count (e.g. 200)
-- ─────────────────────────────────────────────
NewShader("scanlines", [[
    extern float strength;
    extern float count;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4  pixel = Texel(tex, tc) * color;
        float line  = sin(tc.y * count * 3.14159) * 0.5 + 0.5;
        float dim   = 1.0 - strength * (1.0 - line);
        return vec4(pixel.rgb * dim, pixel.a);
    }
]])

-- ─────────────────────────────────────────────
-- PIXELATE
-- Uniforms: float pixels (grid cell size, e.g. 8.0), vec2 size
-- ─────────────────────────────────────────────
NewShader("pixelate", [[
    extern float pixels;
    extern vec2  size;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec2 grid = floor(tc * size / pixels) * pixels / size;
        return Texel(tex, grid) * color;
    }
]])

-- ─────────────────────────────────────────────
-- VIGNETTE
-- Uniforms: float intensity (0.0-1.0), float smoothness (0.0-1.0)
-- ─────────────────────────────────────────────
NewShader("vignette", [[
    extern float intensity;
    extern float smoothness;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4  pixel = Texel(tex, tc) * color;
        vec2  uv    = tc - 0.5;
        float dist  = length(uv);
        float vig   = smoothstep(0.8, 0.8 - smoothness, dist * intensity);
        return vec4(pixel.rgb * vig, pixel.a);
    }
]])

-- ─────────────────────────────────────────────
-- HUE SHIFT
-- Uniforms: float hue (radians, 0 = no change)
-- ─────────────────────────────────────────────
NewShader("hue_shift", [[
    extern float hue;
    vec3 rgb2hsv(vec3 c) {
        vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
        vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
        vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
        float d = q.x - min(q.w, q.y);
        float e = 1.0e-10;
        return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
    }
    vec3 hsv2rgb(vec3 c) {
        vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
        vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    }
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4  pixel = Texel(tex, tc) * color;
        vec3  hsv   = rgb2hsv(pixel.rgb);
        hsv.x       = fract(hsv.x + hue / 6.28318);
        return vec4(hsv2rgb(hsv), pixel.a);
    }
]])

--[[
    NEEDS TESTING :P
]]

-- ─────────────────────────────────────────────
-- DISSOLVE
-- Uniforms: float threshold (0.0=visible, 1.0=gone)
--           float edge_width (e.g. 0.05)
--           vec4  edge_color
-- ─────────────────────────────────────────────
NewShader("dissolve", [[
    extern float threshold;
    extern float edge_width;
    extern vec4  edge_color;
    float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }
    float noise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i),             hash(i + vec2(1,0)), u.x),
                   mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), u.x), u.y);
    }
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4  pixel = Texel(tex, tc) * color;
        float n     = noise(tc * 8.0);
        if (n < threshold)               discard;
        if (n < threshold + edge_width)  return edge_color;
        return pixel;
    }
]])

-- ─────────────────────────────────────────────
-- WAVE
-- Uniforms: float time, float amplitude (e.g. 0.01), float frequency (e.g. 10.0)
-- ─────────────────────────────────────────────
NewShader("wave", [[
    extern float time;
    extern float amplitude;
    extern float frequency;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec2 uv = tc;
        uv.x   += sin(uv.y * frequency + time * 3.0) * amplitude;
        uv.y   += sin(uv.x * frequency + time * 2.5) * amplitude * 0.6;
        return Texel(tex, uv) * color;
    }
]])


-- ─────────────────────────────────────────────
-- RAINBOW / IRIDESCENCE
-- Uniforms: float time, float speed (e.g. 1.0), float spread (e.g. 2.0)
-- ─────────────────────────────────────────────
NewShader("rainbow", [[
    extern float time;
    extern float speed;
    extern float spread;
    vec3 hsv2rgb(vec3 c) {
        vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
        vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    }
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4  pixel   = Texel(tex, tc) * color;
        float h       = fract(tc.x * spread + time * speed * 0.1);
        vec3  rainbow = hsv2rgb(vec3(h, 0.8, 1.0));
        return vec4(pixel.rgb * rainbow, pixel.a);
    }
]])


-- ─────────────────────────────────────────────
-- FLASH / HIT-FLASH
-- Uniforms: float flash (0.0=normal, 1.0=full flash)
--           vec4  flash_color (e.g. {1,1,1,1})
-- ─────────────────────────────────────────────
NewShader("flash", [[
    extern float flash;
    extern vec4  flash_color;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 pixel = Texel(tex, tc) * color;
        vec3 mixed = pixel.rgb * (1.0 - flash) + flash_color.rgb * flash;
        return vec4(mixed, pixel.a);
    }
]])


-- ─────────────────────────────────────────────
-- INVERT
-- Uniforms: float amount  (0.0 = normal, 1.0 = fully inverted)
-- ─────────────────────────────────────────────
NewShader("invert", [[
    extern float amount;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 pixel    = Texel(tex, tc) * color;
        vec3 inverted = 1.0 - pixel.rgb;
        vec3 mixed    = pixel.rgb * (1.0 - amount) + inverted * amount;
        return vec4(mixed, pixel.a);
    }
]])

-- Auto hooks new shaders to SHADERS namespace, also adds the NewShader function
return {init = function(gui) gui.SHADERS=shaders gui.NewShader = NewShader end}