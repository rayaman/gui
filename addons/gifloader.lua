-- GIF Loader for Love2D with LZW Decompression
-- Note: love.data.compress/decompress don't support LZW, so we implement it

local GifLoader = {}

-- Pure Lua LZW decompression for GIF
local function decompressLZW(data, minCodeSize)
    local clearCode = 2 ^ minCodeSize
    local endCode = clearCode + 1
    local nextCode = endCode + 1
    local codeSize = minCodeSize + 1
    
    local dict = {}
    for i = 0, clearCode - 1 do
        dict[i] = {string.byte(string.char(i))}
    end
    
    local output = {}
    local bits = 0
    local bitBuffer = 0
    local pos = 1
    local prevCode = nil
    
    local function readCode()
        while bits < codeSize do
            if pos > #data then return nil end
            bitBuffer = bitBuffer + bit.lshift(string.byte(data, pos), bits)
            bits = bits + 8
            pos = pos + 1
        end
        
        local code = bit.band(bitBuffer, bit.lshift(1, codeSize) - 1)
        bitBuffer = bit.rshift(bitBuffer, codeSize)
        bits = bits - codeSize
        return code
    end
    
    local first = true
    
    while true do
        local code = readCode()
        if not code or code == endCode then break end
        
        if code == clearCode then
            dict = {}
            for i = 0, clearCode - 1 do
                dict[i] = {string.byte(string.char(i))}
            end
            nextCode = endCode + 1
            codeSize = minCodeSize + 1
            prevCode = nil
            first = true
        else
            local entry
            if dict[code] then
                entry = dict[code]
            elseif code == nextCode and prevCode then
                -- Special case: code not in dict yet
                entry = {}
                for i = 1, #dict[prevCode] do
                    entry[i] = dict[prevCode][i]
                end
                entry[#entry + 1] = dict[prevCode][1]
            else
                -- Invalid code, stop
                break
            end
            
            -- Output the entry
            for i = 1, #entry do
                table.insert(output, entry[i])
            end
            
            -- Add new entry to dictionary
            if not first and prevCode and nextCode < 4096 then
                local newEntry = {}
                for i = 1, #dict[prevCode] do
                    newEntry[i] = dict[prevCode][i]
                end
                newEntry[#newEntry + 1] = entry[1]
                dict[nextCode] = newEntry
                nextCode = nextCode + 1
                
                -- Increase code size when needed
                if nextCode >= bit.lshift(1, codeSize) and codeSize < 12 then
                    codeSize = codeSize + 1
                end
            end
            
            prevCode = code
            first = false
        end
    end
    
    -- Convert output bytes to string
    local result = {}
    for i = 1, #output do
        result[i] = string.char(output[i])
    end
    return table.concat(result)
end

function GifLoader.load(filepath)
    local fileData = love.filesystem.read(filepath)
    if not fileData then
        error("Could not read GIF file: " .. filepath)
    end
    
    local gif = {
        frames = {},
        frameData = {},  -- Store ImageData for frame composition
        delays = {},
        currentFrame = 1,
        timer = 0,
        width = 0,
        height = 0,
        playing = true,
        loop = true,
        getWidth = function(self)
            return self.width
        end,
        getHeight = function(self)
            return self.height
        end,
    }

    -- Parse GIF header
    local header = fileData:sub(1, 6)
    if header ~= "GIF87a" and header ~= "GIF89a" then
        error("Not a valid GIF file")
    end
    
    -- Read logical screen descriptor
    local pos = 7
    gif.width = string.byte(fileData, pos) + string.byte(fileData, pos + 1) * 256
    gif.height = string.byte(fileData, pos + 2) + string.byte(fileData, pos + 3) * 256
    
    local packed = string.byte(fileData, pos + 4)
    local hasGlobalColorTable = bit.band(packed, 0x80) ~= 0
    local backgroundColorIndex = string.byte(fileData, pos + 5)
    
    pos = pos + 7
    
    -- Read global color table
    local globalColorTable = {}
    if hasGlobalColorTable then
        local size = 2 ^ (bit.band(packed, 0x07) + 1)
        for i = 1, size do
            local r = string.byte(fileData, pos) / 255
            local g = string.byte(fileData, pos + 1) / 255
            local b = string.byte(fileData, pos + 2) / 255
            table.insert(globalColorTable, {r, g, b, 1})
            pos = pos + 3
        end
    end
    
    -- Parse blocks
    local delay = 0.1
    local transparentIndex = nil
    local disposalMethod = 0
    local delayForNextFrame = 0.1  -- Track delay for next frame
    
    while pos <= #fileData do
        local separator = string.byte(fileData, pos)
        
        if separator == 0x21 then -- Extension
            local label = string.byte(fileData, pos + 1)
            pos = pos + 2
            
            if label == 0xF9 then -- Graphic Control Extension
                local blockSize = string.byte(fileData, pos)
                pos = pos + 1
                
                local flags = string.byte(fileData, pos)
                disposalMethod = bit.rshift(bit.band(flags, 0x1C), 2)
                local hasTransparency = bit.band(flags, 0x01) ~= 0
                
                local delayTime = string.byte(fileData, pos + 1) + string.byte(fileData, pos + 2) * 256
                -- GIF delay is in hundredths of a second, convert to seconds
                -- Many GIFs use 0 or very small delays, set a minimum
                if delayTime == 0 then
                    delayForNextFrame = 0.1  -- Default 100ms
                elseif delayTime <= 2 then
                    delayForNextFrame = 0.02  -- Minimum 20ms for very fast animations
                else
                    delayForNextFrame = delayTime / 100
                end
                
                if hasTransparency then
                    transparentIndex = string.byte(fileData, pos + 3)
                else
                    transparentIndex = nil
                end
                
                pos = pos + blockSize + 1
            else
                -- Skip other extensions
                repeat
                    local blockSize = string.byte(fileData, pos)
                    pos = pos + 1
                    if blockSize > 0 then
                        pos = pos + blockSize
                    end
                until blockSize == 0
            end
            
        elseif separator == 0x2C then -- Image Descriptor
            pos = pos + 1
            
            local left = string.byte(fileData, pos) + string.byte(fileData, pos + 1) * 256
            local top = string.byte(fileData, pos + 2) + string.byte(fileData, pos + 3) * 256
            local width = string.byte(fileData, pos + 4) + string.byte(fileData, pos + 5) * 256
            local height = string.byte(fileData, pos + 6) + string.byte(fileData, pos + 7) * 256
            
            local imgPacked = string.byte(fileData, pos + 8)
            local hasLocalColorTable = bit.band(imgPacked, 0x80) ~= 0
            local interlaced = bit.band(imgPacked, 0x40) ~= 0
            
            pos = pos + 9
            
            local colorTable = globalColorTable
            if hasLocalColorTable then
                local size = 2 ^ (bit.band(imgPacked, 0x07) + 1)
                colorTable = {}
                for i = 1, size do
                    local r = string.byte(fileData, pos) / 255
                    local g = string.byte(fileData, pos + 1) / 255
                    local b = string.byte(fileData, pos + 2) / 255
                    table.insert(colorTable, {r, g, b, 1})
                    pos = pos + 3
                end
            end
            
            -- Read LZW minimum code size
            local minCodeSize = string.byte(fileData, pos)
            pos = pos + 1
            
            -- Read compressed image data blocks
            local compressedData = {}
            while true do
                local blockSize = string.byte(fileData, pos)
                pos = pos + 1
                if blockSize == 0 then break end
                table.insert(compressedData, fileData:sub(pos, pos + blockSize - 1))
                pos = pos + blockSize
            end
            
            -- Decompress image data
            local indexStream = decompressLZW(table.concat(compressedData), minCodeSize)
            
            -- Create image data
            local imageData = love.image.newImageData(gif.width, gif.height)
            
            -- Fill with background if first frame
            if #gif.frames == 0 and backgroundColorIndex and globalColorTable[backgroundColorIndex + 1] then
                local bg = globalColorTable[backgroundColorIndex + 1]
                for y = 0, gif.height - 1 do
                    for x = 0, gif.width - 1 do
                        imageData:setPixel(x, y, bg[1], bg[2], bg[3], bg[4])
                    end
                end
            elseif #gif.frames > 0 then
                -- Copy previous frame if needed
                local prevData = gif.frameData[#gif.frameData]
                imageData:paste(prevData, 0, 0, 0, 0, gif.width, gif.height)
            end
            
            -- Draw current frame
            if indexStream and #indexStream > 0 then
                local idx = 1
                
                -- Use mapPixel for faster pixel operations
                local function setPixels(x, y, r, g, b, a)
                    if x >= left and x < left + width and y >= top and y < top + height then
                        local pixelIdx = (y - top) * width + (x - left) + 1
                        if pixelIdx <= #indexStream then
                            local colorIndex = string.byte(indexStream, pixelIdx)
                            
                            -- Skip transparent pixels
                            if transparentIndex == nil or colorIndex ~= transparentIndex then
                                if colorTable[colorIndex + 1] then
                                    local color = colorTable[colorIndex + 1]
                                    return color[1], color[2], color[3], color[4]
                                end
                            end
                        end
                    end
                    return r, g, b, a
                end
                
                -- Only update the region where the frame is located
                for y = top, top + height - 1 do
                    for x = left, left + width - 1 do
                        local pixelIdx = (y - top) * width + (x - left) + 1
                        if pixelIdx <= #indexStream then
                            local colorIndex = string.byte(indexStream, pixelIdx)
                            
                            -- Skip transparent pixels
                            if transparentIndex == nil or colorIndex ~= transparentIndex then
                                if colorTable[colorIndex + 1] then
                                    local color = colorTable[colorIndex + 1]
                                    imageData:setPixel(x, y, color[1], color[2], color[3], color[4])
                                end
                            end
                        end
                    end
                end
            end
            
            table.insert(gif.frameData, imageData)
            table.insert(gif.frames, love.graphics.newImage(imageData))
            table.insert(gif.delays, delayForNextFrame)
            
            -- Reset delay for next frame
            delayForNextFrame = 0.1
            
        elseif separator == 0x3B then -- Trailer
            break
        else
            pos = pos + 1
        end
    end
    
    if #gif.frames == 0 then
        error("No frames found in GIF")
    end
    
    -- Ensure all frames have valid delays
    for i = 1, #gif.delays do
        if gif.delays[i] <= 0 or gif.delays[i] ~= gif.delays[i] then -- check for 0 or NaN
            gif.delays[i] = 0.1
        end
    end
    
    return gif
end

function GifLoader.Updater(gif, proc)
    local wait = function()
        return gif.playing or gif.kill
    end
    proc:newThread("Gif Handler",function()
        while true do
            -- Only run if not paused
            if gif.kill then -- When we want to clean up
                thread.kill()
            end
            thread.hold(wait)
            thread.sleep(gif.delays[gif.currentFrame] * 4)
            gif.currentFrame = gif.currentFrame + 1
        
            if gif.currentFrame > #gif.frames then
                if gif.loop then
                    gif.currentFrame = 1
                else
                    gif.currentFrame = #gif.frames
                    gif.playing = false
                    gif.timer = 0
                end
            end
        end
    end)
end

function GifLoader.update(gif, dt)
    if not gif.playing or #gif.frames <= 1 then return end
    
    gif.timer = gif.timer + dt
    
    -- Simple, accurate frame advancement
    if gif.timer >= gif.delays[gif.currentFrame] then
        -- Subtract the current frame's delay
        gif.timer = gif.timer - gif.delays[gif.currentFrame]
        
        -- Move to next frame
        gif.currentFrame = gif.currentFrame + 1
        
        if gif.currentFrame > #gif.frames then
            if gif.loop then
                gif.currentFrame = 1
            else
                gif.currentFrame = #gif.frames
                gif.playing = false
                gif.timer = 0
            end
        end
        
        -- If we've accumulated too much time (lag spike), cap it
        if gif.timer > 0.5 then
            gif.timer = 0
        end
    end
end

function GifLoader.draw(gif, x, y, r, sx, sy, ox, oy)
    if gif.frames[gif.currentFrame] then
        love.graphics.draw(gif.frames[gif.currentFrame], x, y, r or 0, sx or 1, sy or 1, ox or 0, oy or 0)
    end
end

function GifLoader.play(gif)
    gif.playing = true
end

function GifLoader.pause(gif)
    gif.playing = false
end

function GifLoader.reset(gif)
    gif.currentFrame = 1
    gif.timer = 0
end

function GifLoader.setFixedFramerate(gif, fps)
    local delay = 1 / fps
    for i = 1, #gif.delays do
        gif.delays[i] = delay
    end
end

function GifLoader.getInfo(gif)
    return {
        width = gif.width,
        height = gif.height,
        frameCount = #gif.frames,
        delays = gif.delays, -- Show actual delays for debugging
        totalDuration = (function()
            local total = 0
            for i = 1, #gif.delays do
                total = total + gif.delays[i]
            end
            return total
        end)()
    }
end

return GifLoader

-- USAGE:
--[[
local GifLoader = require("gifloader")

function love.load()
    myGif = GifLoader.load("animation.gif")
    myGif.loop = true
end

function love.update(dt)
    GifLoader.update(myGif, dt)
end

function love.draw()
    GifLoader.draw(myGif, 100, 100)
    
    -- Draw scaled
    GifLoader.draw(myGif, 300, 100, 0, 2, 2)
end
]]