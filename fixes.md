Review of [`gui/init.lua`](gui/init.lua:1) complete — no changes were made. Key improvement areas identified:

**Likely bugs:**
- Global leak in [`getLocalCords`](gui/init.lua:495) (line 496, missing `local` on `x, y, w, h`) and in the shader loader (line 2559, `files`).
- Clone broken for images: [`getUniques`](gui/init.lua:1920) returns key `DO` (line 1923) but [`clone`](gui/init.lua:524) reads `u.Do[2]` (lines 535/537).
- [`newImageButton`](gui/init.lua:2007) never sets the `button` type bit (uses `newImageBase(frame, ...)`), so `hasType(button)` and the clone `image + button` branch never match.
- [`fitFont`](gui/init.lua:1227) discards the binary-search result (lines 1281–1285) and crashes on `mid*opt.scale` when `opt` is passed without `scale`.
- [`setFont`](gui/init.lua:1201) caches the raw argument instead of the created Font object (line 1215).
- [`getTile`](gui/init.lua:431) caches `image_cache[i] = i` keyed by userdata instead of the path (line 437).
- [`calculateFontOffset`](gui/init.lua:1156) sets `f_bot = false` where it should be `true` (line 1189).
- [`insert`](gui/init.lua:1759) double-increments `cur_pos` for multi-char text; [`delete`](gui/init.lua:1775) mixes `obj`/`object_focus`; textbox `OnKeyPressed` lacks `cur_pos` bounds checks.
- [`setImage`](gui/init.lua:1941) uses `i:match(".gif")` — `.` is a wildcard and case-sensitive (line 1944); should be `%.gif$`.
- [`setShader`](gui/init.lua:760) errors on nil `env`; [`GetSizeAdjustedToAspectRatio`](gui/init.lua:2492) divides by zero when `g_height` is 0.

**Subtle logic issues:** `clone` compares `v.Type == "connector"` string vs the `CONNECTOR_TYPE` constant (line 550); `drawBorder`/`drawborder` casing mismatch (line 586); [`OnCreated`](gui/init.lua:1003) `isDescendantOf` check looks inverted (line 1005); [`OnWheelMoved`](gui/init.lua:994) passes undefined globals to `defaultCheck`; `makeCircle`/`makeArc` pass 7 args to 8-param `setDualDim`; [`extend`](gui/init.lua:652) ignores its `typ` argument at the call site (line 1104); [`newVideo`](gui/init.lua:2016) leaks its handler thread on destroy; [`textBoxThread`](gui/init.lua:1743) `.OnError` recursion can spin.

**Performance:** [`rebuildLabels`](gui/init.lua:1371) recreates every line label per keystroke; `love.graphics.newFont(13)` re-created per call in `updateCursor` (line 1422); [`has_blur_ancestor`](gui/init.lua:2319) walks the ancestor chain for every child every frame; the "Draw Handler" thread (lines ~2433–2442) polls the whole tree 10×/s to refresh cached geometry.

**Dead code/naming:** [`offsetToScale`](gui/init.lua:360) is a no-op; unused `utf8`, `bor`, `cursor_hand`, `clips`, `anim`, empty `drawtypes[16]`, `dt`/`pos`/`as`/`ae` params; typos `intersecpt`, `getLocalCords`, `videoHeigth`, `doselection`, `evnt_type`.

**Structure:** the 2565-line monolith splits cleanly into events, geometry, elements, textarea, and draw modules under the existing [`gui/core/`](gui/core) pattern.