local blur_h = love.graphics.newShader([[
    extern vec2 size;
    extern float radius;

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec2 step = vec2(1.0 / size.x, 0.0);
        vec4 result = vec4(0.0);
        float total = 0.0;
        float sigma = radius * 0.5;
        float r = floor(radius);
        float i = -r;

        while (i <= r) {
            float weight = exp(-0.5 * (i * i) / (sigma * sigma));
            result += Texel(tex, tc + step * i) * weight;
            total  += weight;
            i = i + 1.0;
        }

        return (result / total) * color;
    }
]])

local blur_v = love.graphics.newShader([[
    extern vec2 size;
    extern float radius;

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec2 step = vec2(0.0, 1.0 / size.y);
        vec4 result = vec4(0.0);
        float total = 0.0;
        float sigma = radius * 0.5;
        float r = floor(radius);
        float i = -r;

        while (i <= r) {
            float weight = exp(-0.5 * (i * i) / (sigma * sigma));
            result += Texel(tex, tc + step * i) * weight;
            total  += weight;
            i = i + 1.0;
        }

        return (result / total) * color;
    }
]])

local c = {}

function c:setBlur(radius)
    radius = radius or 8
    c.__blur = {
        radius   = radius,
        canvas1  = nil,   -- populated on first draw
        canvas2  = nil,
        shader_h = blur_h,
        shader_v = blur_v,
    }
end

function c:clearBlur()
    c.__blur = nil
end

function c:setBlurRadius(radius)
    if c.__blur then
        c.__blur.radius = radius
    end
end

return {init = function(gui) gui.registerExtension(c) end}