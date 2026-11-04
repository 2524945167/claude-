local bit, ffi = require("bit"), require("ffi")
local TAB, CON = "AA", "Anti-aimbot angles"
local conditions = {"Global", "Standing", "Moving", "Slowwalk", "Air", "Air+", "Duck", "Duck move", "Freestanding", "On peek"}
local util, ref, aa, native, style, gui, menu, builder, config = {}, {aa = {}, other = {}}, {}, {}, {}, {}, {}, {}, {}
local state, move, seq, def, pro, fl, slow_pro, pulse, antiaim, fs = {}, {}, {}, {}, {state = {}}, {}, {}, {}, {}, {}
local hitlog, rh, dormant, qs, hc, stop, override, comm, clan, perf, anim, drop, fd = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
local tp, scope, hud, ind, octo, core, lang = {}, {}, {}, {}, {}, {}, {}


do
    local ok, json = pcall(require, "json")
    util.json = ok and json or nil
    local ok_cp, cp = pcall(require, "gamesense/clipboard")
    if ok_cp and type(cp) == "table" and cp.get and cp.set then
        util.clipboard = cp
    else
        pcall(ffi.cdef, [[
            typedef void* HANDLE;
            typedef void* HGLOBAL;
            typedef void* HWND;
            typedef unsigned int UINT;
            HWND GetActiveWindow(void);
            bool OpenClipboard(HWND hWndNewOwner);
            bool CloseClipboard(void);
            bool EmptyClipboard(void);
            HANDLE SetClipboardData(UINT uFormat, HANDLE hMem);
            HANDLE GetClipboardData(UINT uFormat);
            HGLOBAL GlobalAlloc(UINT uFlags, size_t dwBytes);
            void* GlobalLock(HGLOBAL hMem);
            bool GlobalUnlock(HGLOBAL hMem);
            HGLOBAL GlobalFree(HGLOBAL hMem);
            size_t GlobalSize(HGLOBAL hMem);
        ]])
        local user32, kernel32 = ffi.load("user32.dll"), ffi.load("kernel32.dll")
        util.clipboard = {
            get = function()
                assert(user32.OpenClipboard(nil), "clipboard: OpenClipboard failed")
                local memory, pointer
                local ok_get, text = pcall(function()
                    memory = user32.GetClipboardData(1)
                    if memory == nil then return "" end
                    local size = tonumber(kernel32.GlobalSize(memory))
                    assert(size and size > 0 and size <= 2097153, "clipboard: invalid or oversized text")
                    pointer = kernel32.GlobalLock(memory)
                    assert(pointer ~= nil, "clipboard: GlobalLock failed")
                    local bytes = ffi.string(pointer, size)
                    local finish = bytes:find("\0", 1, true)
                    assert(finish, "clipboard: text is not NUL-terminated")
                    return bytes:sub(1, finish - 1)
                end)
                if pointer ~= nil then kernel32.GlobalUnlock(memory) end
                user32.CloseClipboard()
                if not ok_get then error(text, 0) end
                return text
            end,
            set = function(text)
                text = tostring(text)
                local memory = kernel32.GlobalAlloc(0x0042, #text + 1)
                assert(memory ~= nil, "clipboard: GlobalAlloc failed")
                local pointer = kernel32.GlobalLock(memory)
                if pointer == nil then kernel32.GlobalFree(memory); error("clipboard: GlobalLock failed") end
                ffi.copy(pointer, text, #text)
                ffi.cast("char*", pointer)[#text] = 0
                kernel32.GlobalUnlock(memory)
                local owner = user32.GetActiveWindow()
                if owner == nil or not user32.OpenClipboard(owner) then
                    kernel32.GlobalFree(memory)
                    error("clipboard: active window unavailable or OpenClipboard failed")
                end
                if not user32.EmptyClipboard() or user32.SetClipboardData(1, memory) == nil then
                    user32.CloseClipboard()
                    kernel32.GlobalFree(memory)
                    error("clipboard: SetClipboardData failed")
                end
                user32.CloseClipboard()
                return true
            end
        }
    end
end

function util.finite(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

function util.pressed(v)
    return v == true or type(v) == "number" and v ~= 0
end

function util.contains(list, name)
    for i = 1, #list do
        if list[i] == name then return true end
    end
    return false
end

function util.active(r)
    local v = ui.get(r)
    if type(v) == "table" then return #v > 0 end
    return v ~= nil and v ~= false and v ~= "Off"
end

function util.has(r, name)
    local v = ui.get(r)
    if type(v) ~= "table" then return v == name end
    return util.contains(v, name)
end

function util.clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

function util.normalize(y)
    while y > 180 do y = y - 360 end
    while y < -180 do y = y + 360 end
    return y
end

function util.view_delta(x, y, ox, oy, view)
    return math.abs(util.normalize(math.deg(math.atan2(y - oy, x - ox)) - view))
end

function util.hotkey(r)
    return ui.get(r[1]) == true and (r[2] == nil or ui.get(r[2]) == true)
end

function util.exploit()
    return util.hotkey(ref.dt) or util.hotkey(ref.os)
end

function util.live()
    local me = entity.get_local_player()
    return ui.get(gui.master) and me and entity.is_alive(me), me
end

function util.velocity(ent)
    return entity.get_prop(ent, "m_vecVelocity[0]") or 0, entity.get_prop(ent, "m_vecVelocity[1]") or 0, entity.get_prop(ent, "m_vecVelocity[2]") or 0
end

function util.speed(ent)
    local vx, vy = util.velocity(ent)
    return math.sqrt(vx * vx + vy * vy)
end

function util.on_ground(ent)
    return bit.band(entity.get_prop(ent, "m_fFlags") or 0, 1) ~= 0
end

function util.scoped(ent)
    return util.pressed(entity.get_prop(ent, "m_bIsScoped"))
end

function util.can_fire(me, weapon, slack)
    local ready = math.max(entity.get_prop(me, "m_flNextAttack") or 0, entity.get_prop(weapon, "m_flNextPrimaryAttack") or 0)
    return ready <= (entity.get_prop(me, "m_nTickBase") or 0) * globals.tickinterval() + (slack or 0)
end

function util.weapons(me)
    local list = {}
    for index = 0, 63 do
        local handle = entity.get_prop(me, "m_hMyWeapons", index)
        if util.finite(handle) and handle > 0 and bit.band(handle, 4095) > 0 then list[#list + 1] = bit.band(handle, 4095) end
    end
    return list
end

function util.segment_distance(px, py, pz, ax, ay, az, bx, by, bz)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local len = dx * dx + dy * dy + dz * dz
    local t = len > 0 and util.clamp(((px - ax) * dx + (py - ay) * dy + (pz - az) * dz) / len, 0, 1) or 0
    local x, y, z = ax + dx * t - px, ay + dy * t - py, az + dz * t - pz
    return math.sqrt(x * x + y * y + z * z)
end

function util.by_distance(a, b)
    return a.d < b.d
end

function util.weapon_id(me)
    local weapon = entity.get_player_weapon(me)
    if not weapon or weapon == 0 then return end
    local id = entity.get_prop(weapon, "m_iItemDefinitionIndex")
    if not util.finite(id) or id % 1 ~= 0 then return end
    return bit.band(id, 0xFFFF), weapon
end

function util.frame_dt()
    local dt = globals.frametime()
    return util.finite(dt) and math.max(0, math.min(0.1, dt)) or 0
end


ref.aa.enabled = ui.reference(TAB, CON, "Enabled")
ref.aa.pitch, ref.aa.pitch_add = ui.reference(TAB, CON, "Pitch")
ref.aa.yaw_base = ui.reference(TAB, CON, "Yaw base")
ref.aa.yaw, ref.aa.yaw_add = ui.reference(TAB, CON, "Yaw")
ref.aa.yaw_jitter, ref.aa.yaw_jit_add = ui.reference(TAB, CON, "Yaw jitter")
ref.aa.body_yaw, ref.aa.body_yaw_add = ui.reference(TAB, CON, "Body yaw")
ref.aa.fs_body = ui.reference(TAB, CON, "Freestanding body yaw")
ref.aa.edge_yaw = ui.reference(TAB, CON, "Edge yaw")
ref.aa.freestand, ref.aa.fs_mode = ui.reference(TAB, CON, "Freestanding")
ref.aa.roll = ui.reference(TAB, CON, "Roll")
ref.aa.fake_enabled = ui.reference(TAB, "Fake lag", "Enabled")
ref.aa.fake_amt = ui.reference(TAB, "Fake lag", "Amount")
ref.aa.fake_var = ui.reference(TAB, "Fake lag", "Variance")
ref.aa.fake_limit = ui.reference(TAB, "Fake lag", "Limit")
for _, name in ipairs({"On shot anti-aim", "Slow motion", "Fake peek", "Leg movement"}) do
    local a, b = ui.reference(TAB, "Other", name)
    ref.other[#ref.other + 1] = a
    ref.other[#ref.other + 1] = b
end
ref.dt = {ui.reference("RAGE", "Aimbot", "Double tap")}
ref.baim = {ui.reference("RAGE", "Aimbot", "Force body aim")}
ref.md = {ui.reference("RAGE", "Aimbot", "Minimum damage override")}
ref.os = {ui.reference("AA", "Other", "On shot anti-aim")}
ref.mindmg = {ui.reference("RAGE", "Aimbot", "Minimum damage")}
ref.hitchance = ui.reference("RAGE", "Aimbot", "Minimum hit chance")
do
    local ok, r = pcall(ui.reference, "RAGE", "Weapon type", "Weapon type")
    ref.weapon_type = ok and r or nil
end
ref.duck = ui.reference("RAGE", "Other", "Duck peek assist")
ref.peek, ref.peek_key = ui.reference("RAGE", "Other", "Quick peek assist")
ref.resolver = ui.reference("RAGE", "Other", "Anti-aim correction")
ref.slow_key = select(2, ui.reference(TAB, "Other", "Slow motion"))
ref.legs = ui.reference(TAB, "Other", "Leg movement")
ref.scope = ui.reference("VISUALS", "Effects", "Remove scope overlay")
ref.dormant_esp = ui.reference("VISUALS", "Player ESP", "Dormant")
ref.dpi = ui.reference("MISC", "Settings", "DPI scale")


aa.active, aa.priority, aa.value, aa.rank, aa.managed, aa.refs = false, 0, {}, {}, {}, {}
for _, key in ipairs({"enabled", "pitch", "pitch_add", "yaw_base", "yaw", "yaw_add", "yaw_jitter", "yaw_jit_add", "body_yaw", "body_yaw_add", "fs_body", "edge_yaw", "roll"}) do
    aa.refs[#aa.refs + 1] = ref.aa[key]
    aa.managed[ref.aa[key]] = true
end

function aa.clear()
    for i = 1, #aa.refs do aa.value[aa.refs[i]], aa.rank[aa.refs[i]] = nil, nil end
end

function aa.begin(priority)
    aa.active = true
    aa.priority = priority or 0
    aa.jitter_offset = 0
    aa.clear()
end

function aa.owner(priority)
    aa.priority = priority or 0
end

function aa.cancel()
    aa.active = false
    aa.clear()
end

function aa.commit()
    aa.active = false
    for i = 1, #aa.refs do
        local r = aa.refs[i]
        if aa.rank[r] then ui.set(r, aa.value[r]) end
    end
    aa.clear()
end

function aa.set(r, value)
    if aa.active and aa.managed[r] then
        if not aa.rank[r] or aa.priority >= aa.rank[r] then aa.value[r], aa.rank[r] = value, aa.priority end
        return true
    end
    ui.set(r, value)
    return true
end


native.hotkey_modes = {"Always on", "On hotkey", "Toggle", "Off hotkey"}

function native.visible(visible)
    for _, r in pairs(ref.aa) do ui.set_visible(r, visible) end
    for _, r in ipairs(ref.other) do ui.set_visible(r, visible) end
end

function native.capture()
    if native.snapshot then return end
    local snapshot = {}
    for key, r in pairs(ref.aa) do
        if key == "fs_mode" then
            local _, mode, hotkey = ui.get(r)
            if native.hotkey_modes[(tonumber(mode) or -1) + 1] then
                snapshot[key] = {native.hotkey_modes[mode + 1], tonumber(hotkey) or 0}
            end
        else
            local value = ui.get(r)
            if value ~= nil then snapshot[key] = {value} end
        end
    end
    native.snapshot = snapshot
end

function native.reset()
    local snapshot = native.snapshot
    native.snapshot = nil
    if not snapshot then return end
    for key, values in pairs(snapshot) do ui.set(ref.aa[key], unpack(values)) end
end

function native.value(key)
    local saved = native.snapshot and native.snapshot[key]
    return saved and saved[1]
end


style.version = "2.1"
style.text, style.muted = {241, 231, 226}, {141, 133, 128}
style.sub, style.warn, style.off = "\a8D8580FF› \aCDCDCDFF", "\aE5735FFF", "  \a8D8580FF· off"

function style.accent()
    return ui.get(gui.qucy_color)
end

function style.log(message)
    local r, g, b = style.accent()
    client.color_log(r, g, b, "[Ünoins_qucy] \0")
    client.color_log(style.text[1], style.text[2], style.text[3], message)
end


menu.tabs = {"Home", "Builder", "Defensive", "Binds", "Rage", "World", "Visuals"}
menu.controls, menu.headers = {}, {}

function menu.add(key, kind, page, group, parent, name, ...)
    if parent and kind ~= "hotkey" and kind ~= "color_picker" and name:sub(1, 1) ~= "\n" then name = style.sub .. name end
    local r = ui["new_" .. kind](TAB, group, name, ...)
    local control = {key = key, ref = r, kind = kind, page = page, parent = parent}
    gui[key] = r
    menu.controls[#menu.controls + 1] = control
    return r, control
end

function menu.when(control, ...)
    control.when = {...}
    return control
end

function menu.label(page, group, text)
    local r = ui.new_label(TAB, group, text .. "\n" .. page .. #menu.headers)
    menu.headers[#menu.headers + 1] = {page = page, ref = r}
    return r
end

function menu.header(page, group, name)
    return menu.label(page, group, "\aD97757FF" .. name)
end


gui.welcome = menu.header("Home", CON, "Welcome back")
menu.label("Home", CON, "Build " .. style.version .. " · Ünoins_qucy")
gui.master = ui.new_checkbox(TAB, CON, "\aD97757FFÜnoins_qucy")
gui.pet = ui.new_checkbox(TAB, CON, "Show octopus on menu")
gui.banner = ui.new_checkbox(TAB, CON, "Draw menu banner")
ui.set(gui.pet, true)
ui.set(gui.banner, true)
menu.header("Home", CON, "Changelog")
for _, entry in ipairs({
    {"2026-11-04", {"In-game language switcher in the CS:GO settings page"}},
    {"2026-10-13", {
        "Fix: slider unit text not shown", "Auto resolver off: marked SSG 08 only", "Scope: fine tune folded",
        "Resolver: miss filter, learning, onshot, animstate", "Leaner freestanding reads, Binds styling",
        "Hit chance written to the weapon type group", "DT release weapons default to Off",
        "Fix: Ünoins_qucy freestanding hid the wrong side", "Freestanding: native side, read back", "Freestanding engine option removed"
    }}
}) do
    menu.label("Home", CON, "\a8D8580FFv" .. style.version .. " · " .. entry[1])
    for _, line in ipairs(entry[2]) do menu.label("Home", CON, "· " .. line) end
end

gui.page = ui.new_combobox(TAB, "Fake lag", "Tab", menu.tabs)
menu.header("Home", "Fake lag", "Session")
gui.session = {
    menu.label("Home", "Fake lag", "Loaded  00:00"),
    menu.label("Home", "Fake lag", "Ping  --"),
    menu.label("Home", "Fake lag", "Map  --")
}

function config.names()
    local list = database.read("unoins_cfg_list")
    if type(list) == "table" and #list > 0 then return list end
    return {"default"}
end

config.list = config.names()
menu.header("Home", "Other", "Configs")
gui.cfg_list = ui.new_listbox(TAB, "Other", "Configs", config.list)
gui.cfg_name = ui.new_textbox(TAB, "Other", "Config name")
gui.cfg_load = ui.new_button(TAB, "Other", "Load", function() end)
gui.cfg_save = ui.new_button(TAB, "Other", "Save", function() end)
gui.cfg_delete = ui.new_button(TAB, "Other", "Delete", function() end)
gui.cfg_import = ui.new_button(TAB, "Other", "Import from clipboard", function() end)
gui.cfg_export = ui.new_button(TAB, "Other", "Export to clipboard", function() end)

menu.header("Defensive", "Other", "Engine")
gui.backend = ui.new_combobox(TAB, "Other", "Backend", "\a8D8580FFGamesense\r", "\aD97757FFÜnoins_qucy\r", "\aF2C6B4FFÜnoins_qucy Pro\r")

menu.header("Binds", "Fake lag", "Safety")
gui.safe_head = ui.new_multiselect(TAB, "Fake lag", "Safe head", "Knife", "Taser", "Glock-18")
gui.backstab = ui.new_checkbox(TAB, "Fake lag", "Anti backstab")
menu.header("Binds", CON, "Manual yaw")
gui.manual_left = ui.new_hotkey(TAB, CON, "Left", false)
gui.manual_right = ui.new_hotkey(TAB, CON, "Right", false)
gui.manual_fwd = ui.new_hotkey(TAB, CON, "Forward", false)
gui.fs_key = ui.new_hotkey(TAB, CON, "Freestanding\nfs_key", false)
gui.fs_states = ui.new_multiselect(TAB, CON, style.sub .. "States\nfs_states", "Standing", "Moving", "Slowwalk", "Air", "Air+", "Duck", "Duck move")
gui.fs_options = ui.new_multiselect(TAB, CON, style.sub .. "Options\nfs_options", "Disable yaw jitter", "Disable body yaw")
gui.edge_key = ui.new_hotkey(TAB, CON, "Edge yaw\nedge_key", false)
menu.header("Binds", "Other", "Movement")
gui.fast_ladder = ui.new_checkbox(TAB, "Other", "Fast ladder")
menu.add("duck_fd", "checkbox", "Binds", "Other", nil, "\aD97757FFFake duck Freedom\r")

gui.cond_header = ui.new_label(TAB, "Fake lag", "\aD97757FFCondition")
gui.condition = ui.new_listbox(TAB, "Fake lag", "Condition", conditions)

menu.header("Visuals", CON, "Indicators")
gui.indicator = ui.new_combobox(TAB, CON, "Style\nindicator", "Off", "Ünoins_qucy", "Half-life", "Ideal yaw", "Ünoins_qucy new")
gui.qucy_color = ui.new_color_picker(TAB, CON, "\nIndicator accent color", 217, 119, 87, 255)
menu.controls[#menu.controls + 1] = {key = "qucy_color", ref = gui.qucy_color, kind = "color_picker", page = "Visuals", indicator = {["Ünoins_qucy"] = true, ["Ünoins_qucy new"] = true}}
select(2, menu.add("qucy_offset", "slider", "Visuals", CON, nil, "Indicator offset", 20, 180, 28, true, "px")).indicator = {["Ünoins_qucy new"] = true}
menu.add("ind_extras", "multiselect", "Visuals", CON, nil, "Indicator extras", "Group name", "Damage")
menu.add("velocity", "checkbox", "Visuals", CON, nil, "Momentum HUD")
menu.add("scope", "checkbox", "Visuals", "Fake lag", nil, "\aD97757FFScope lines\r")
menu.add("scope_color", "color_picker", "Visuals", "Fake lag", "scope", "Scope accent", 217, 119, 87, 235)
menu.add("scope_style", "combobox", "Visuals", "Fake lag", "scope", "Style\nscope", "Soft", "Classic", "Diagonal")
menu.add("scope_tune", "checkbox", "Visuals", "Fake lag", "scope", "Fine tune\nscope")
select(2, menu.add("scope_length", "slider", "Visuals", "Fake lag", "scope", "Length\nscope", 20, 260, 105, true, "px")).parent2 = "scope_tune"
select(2, menu.add("scope_gap", "slider", "Visuals", "Fake lag", "scope", "Gap\nscope", 0, 90, 10, true, "px")).parent2 = "scope_tune"
select(2, menu.add("scope_thickness", "combobox", "Visuals", "Fake lag", "scope", "Thickness\nscope", "Thin", "Regular", "Bold")).parent2 = "scope_tune"
select(2, menu.add("scope_exclude", "multiselect", "Visuals", "Fake lag", "scope", "Hidden arms", "Top", "Bottom", "Left", "Right")).parent2 = "scope_tune"
menu.header("Visuals", "Other", "Thirdperson")
gui.hide_weapon = ui.new_checkbox(TAB, "Other", "Hide weapon")

menu.add("aim_tools", "checkbox", "Rage", CON, nil, "\aD97757FFAim tools\r")
menu.aim_names = {"DT release", "No scope", "Quick stop", style.warn .. "Auto resolver off · SSG 08\r"}
menu.aim_keys = {"aim_release", "aim_noscope", "aim_quickstop", "aim_resolver_off"}
menu.add("aim_list", "listbox", "Rage", CON, "aim_tools", "\naim_list", menu.aim_names)
for i, key in ipairs(menu.aim_keys) do menu.when(select(2, menu.add(key, "checkbox", "Rage", CON, "aim_tools", "Enabled\n" .. key)), "aim_list", i - 1) end
menu.when(select(2, menu.add("release_weapon", "combobox", "Rage", CON, "aim_tools", "Weapon\nrelease", "SSG 08", "Desert Eagle", "R8 Revolver")), "aim_list", 0).parent2 = "aim_release"
hc.release, hc.saved = {}, {}
hc.groups = {[40] = "SSG 08", [9] = "AWP", [38] = "G3SG1 / SCAR-20", [11] = "G3SG1 / SCAR-20", [1] = "Desert Eagle", [64] = "R8 Revolver", [8] = "Rifle", [39] = "Rifle"}
for _, weapon in ipairs({{40, "SSG 08", "ssg08"}, {1, "Desert Eagle", "deagle"}, {64, "R8 Revolver", "r8"}}) do
    local key = "release_" .. weapon[3]
    local r, c = menu.add(key, "slider", "Rage", CON, "aim_tools", "Hit chance\n" .. key, -1, 100, -1, true, "%", 1, {[-1] = "Off"})
    menu.when(c, "aim_list", 0, "release_weapon", weapon[2]).parent2 = "aim_release"
    hc.release[weapon[1]] = r
end
menu.when(select(2, menu.add("noscope_weapon", "combobox", "Rage", CON, "aim_tools", "Weapon\nnoscope", "SSG 08", "SCAR-20", "G3SG1", "AWP", "AUG", "SG 553")), "aim_list", 1).parent2 = "aim_noscope"
hc.noscope = {}
for _, weapon in ipairs({{40, "SSG 08", "ssg08"}, {38, "SCAR-20", "scar20"}, {11, "G3SG1", "g3sg1"}, {9, "AWP", "awp"}, {8, "AUG", "aug"}, {39, "SG 553", "sg553"}}) do
    local key = "noscope_" .. weapon[3]
    local r, c = menu.add(key, "slider", "Rage", CON, "aim_tools", "Hit chance\n" .. key, -1, 100, -1, true, "%", 1, {[-1] = "Off"})
    menu.when(c, "aim_list", 1, "noscope_weapon", weapon[2]).parent2 = "aim_noscope"
    hc.noscope[weapon[1]] = r
end
menu.when(select(2, menu.add("quick_stop_mode", "combobox", "Rage", CON, "aim_tools", "Activation\nstop", "Visible target", "On attack")), "aim_list", 2).parent2 = "aim_quickstop"
menu.when(select(2, menu.add("stop_fov", "slider", "Rage", CON, "aim_tools", "Field of view\nstop", 5, 90, 25, true, "°")), "aim_list", 2).parent2 = "aim_quickstop"
menu.when(select(2, menu.add("stop_speed", "slider", "Rage", CON, "aim_tools", "Brake until\nstop", 5, 60, 20, true, "u/s")), "aim_list", 2).parent2 = "aim_quickstop"
menu.when(select(2, menu.add("resolver_off_note", "label", "Rage", CON, "aim_tools", "\a8D8580FFOnly SSG 08 · unscoped · moving")), "aim_list", 3)
menu.when(select(2, menu.add("resolver_off_range", "slider", "Rage", CON, "aim_tools", "Min distance\nresolver_off", 10, 80, 35, true, "ft")), "aim_list", 3).parent2 = "aim_resolver_off"
menu.when(select(2, menu.add("resolver_off_health", "slider", "Rage", CON, "aim_tools", "Min target health\nresolver_off", 1, 100, 93, true, "hp")), "aim_list", 3).parent2 = "aim_resolver_off"
menu.header("Rage", "Fake lag", "Resolver")
gui.resolver = ui.new_checkbox(TAB, "Fake lag", "Enabled\nresolver")
menu.add("resolver_extras", "multiselect", "Rage", "Fake lag", "resolver", "Resolver extras", "Learn per player", "Onshot zero", "Animstate (beta)")
ui.set(gui.resolver_extras, {"Learn per player", "Onshot zero"})
menu.add("dormant", "checkbox", "Rage", "Fake lag", nil, style.warn .. "Dormant aimbot\r")
menu.add("dormant_key", "hotkey", "Rage", "Fake lag", "dormant", "Dormant aimbot key", true)
dormant.groups = {"Global", "Pistols", "Deagle", "R8", "SSG 08", "AWP", "Auto", "Rifles", "SMG", "Heavy"}
menu.add("dormant_weapon", "combobox", "Rage", "Fake lag", "dormant", "Dormant weapon", unpack(dormant.groups))
for i, group in ipairs(dormant.groups) do
    local key = "dormant_" .. i
    if i > 1 then menu.when(select(2, menu.add(key .. "_on", "checkbox", "Rage", "Fake lag", "dormant", "Override\n" .. key)), "dormant_weapon", group) end
    local _, dmg = menu.add(key .. "_dmg", "slider", "Rage", "Fake lag", "dormant", "Min damage\n" .. key, 0, 100, 0, true, "hp", 1, {[0] = "Auto"})
    local _, chance = menu.add(key .. "_hc", "slider", "Rage", "Fake lag", "dormant", "Hit chance\n" .. key, 0, 100, 50, true, "%")
    for _, c in ipairs({dmg, chance}) do menu.when(c, "dormant_weapon", group).parent2 = i > 1 and key .. "_on" or nil end
end
menu.add("dormant_auto", "multiselect", "Rage", "Fake lag", "dormant", "Dormant automation", "Auto scope", "Auto stop", "Dormant ESP", "Indicator")
ui.set(gui.dormant_auto, {"Auto scope", "Auto stop", "Dormant ESP", "Indicator"})
menu.header("Rage", "Other", "Shooting")
menu.add("onshot", "checkbox", "Rage", "Other", nil, "\aD97757FFOn shot sync\r")
menu.add("quick_switch_list", "multiselect", "Rage", "Other", nil, "Quick switch after shot", "SSG 08", "AWP")
gui.hitlog = ui.new_checkbox(TAB, "Other", "Hit log")

menu.header("World", CON, "Animation")
menu.add("anim_ground_pose", "combobox", "World", CON, nil, "Ground pose", "Off", "Static", "Jitter", "Moonwalk")
menu.add("anim_air_pose", "combobox", "World", CON, nil, "Air pose", "Off", "Static", "Cycle")
menu.add("anim_amount", "slider", "World", CON, nil, "Pose amount", 0, 100, 100, true, "%")
menu.when(select(2, menu.add("anim_delay", "slider", "World", CON, nil, "Pose interval", 1, 8, 2, true, "t")), "anim_ground_pose", "Jitter")
menu.add("anim_land", "checkbox", "World", CON, nil, "Level pitch on landing")
menu.header("World", "Fake lag", "Utility")
menu.add("drop", "checkbox", "World", "Fake lag", nil, "Nade relay")
menu.add("drop_key", "hotkey", "World", "Fake lag", "drop", "Nade Relay key", true)
menu.add("drop_types", "multiselect", "World", "Fake lag", "drop", "Grenades\ndrop", "HE", "Smoke", "Fire", "Flash", "Decoy")
gui.clan = ui.new_combobox(TAB, "Fake lag", "Clan tag", "Off", "Half-life.beta", "Ünoins_qucy", "gamesense", "Ideal Yaw")
gui.mute = ui.new_checkbox(TAB, "Fake lag", style.warn .. "Auto mute all players\r")
menu.header("World", "Other", "Performance")
menu.add("fps_effects", "multiselect", "World", "Other", nil, "Reduce effects", "Blood", "Bloom", "Decals", "Shadows", "Ropes", "Debris", "Weapon effects")
menu.add("console", "checkbox", "World", "Other", nil, "Clear Console")
ui.set(gui.drop_types, {"HE", "Smoke", "Fire"})

menu.header("Builder", "Other", "Fake lag")
for _, cond in ipairs(conditions) do
    builder[cond] = {
        enabled = cond ~= "Global" and ui.new_checkbox(TAB, CON, "[" .. cond .. "] Enable") or nil,
        h_yaw = ui.new_label(TAB, CON, "\aD97757FFYaw\n" .. cond .. " h_yaw"),
        yaw_base = ui.new_combobox(TAB, CON, "[" .. cond .. "] Yaw base", "Local view", "At targets"),
        yaw_add = ui.new_slider(TAB, CON, "\n" .. cond .. " yaw", -180, 180, 0, true, "°"),
        yaw_left_right = ui.new_checkbox(TAB, CON, "[" .. cond .. "] Yaw L/R"),
        left = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw left", -180, 180, 0, true, "°"),
        left_randomization = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw left rand", 0, 100, 0, true, "°"),
        right = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw right", -180, 180, 0, true, "°"),
        right_randomization = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw right rand", 0, 100, 0, true, "°"),
        h_jit = ui.new_label(TAB, CON, "\aD97757FFJitter\n" .. cond .. " h_jit"),
        yaw_jitter = ui.new_combobox(TAB, CON, "[" .. cond .. "] Yaw jitter", "Off", "\aD97757FFCenter\r", "Slow", "\aD97757FFSlow Pro\r", "\aD97757FFPulse\r"),
        yaw_jit_add = ui.new_slider(TAB, CON, "\n" .. cond .. " jitter", -180, 180, 30, true, "°"),
        pulse_lopsided = ui.new_checkbox(TAB, CON, "[" .. cond .. "] Pulse lopsided"),
        pulse_extras = ui.new_multiselect(TAB, CON, "[" .. cond .. "] Pulse extras", "Decouple body", "Anti brute"),
        slow_pro_degree = ui.new_slider(TAB, CON, "[" .. cond .. "] Slow Pro degree", 0, 15, 3, true, "°"),
        slow_pro_random = ui.new_slider(TAB, CON, "[" .. cond .. "] Slow Pro randomly", 0, 10, 0, true, "°"),
        slow_pro_speed = ui.new_slider(TAB, CON, "[" .. cond .. "] Slow Pro delay", 0, 6, 0, true, "t", 1, {[0] = "Fast"}),
        slow_pro_mode = ui.new_combobox(TAB, CON, "[" .. cond .. "] Slow Pro mode", "Default", "Randomize", "Cycle lift", "X-way"),
        slow_pro_min = ui.new_slider(TAB, CON, "[" .. cond .. "] Slow Pro lift min", 0, 5, 0, true, "t"),
        slow_pro_max = ui.new_slider(TAB, CON, "[" .. cond .. "] Slow Pro lift max", 1, 6, 1, true, "t"),
        slow_pro_interval = ui.new_slider(TAB, CON, "[" .. cond .. "] Slow Pro lift interval", 1, 30, 1, true, "t"),
        h_body = ui.new_label(TAB, CON, "\aD97757FFBody\n" .. cond .. " h_body"),
        body_yaw = ui.new_combobox(TAB, CON, "[" .. cond .. "] Body yaw", "Off", "Opposite", "\aD97757FFJitter Pro\r", "\aD97757FFStatic Pro\r"),
        body_side = ui.new_combobox(TAB, CON, "[" .. cond .. "] Body side", "+", "-"),
        body_delay = ui.new_slider(TAB, CON, "[" .. cond .. "] Body delay", 1, 17, 1, true, "t", 1, {[1] = "OFF"}),
        force_def = ui.new_checkbox(TAB, CON, "\aD97757FF[" .. cond .. "] Force break lc\r"),
        def_mode = ui.new_combobox(TAB, CON, "[" .. cond .. "] Defensive mode", "Always", "On peek"),
        def_trigger = ui.new_checkbox(TAB, "Other", "\aD97757FF[" .. cond .. "] Defensive trigger\r"),
        def_duration = ui.new_slider(TAB, CON, "\n" .. cond .. " defensive duration", 1, 14, 14, true, "t"),
        h_pitch = ui.new_label(TAB, CON, "\aD97757FFPitch\n" .. cond .. " h_pitch"),
        def_pitch = ui.new_combobox(TAB, CON, "[" .. cond .. "] Defensive pitch", "Off", "Up", "Zero", "Down", "Custom", "Jitter", "Spin", "Auto Spin", "Random", "4Way", "5Way"),
        def_pitch_val = ui.new_slider(TAB, CON, "\n" .. cond .. " def pitch val", -89, 89, 0, true, "°"),
        def_pitch_j1 = ui.new_slider(TAB, CON, "[" .. cond .. "] Pitch jitter 1", -89, 89, -89, true, "°"),
        def_pitch_j2 = ui.new_slider(TAB, CON, "[" .. cond .. "] Pitch jitter 2", -89, 89, 89, true, "°"),
        def_pitch_jdelay = ui.new_slider(TAB, CON, "[" .. cond .. "] Pitch jitter delay", 1, 14, 1, true, "t"),
        def_pitch_speed = ui.new_slider(TAB, CON, "[" .. cond .. "] Pitch spin speed", 1, 10, 4, true),
        def_pitch_r1 = ui.new_slider(TAB, CON, "[" .. cond .. "] Pitch rand min", -89, 89, -89, true, "°"),
        def_pitch_r2 = ui.new_slider(TAB, CON, "[" .. cond .. "] Pitch rand max", -89, 89, 89, true, "°"),
        h_dyaw = ui.new_label(TAB, CON, "\aD97757FFYaw\n" .. cond .. " h_dyaw"),
        def_yaw = ui.new_combobox(TAB, CON, "[" .. cond .. "] Defensive yaw", "Off", "Custom", "Jitter", "Spin", "Auto Spin", "Random", "Opposite", "4Way", "Custom Way"),
        def_yaw_val = ui.new_slider(TAB, CON, "\n" .. cond .. " def yaw val", -180, 180, 0, true, "°"),
        def_yaw_j1 = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw jitter 1", -180, 180, -90, true, "°"),
        def_yaw_j2 = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw jitter 2", -180, 180, 90, true, "°"),
        def_yaw_jdelay = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw jitter delay", 1, 14, 1, true, "t"),
        def_yaw_speed = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw spin speed", 1, 10, 4, true),
        def_yaw_r1 = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw rand min", -180, 180, -180, true, "°"),
        def_yaw_r2 = ui.new_slider(TAB, CON, "[" .. cond .. "] Yaw rand max", -180, 180, 180, true, "°"),
        def_yaw_way_count = ui.new_slider(TAB, CON, "[" .. cond .. "] Custom way count", 1, 10, 4, true),
        def_yaw_ways = {
            ui.new_slider(TAB, CON, "[" .. cond .. "] Way 1 angle", -180, 180, 0, true, "°"),
            ui.new_slider(TAB, CON, "[" .. cond .. "] Way 2 angle", -180, 180, 90, true, "°"),
            ui.new_slider(TAB, CON, "[" .. cond .. "] Way 3 angle", -180, 180, 180, true, "°"),
            ui.new_slider(TAB, CON, "[" .. cond .. "] Way 4 angle", -180, 180, -90, true, "°"),
            ui.new_slider(TAB, CON, "[" .. cond .. "] Way 5 angle", -180, 180, 0, true, "°"),
            ui.new_slider(TAB, CON, "[" .. cond .. "] Way 6 angle", -180, 180, 45, true, "°"),
            ui.new_slider(TAB, CON, "[" .. cond .. "] Way 7 angle", -180, 180, 90, true, "°"),
            ui.new_slider(TAB, CON, "[" .. cond .. "] Way 8 angle", -180, 180, 135, true, "°"),
            ui.new_slider(TAB, CON, "[" .. cond .. "] Way 9 angle", -180, 180, 180, true, "°"),
            ui.new_slider(TAB, CON, "[" .. cond .. "] Way 10 angle", -180, 180, -135, true, "°"),
        },
        h_dbody = ui.new_label(TAB, CON, "\aD97757FFBody\n" .. cond .. " h_dbody"),
        def_body_yaw = ui.new_combobox(TAB, CON, "[" .. cond .. "] Defensive body yaw", "Inherit", "Off", "Opposite", "Jitter Pro", "Static Pro"),
        def_body_side = ui.new_combobox(TAB, CON, "[" .. cond .. "] Defensive body side", "+", "-"),
        def_body_delay = ui.new_slider(TAB, CON, "[" .. cond .. "] Defensive body delay", 1, 17, 1, true, "t"),
        fakelag = ui.new_combobox(TAB, "Other", "Mode\nfl " .. cond, "Off", "Always on", "\aD97757FFAdaptive\r"),
        fl_amount = ui.new_combobox(TAB, "Other", "Amount\nfl " .. cond, "Dynamic", "Maximum", "Fluctuate"),
        fl_variance = ui.new_slider(TAB, "Other", "Variance\nfl " .. cond, 0, 100, 0, true, "%"),
        fl_limit = ui.new_slider(TAB, "Other", "Limit\nfl " .. cond, 1, 15, 14, true, "t"),
    }
end
for _, cond in ipairs(conditions) do
    local c = builder[cond]
    local amount, variance, limit = ui.get(ref.aa.fake_amt), ui.get(ref.aa.fake_var), ui.get(ref.aa.fake_limit)
    ui.set(c.fl_amount, (amount == "Dynamic" or amount == "Maximum" or amount == "Fluctuate") and amount or "Maximum")
    if type(variance) == "number" then ui.set(c.fl_variance, math.max(0, math.min(100, variance))) end
    if type(limit) == "number" then ui.set(c.fl_limit, math.max(1, math.min(15, limit))) end
end
gui.fl_ground = ui.new_combobox(TAB, "Other", "Adaptive ground fake lag", "Low choke", "Maximum")


state.cond, state.layer, state.edge, state.manual = "Standing", "normal", false, "back"
state.prev_left, state.prev_right, state.prev_fwd = false, false, false
state.fs_requested, state.fs_applied, state.fs_ready = false, false, false

function move.manual()
    local l, r, f = ui.get(gui.manual_left), ui.get(gui.manual_right), ui.get(gui.manual_fwd)
    if l and not state.prev_left then state.manual = state.manual == "left" and "back" or "left" end
    if r and not state.prev_right then state.manual = state.manual == "right" and "back" or "right" end
    if f and not state.prev_fwd then state.manual = state.manual == "forward" and "back" or "forward" end
    state.prev_left, state.prev_right, state.prev_fwd = l, r, f
end

move.state = {}

function move.reset()
    for key in pairs(move.state) do move.state[key] = nil end
end

function move.condition(me, cmd)
    local s, tick = move.state, globals.tickcount()
    local command = cmd and cmd.command_number or tick
    local movetype = entity.get_prop(me, "m_MoveType") or 2
    if s.player ~= me or s.tick and (tick < s.tick or tick - s.tick > 16) or s.command and command < s.command or movetype == 8 or movetype == 9 then
        move.reset()
    end
    if s.command == command and s.result then return s.result end
    local duck = (entity.get_prop(me, "m_flDuckAmount") or 0) == 1
    local moving = util.speed(me) > 5
    local result
    if not util.on_ground(me) then
        result = duck and "Air+" or "Air"
        s.air, s.landed = result, nil
    elseif s.air and movetype ~= 8 and movetype ~= 9 then
        s.landed = s.landed or tick
        if tick - s.landed < 2 then result = s.air else s.air, s.landed = nil, nil end
    end
    if not result then
        if duck then result = moving and "Duck move" or "Duck"
        elseif moving then result = ui.get(ref.slow_key) and "Slowwalk" or "Moving"
        else result = "Standing" end
    end
    s.player, s.command, s.tick, s.result = me, command, tick, result
    return result
end

function move.get(me, cmd)
    state.fs_requested, state.edge = false, false
    local move_cond = move.condition(me, cmd)
    state.fs_requested = state.manual == "back" and ui.get(gui.fs_key) and util.has(gui.fs_states, move_cond)
    fs.detect(me, cmd, state.fs_requested)
    if state.manual ~= "back" then return "manual", move_cond end
    state.edge = ui.get(gui.edge_key)
    if state.fs_requested and fs.peeking(me) then return "On peek", move_cond end
    if state.fs_requested and ui.get(builder.Freestanding.enabled) then return "Freestanding", move_cond end
    return move_cond, move_cond
end

function move.config(cond, move_cond)
    if cond == "manual" then return builder.Standing end
    local c = builder[cond]
    if c and (not c.enabled or ui.get(c.enabled)) then return c end
    if move_cond and move_cond ~= cond then
        local mc = builder[move_cond]
        if mc and (not mc.enabled or ui.get(mc.enabled)) then return mc end
    end
    return builder.Global
end

move.ladder_started = false

function move.ladder(cmd, me)
    if (entity.get_prop(me, "m_MoveType") or 0) ~= 9 or (cmd.forwardmove or 0) == 0 then
        move.ladder_started = false
        return
    end
    local weapon = entity.get_player_weapon(me)
    if weapon and (entity.get_prop(weapon, "m_fThrowTime") or 0) ~= 0 then return end
    if not move.ladder_started then
        move.ladder_started = true
        return
    end
    local pitch = client.camera_angles()
    local down = cmd.forwardmove < 0 or (pitch or 0) > 45
    cmd.in_moveleft, cmd.in_moveright = down and 1 or 0, down and 0 or 1
    cmd.in_forward, cmd.in_back = down and 1 or 0, down and 0 or 1
    cmd.pitch = 89
    cmd.yaw = util.normalize((cmd.move_yaw or cmd.yaw or 0) + 90)
end

function move.micro(me, cmd)
    if not me or not entity.is_alive(me) or not util.on_ground(me) then return end
    if (entity.get_prop(me, "m_MoveType") or 0) == 9 then return end
    local rules = entity.get_game_rules()
    if rules and entity.get_prop(rules, "m_bFreezePeriod") == 1 then return end
    if cmd.in_forward == 1 or cmd.in_back == 1 or cmd.in_moveleft == 1 or cmd.in_moveright == 1 then return end
    if util.speed(me) > 20 then return end
    if cmd.in_attack == 1 or cmd.in_attack2 == 1 or cmd.in_use == 1 then return end
    local amount = (entity.get_prop(me, "m_flDuckAmount") or 0) > 0 and 3.3 or 1.1
    cmd.sidemove = (cmd.command_number or 0) % 2 == 0 and amount or -amount
end


seq.sent, seq.last = 0, -1

function seq.reset()
    seq.sent, seq.last = 0, -1
end

function seq.update(cmd)
    local command = cmd.command_number or globals.tickcount()
    if (cmd.chokedcommands or 0) == 0 and command ~= seq.last then
        seq.sent, seq.last = seq.sent + 1, command
    end
end


def.version, def.keys, def.pitch5, def.yaw4 = 0, {}, {45, 0, -45}, {0, 90, 179, -90}
def.epoch, def.motions, def.spin_step = 0, {}, 6

function def.read_proc()
    local raw = tonumber(client.get_cvar("sv_maxusrcmdprocessticks"))
    def.max_proc = util.finite(raw) and raw >= 2 and math.floor(raw) - 1 or 15
end
def.read_proc()

function def.new_timing()
    return {window = false, request_until = -1, window_until = -1, exhausted = false, phase = 0, phase_tick = -1, cached_pitch_value = 0}
end

def.timing = {Gamesense = def.new_timing(), Unoins = def.new_timing(), UnoinsPro = pro.state}
def.state = {run_command_number = 0, choked = 0, lc_left = 0, active = false, last_predict_tick = -1, spatial_until = -1, request = false, peeking = false}
def.probe, def.horizons, def.boxes, def.peek_hold = {tick = -100, peek = false}, {4, 8}, {0, 4}, 7

function def.reset_timing(t, full)
    t.window, t.window_until, t.exhausted, t.phase, t.phase_tick = false, -1, false, 0, -1
    t.cached_config, t.cached_pitch_mode, t.cached_pitch_value, t.cached_yaw = nil, nil, 0, nil
    if full then t.request_until = -1 end
end

function def.reset()
    local s = def.state
    move.reset()
    s.run_command_number, s.choked, s.baseline, s.lc_left, s.active, s.last_predict_tick = 0, 0, nil, 0, false, -1
    s.origin_x, s.origin_y, s.origin_z, s.simulation_tick, s.spatial_until = nil, nil, nil, nil, -1
    s.request, s.peeking = false, false
    def.backend, def.probe.tick = nil, -100
    def.reset_timing(def.timing.Gamesense, true)
    def.reset_timing(def.timing.Unoins, true)
    pro.reset()
end

function def.reset_local(e)
    local me = entity.get_local_player()
    local idx = e and e.userid and client.userid_to_entindex(e.userid) or nil
    if not me or not idx or idx == me then def.reset() end
end

function def.run_command(c)
    if not ui.get(gui.master) then return end
    def.state.run_command_number = c.command_number or 0
    def.state.choked = c.chokedcommands or 0
end

function def.predict_command(c)
    local s = def.state
    if not ui.get(gui.master) or (c.command_number or 0) ~= s.run_command_number then return end
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then def.reset() return end
    local tickbase = entity.get_prop(me, "m_nTickBase")
    if not tickbase then return end
    if s.baseline == nil or math.abs(tickbase - s.baseline) > 64 or tickbase > s.baseline then s.baseline = tickbase end
    local cap = math.max(0, math.min(14, def.max_proc - s.choked))
    s.lc_left = math.min(cap, math.max(0, s.baseline - tickbase - 1))
    s.active = util.exploit() and s.lc_left > 0
    s.last_predict_tick = globals.tickcount()
    s.run_command_number = 0
end

function def.net_update_start()
    local live, me = util.live()
    if not live then return end
    local s = def.state
    local x, y, z = entity.get_origin(me)
    local simulation_time = entity.get_prop(me, "m_flSimulationTime")
    if not x or not simulation_time then return end
    local simulation_tick = math.floor(simulation_time / globals.tickinterval() + 0.5)
    if s.origin_x and s.simulation_tick then
        local delta = simulation_tick - s.simulation_tick
        if delta < 0 or delta > 0 and delta <= 64 then
            local dx, dy, dz = x - s.origin_x, y - s.origin_y, z - s.origin_z
            if dx * dx + dy * dy + dz * dz > 4096 then s.spatial_until = globals.tickcount() + 2 end
        end
    end
    s.origin_x, s.origin_y, s.origin_z, s.simulation_tick = x, y, z, simulation_tick
end

function def.breaking_lc()
    local s, tick = def.state, globals.tickcount()
    if s.last_predict_tick >= 0 and tick - s.last_predict_tick > 3 then s.active, s.lc_left = false, 0 end
    local exploit = util.exploit()
    local age = tick - s.last_predict_tick
    local remaining = math.max(0, s.lc_left - math.max(0, age))
    return exploit and s.active and age >= 0 and age <= 3 and remaining > 0, remaining, exploit and tick <= s.spatial_until
end

function def.exposed(me, enemy, sx, sy, sz, tx, ty, tz)
    local hit, damage = client.trace_bullet(me, sx, sy, sz, tx, ty, tz)
    return hit == enemy and util.finite(damage) and damage > 0
end

function def.peek_points(me, x, y, z)
    local vx, vy, vz = util.velocity(me)
    if vx * vx + vy * vy < 625 then return nil end
    local points, interval, air = {}, globals.tickinterval(), not util.on_ground(me)
    for _, horizon in ipairs(def.horizons) do
        local dt = math.min(horizon, pro.capacity(0)) * interval
        local px, py, pz = x + vx * dt, y + vy * dt, z + vz * dt
        if air then pz = pz - 400 * dt * dt end
        local fraction = client.trace_line(me, x, y, z, px, py, pz)
        if util.finite(fraction) then
            fraction = math.max(0, math.min(1, fraction) - 0.02)
            points[#points + 1] = {x + (px - x) * fraction, y + (py - y) * fraction, z + (pz - z) * fraction}
        end
    end
    return points
end

function def.peek_enemy(me, enemy, x, y, z, points)
    local current, future = false, false
    for _, box in ipairs(def.boxes) do
        local tx, ty, tz = entity.hitbox_position(enemy, box)
        if util.finite(tx) and util.finite(ty) and util.finite(tz) then
            current = current or def.exposed(me, enemy, x, y, z, tx, ty, tz)
            for _, p in ipairs(points) do future = future or def.exposed(me, enemy, p[1], p[2], p[3], tx, ty, tz) end
        end
    end
    return future and not current
end

function def.peeking(me)
    local probe, tick = def.probe, globals.tickcount()
    if tick >= probe.tick and tick - probe.tick < 2 then return probe.peek end
    probe.tick, probe.peek = tick, false
    local x, y, z = client.eye_position()
    if not util.finite(x) or not util.finite(y) or not util.finite(z) then return false end
    local points = def.peek_points(me, x, y, z)
    if not points then return false end
    local enemies = {}
    for _, enemy in ipairs(entity.get_players(true)) do
        local ex, ey, ez = entity.hitbox_position(enemy, 0)
        if util.finite(ex) and util.finite(ey) and util.finite(ez) then
            enemies[#enemies + 1] = {id = enemy, d = (ex - x) ^ 2 + (ey - y) ^ 2 + (ez - z) ^ 2}
        end
    end
    table.sort(enemies, util.by_distance)
    for i = 1, math.min(3, #enemies) do
        if def.peek_enemy(me, enemies[i].id, x, y, z, points) then
            probe.peek = true
            return true
        end
    end
    return false
end

function def.motion(c, kind, cmd, mode)
    local list = def.motions[c]
    if not list then
        list = {}
        def.motions[c] = list
    end
    local q = list[kind]
    if not q then
        q = {step = 0, angle = 0, speed = 0, last = -1, epoch = -1, flip = 0, start = 0}
        list[kind] = q
    end
    local fresh = q.epoch ~= def.epoch
    local speed = ui.get(kind == "pitch" and c.def_pitch_speed or c.def_yaw_speed) * def.spin_step
    if mode == "Auto Spin" then
        if fresh then q.speed = client.random_int(math.ceil(speed / 3), speed) end
        speed = q.speed
    end
    local command = cmd.command_number or globals.tickcount()
    if (cmd.chokedcommands or 0) == 0 and command ~= q.last then
        if q.last >= 0 then q.step, q.angle = q.step + 1, q.angle + speed end
        q.last = command
    end
    if fresh then q.epoch, q.flip, q.start = def.epoch, 1 - q.flip, q.step end
    return q
end

function def.jitter_first(q, delay)
    return (math.floor((q.step - q.start) / math.max(1, delay)) + q.flip) % 2 == 0
end

function def.calc_pitch(mode, c, q)
    if mode == "Off" then return nil, nil end
    if mode == "Up" then return "Up", 0 end
    if mode == "Zero" then return "Custom", 0 end
    if mode == "Down" then return "Down", 0 end
    if mode == "Custom" then return "Custom", util.clamp(ui.get(c.def_pitch_val), -89, 89) end
    if mode == "Jitter" then
        local first = def.jitter_first(q, ui.get(c.def_pitch_jdelay))
        return "Custom", util.clamp(first and ui.get(c.def_pitch_j1) or ui.get(c.def_pitch_j2), -89, 89)
    end
    if mode == "Spin" or mode == "Auto Spin" then return "Custom", q.angle % 178 - 89 end
    if mode == "Random" then
        local r1, r2 = ui.get(c.def_pitch_r1), ui.get(c.def_pitch_r2)
        return "Custom", util.clamp(client.random_int(math.min(r1, r2), math.max(r1, r2)), -89, 89)
    end
    if mode == "4Way" then
        local step = math.floor(q.step / 2) % 4
        if step == 0 then return "Down", 0 end
        if step == 2 then return "Up", 0 end
        return "Custom", 0
    end
    if mode == "5Way" then
        local step = math.floor(q.step / 2) % 5
        if step == 0 then return "Down", 0 end
        if step == 4 then return "Up", 0 end
        return "Custom", def.pitch5[step]
    end
    return nil, nil
end

function def.calc_yaw(mode, c, q)
    if mode == "Off" then return nil end
    if mode == "Custom" then return ui.get(c.def_yaw_val) end
    if mode == "Jitter" then
        return def.jitter_first(q, ui.get(c.def_yaw_jdelay)) and ui.get(c.def_yaw_j1) or ui.get(c.def_yaw_j2)
    end
    if mode == "Spin" or mode == "Auto Spin" then return (q.angle + 180) % 360 - 180 end
    if mode == "Random" then
        local r1, r2 = ui.get(c.def_yaw_r1), ui.get(c.def_yaw_r2)
        return util.normalize(client.random_int(math.min(r1, r2), math.max(r1, r2)))
    end
    if mode == "4Way" then return def.yaw4[q.step % 4 + 1] end
    if mode == "Custom Way" then
        local way = c.def_yaw_ways[q.step % util.clamp(ui.get(c.def_yaw_way_count) or 1, 1, 10) + 1]
        return util.normalize(way and ui.get(way) or 0)
    end
end

def.key_fields = {"def_pitch", "def_pitch_val", "def_pitch_j1", "def_pitch_j2", "def_pitch_jdelay", "def_pitch_speed", "def_pitch_r1", "def_pitch_r2",
    "def_yaw", "def_yaw_val", "def_yaw_j1", "def_yaw_j2", "def_yaw_jdelay", "def_yaw_speed", "def_yaw_r1", "def_yaw_r2",
    "def_yaw_way_count", "def_body_yaw", "def_body_side", "def_body_delay", "def_duration"}

function def.config_key(c)
    local cached = def.keys[c]
    if cached and cached.version == def.version then return cached.key end
    local values = {}
    for i, field in ipairs(def.key_fields) do values[i] = tostring(ui.get(c[field])) end
    for i = 1, 10 do values[#values + 1] = tostring(ui.get(c.def_yaw_ways[i])) end
    def.keys[c] = {version = def.version, key = table.concat(values, ":")}
    return def.keys[c].key
end

function def.changed()
    def.version = def.version + 1
end

function def.refresh()
    def.changed()
    menu.update()
end

function def.clear(full)
    def.reset_timing(def.timing.Gamesense, full)
    def.reset_timing(def.timing.Unoins, full)
    pro.reset()
end

function def.suppress(c, active)
    if not active or not ui.get(c.def_trigger) then return end
    aa.set(ref.aa.yaw_jitter, "Off")
    aa.set(ref.aa.yaw_jit_add, 0)
    if ui.get(c.def_body_yaw) ~= "Inherit" then
        aa.set(ref.aa.body_yaw, "Off")
        aa.set(ref.aa.body_yaw_add, 0)
    end
end

function def.body(c, phase)
    local mode = ui.get(c.def_body_yaw)
    if mode == "Inherit" then return end
    if mode == "Off" or mode == "Opposite" then
        aa.set(ref.aa.body_yaw, mode)
        aa.set(ref.aa.body_yaw_add, 0)
        return
    end
    local side = ui.get(c.def_body_side) == "-" and -1 or 1
    local delay = math.max(1, ui.get(c.def_body_delay) or 1)
    if (mode == "Jitter Pro" or delay > 1) and math.floor(phase / delay) % 2 == 1 then side = -side end
    aa.set(ref.aa.body_yaw, "Static")
    aa.set(ref.aa.body_yaw_add, side * 90)
end

function def.window(t, tick, valid, duration)
    if not valid then
        t.window, t.window_until, t.exhausted = false, -1, false
        return false, false
    end
    if t.exhausted then return false, false end
    local entered = not t.window
    if entered then t.window, t.window_until = true, tick + duration end
    if tick >= t.window_until then
        t.window, t.exhausted = false, true
        return false, false
    end
    return true, entered
end

function def.current_yaw()
    if state.fs_requested and fs.side ~= 0 then return "At targets", fs.side * 90 end
    return aa.value[ref.aa.yaw_base] or "At targets", aa.value[ref.aa.yaw_add] or 0
end

function def.set_yaw(base, yaw, mode)
    if mode == "Opposite" then
        local current
        base, current = def.current_yaw()
        yaw, def.state.opposite = current + 180, true
    elseif not yaw then
        return
    end
    aa.set(ref.aa.yaw_base, base)
    aa.set(ref.aa.yaw, "180")
    aa.set(ref.aa.yaw_add, def.final_yaw(yaw))
end

function def.final_yaw(yaw)
    aa.set(ref.aa.yaw_jitter, "Off")
    aa.set(ref.aa.yaw_jit_add, 0)
    aa.jitter_offset = 0
    return util.clamp(util.normalize(yaw), -179, 179)
end

function def.timed(backend, c, cmd, me)
    local t, s = def.timing[backend], def.state
    s.request, s.peeking = false, false
    if not c or not ui.get(c.force_def) or not util.exploit() then
        def.reset_timing(t, true)
        return false
    end
    local mode, tick = ui.get(c.def_mode), globals.tickcount()
    if mode == "On peek" then
        s.peeking = def.peeking(me)
        if s.peeking then t.request_until = tick + def.peek_hold end
    end
    local request = mode == "Always" or mode == "On peek" and tick <= t.request_until
    s.request = request
    if request then cmd.force_defensive = true end
    def.suppress(c, request)
    local active, entered = def.window(t, tick, def.breaking_lc(), math.max(1, math.min(14, ui.get(c.def_duration) or 14)))
    if not active then return false end
    if entered then
        t.cached_config, t.cached_pitch_mode, t.cached_pitch_value, t.cached_yaw = nil, nil, 0, nil
        def.epoch = def.epoch + 1
    end
    local phase_changed = t.phase_tick ~= seq.sent
    if phase_changed then
        if t.phase_tick >= 0 then t.phase = t.phase + 1 end
        t.phase_tick = seq.sent
    end
    local key = def.config_key(c)
    if phase_changed or t.cached_config ~= key then
        local dp, dy = ui.get(c.def_pitch), ui.get(c.def_yaw)
        t.cached_pitch_mode, t.cached_pitch_value, t.cached_yaw = nil, 0, nil
        if dp ~= "Off" then
            local mode_p, value = def.calc_pitch(dp, c, def.motion(c, "pitch", cmd, dp))
            t.cached_pitch_mode, t.cached_pitch_value = mode_p, value or 0
        end
        if dy ~= "Off" then
            local offset = def.calc_yaw(dy, c, def.motion(c, "yaw", cmd, dy))
            if offset then t.cached_yaw = util.normalize(offset) end
        end
        t.cached_config = key
    end
    if t.cached_pitch_mode then
        aa.set(ref.aa.pitch, t.cached_pitch_mode)
        aa.set(ref.aa.pitch_add, t.cached_pitch_value)
    end
    def.set_yaw(ui.get(c.yaw_base), t.cached_yaw, ui.get(c.def_yaw))
    def.body(c, t.phase)
    aa.set(ref.aa.fs_body, false)
    aa.set(ref.aa.edge_yaw, false)
    return true
end

function def.apply(c, cmd, me)
    local selected = ui.get(gui.backend)
    local backend = selected:find("Ünoins_qucy Pro", 1, true) and "UnoinsPro" or selected:find("Ünoins_qucy", 1, true) and "Unoins" or "Gamesense"
    if def.backend ~= backend then
        def.clear(true)
        def.backend = backend
    end
    if backend == "UnoinsPro" then return pro.apply(c, cmd, me) end
    return def.timed(backend, c, cmd, me)
end


function pro.capacity(choke)
    return util.clamp(def.max_proc - math.max(0, choke or 0), 0, 14)
end

function pro.reset()
    local s = pro.state
    for key in pairs(s) do s[key] = nil end
    s.seen, s.last_command, s.last_send = -1, -1, -1
    s.deadline, s.window_until, s.peek_until = -1, -1, -1
    s.raw_left, s.phase, s.phase_tick = 0, 0, -1
    s.window, s.episode, s.exhausted = false, false, false
end
pro.reset()

function pro.observe(tick, tickbase, command, choke)
    local s = pro.state
    if not util.finite(tick) or not util.finite(tickbase) or tickbase < 0 then
        pro.reset()
        return
    end
    if command <= s.last_command then return end
    if tick < s.seen or s.baseline and math.abs(tickbase - s.baseline) > 64 then pro.reset() end
    if not s.baseline then
        s.baseline, s.seen, s.last_command = tickbase, tick, command
        return
    end
    if s.baseline - tickbase > pro.capacity(0) + 2 then
        pro.reset()
        s.baseline, s.seen, s.last_command = tickbase, tick, command
        return
    end
    s.baseline = math.max(s.baseline, tickbase)
    s.seen, s.last_command = tick, command
    local gap_left = math.max(0, s.baseline - tickbase - 1)
    local left = math.min(pro.capacity(choke), gap_left)
    s.raw_left = left
    if gap_left <= 0 then
        s.episode, s.window, s.exhausted = false, false, false
        s.deadline, s.window_until = -1, -1
        return
    end
    if not s.episode then
        def.epoch = def.epoch + 1
        s.episode, s.exhausted = true, left <= 0
        s.started, s.deadline = tick, tick + left
        s.phase, s.last_send, s.cache = 0, -1, nil
    else
        s.deadline = math.min(s.deadline, tick + left)
    end
end

function pro.enabled()
    local me = entity.get_local_player()
    return ui.get(gui.master) and ui.get(gui.backend):find("Ünoins_qucy Pro", 1, true) ~= nil and me and entity.is_alive(me) and util.exploit(), me
end

function pro.run_command(cmd)
    if not pro.enabled() then pro.reset() return end
    local n = cmd.command_number
    if util.finite(n) and n > pro.state.last_command then
        pro.state.pending = n
        pro.state.choke = math.max(0, cmd.chokedcommands or 0)
    end
end

function pro.predict_command(cmd)
    local enabled, me = pro.enabled()
    if not enabled then pro.reset() return end
    if not pro.state.pending or cmd.command_number ~= pro.state.pending then return end
    pro.state.pending = nil
    pro.observe(globals.tickcount(), entity.get_prop(me, "m_nTickBase"), cmd.command_number, pro.state.choke)
end

function pro.blocked(cmd, me)
    if util.pressed(cmd.in_use) or util.pressed(cmd.in_attack) or util.pressed(cmd.in_attack2) or ui.get(ref.duck) then return true end
    local movetype = entity.get_prop(me, "m_MoveType")
    if movetype == 8 or movetype == 9 or bit.band(entity.get_prop(me, "m_fFlags") or 0, 64) ~= 0 then return true end
    local weapon = entity.get_player_weapon(me)
    if not weapon then return true end
    local class = entity.get_classname(weapon) or ""
    return class:find("Grenade", 1, true) or class:find("Molotov", 1, true) or class:find("Incendiary", 1, true) or class == "CC4"
        or (entity.get_prop(weapon, "m_fThrowTime") or 0) > 0
end

function pro.window(cmd, c)
    local s, tick = pro.state, globals.tickcount()
    local age = tick - s.seen
    local remaining = math.min(s.raw_left - math.max(0, age), s.deadline - tick, pro.capacity(math.max(0, cmd.chokedcommands or 0)))
    local valid = s.episode and not s.exhausted and age >= 0 and age <= 2
    local finish = math.min(s.deadline, (s.started or tick) + ui.get(c.def_duration), tick + remaining)
    if s.window then finish = math.min(finish, s.window_until) end
    if not valid or tick >= finish then
        if s.window or s.episode and (age > 2 or tick >= finish) then s.exhausted = true end
        s.window, s.window_until = false, -1
        return false
    end
    if not s.window then s.cache, s.phase, s.last_send = nil, 0, -1 end
    s.window, s.window_until = true, finish
    return true
end

function pro.request(c, cmd, me)
    local s, tick = pro.state, globals.tickcount()
    local mode = ui.get(c.def_mode)
    if mode == "On peek" then
        def.state.peeking = def.peeking(me)
        if def.state.peeking then s.peek_until = tick + def.peek_hold end
    end
    if not (mode == "Always" or mode == "On peek" and tick <= s.peek_until) or s.episode then return end
    cmd.force_defensive = true
    def.state.request = true
end

function pro.angles(c, cmd)
    local s = pro.state
    local command = cmd.command_number or globals.tickcount()
    local clean = (cmd.chokedcommands or 0) == 0
    if clean and command ~= s.last_send then
        if s.last_send >= 0 then s.phase = s.phase + 1 end
        s.last_send = command
    end
    local phase = s.phase
    local key, base = def.config_key(c), ui.get(c.yaw_base)
    if not s.cache or clean and (s.phase_tick ~= phase or s.config_key ~= key or s.cache.base ~= base) then
        local pitch_mode, yaw_mode = ui.get(c.def_pitch), ui.get(c.def_yaw)
        local cache = {base = base}
        cache.pitch_mode, cache.pitch = def.calc_pitch(pitch_mode, c, def.motion(c, "pitch", cmd, pitch_mode))
        cache.yaw = def.calc_yaw(yaw_mode, c, def.motion(c, "yaw", cmd, yaw_mode))
        if cache.yaw then cache.yaw = util.clamp(util.normalize(cache.yaw), -179, 179) end
        s.cache, s.phase_tick, s.config_key = cache, phase, key
    end
    local cache = s.cache
    if cache.pitch_mode then
        aa.set(ref.aa.pitch, cache.pitch_mode)
        aa.set(ref.aa.pitch_add, cache.pitch or 0)
    end
    def.set_yaw(cache.base, cache.yaw, ui.get(c.def_yaw))
    def.body(c, phase)
    aa.set(ref.aa.fs_body, false)
    aa.set(ref.aa.edge_yaw, false)
end

function pro.apply(c, cmd, me)
    def.state.request, def.state.peeking = false, false
    if not c or not ui.get(c.force_def) or not pro.enabled() or pro.blocked(cmd, me) then
        pro.reset()
        return false
    end
    if globals.tickcount() < pro.state.seen then pro.reset() end
    local active = pro.window(cmd, c)
    pro.request(c, cmd, me)
    if not active then return false end
    pro.angles(c, cmd)
    return true
end


fl.peek_until, fl.last = -1, {on = false, mode = "", limit = 0}

function fl.onshot()
    return util.live() and ui.get(gui.onshot) and util.hotkey(ref.os) and not util.hotkey(ref.dt) and not ui.get(ref.duck)
end

function fl.can_shoot_visible(me)
    local weapon = entity.get_player_weapon(me)
    if not weapon or not util.can_fire(me, weapon) or (entity.get_prop(weapon, "m_iClip1") or 0) <= 0 then return false end
    local threat = client.current_threat()
    if not threat or not entity.is_alive(threat) or entity.is_dormant(threat) then return false end
    local x, y, z = entity.hitbox_position(threat, 0)
    return x ~= nil and client.visible(x, y, z)
end

function fl.plan(me)
    if util.hotkey(ref.dt) then return true end
    local cap = util.clamp(def.max_proc - 1, 2, 14)
    local speed, on_ground, tick = util.speed(me), util.on_ground(me), globals.tickcount()
    if on_ground and speed <= 10 then return false end
    local need = speed > 1 and math.ceil(64 / (speed * globals.tickinterval())) or math.huge
    if on_ground and fl.can_shoot_visible(me) then
        fl.peek_until = -1
        return true, "Maximum", 2, 0
    end
    if on_ground and speed > 25 and def.peeking(me) then fl.peek_until = tick + 8 end
    if tick <= fl.peek_until then return true, "Maximum", cap, 0 end
    if need <= cap then return true, "Dynamic", math.min(cap, need + 1), 0 end
    if not on_ground then return true, "Dynamic", cap, 0 end
    if ui.get(gui.fl_ground) == "Maximum" then return true, "Maximum", cap, math.floor(util.clamp(speed / 300 * 100, 0, 100)) end
    return true, "Maximum", 3, 0
end

function fl.apply(fc)
    local mode = ui.get(fc.fakelag)
    local on, amount, limit, variance = false, nil, nil, nil
    if mode ~= "Off" then
        on = true
        local me = entity.get_local_player()
        if mode:find("Adaptive", 1, true) and me then on, amount, limit, variance = fl.plan(me) end
    end
    if fl.onshot() then on = false end
    if not amount and mode == "Always on" then
        amount, limit, variance = ui.get(fc.fl_amount), ui.get(fc.fl_limit), ui.get(fc.fl_variance)
    elseif not amount then
        amount, limit, variance = native.value("fake_amt"), native.value("fake_limit"), native.value("fake_var")
    end
    local last = fl.last
    if last.on ~= on or last.mode ~= mode or last.limit ~= limit or last.amount ~= amount or last.var ~= variance then
        last.on, last.mode, last.limit, last.amount, last.var = on, mode, limit, amount, variance
        aa.set(ref.aa.fake_enabled, on)
        if amount ~= nil then aa.set(ref.aa.fake_amt, amount) end
        if limit ~= nil then aa.set(ref.aa.fake_limit, limit) end
        if variance ~= nil then aa.set(ref.aa.fake_var, variance) end
    end
end


slow_pro.counter, slow_pro.phase, slow_pro.lift = 0, 0, 0

function slow_pro.update(cmd, me)
    local tickbase = entity.get_prop(me, "m_nTickBase")
    if not util.finite(tickbase) then return end
    local choke = cmd.chokedcommands or 0
    if (tickbase > 1 + choke or tickbase < 0) and choke == 0 then slow_pro.counter = slow_pro.counter + 1 end
end

function slow_pro.offset(c, cmd, amount)
    local mode, speed = ui.get(c.slow_pro_mode), ui.get(c.slow_pro_speed)
    if mode == "Cycle lift" then
        if (cmd.command_number or globals.tickcount()) % (ui.get(c.slow_pro_interval) * 2) == 0 then
            slow_pro.lift = slow_pro.lift + 1
            if slow_pro.lift > ui.get(c.slow_pro_max) then slow_pro.lift = ui.get(c.slow_pro_min) end
        end
        speed = slow_pro.lift
    elseif mode == "Randomize" then
        speed = client.random_int(0, speed + 1)
    end
    if (slow_pro.counter + 2) % (speed + 1) == 0 and (cmd.chokedcommands or 0) == 0 then slow_pro.phase = slow_pro.phase + 1 end
    local random = client.random_int(0, ui.get(c.slow_pro_random))
    local degree = ui.get(c.slow_pro_degree)
    local step = slow_pro.phase % 4
    local value = step < 2 and amount or amount > 0 and amount + degree + random or amount - degree - random
    return step % 2 == 0 and value or -value
end

pulse.seq, pulse.sent, pulse.none = {-1, -1, 1, -1, 1, 1}, -1, {}
pulse.mirror, pulse.shift, pulse.body_flip, pulse.brute_tick, pulse.brute_range = 1, 0, 1, -100, 36

function pulse.brute()
    local tick = globals.tickcount()
    if tick >= pulse.brute_tick and tick - pulse.brute_tick < 2 then return end
    pulse.brute_tick, pulse.mirror, pulse.body_flip, pulse.shift = tick, -pulse.mirror, -pulse.body_flip, client.random_int(0, 5)
end

function pulse.player_hurt(e)
    local me = entity.get_local_player()
    if not me or e.hitgroup ~= 1 or client.userid_to_entindex(e.userid) ~= me then return end
    local attacker = client.userid_to_entindex(e.attacker)
    if attacker and attacker ~= me and entity.is_enemy(attacker) then pulse.brute() end
end

function pulse.bullet_impact(e)
    local live, me = util.live()
    local shooter = live and client.userid_to_entindex(e.userid)
    if not shooter or shooter == me or not entity.is_enemy(shooter) then return end
    local sx, sy, sz = entity.get_origin(shooter)
    local hx, hy, hz = entity.hitbox_position(me, 0)
    if not sx or not hx or not e.x then return end
    sz = sz + (entity.get_prop(shooter, "m_vecViewOffset[2]") or 64)
    if util.segment_distance(hx, hy, hz, sx, sy, sz, e.x, e.y, e.z) <= pulse.brute_range then pulse.brute() end
end

function pulse.offset(c, amount)
    if pulse.sent == seq.sent and pulse.c == c and pulse.amount == amount then return pulse.value end
    local brute = util.has(c.pulse_extras, "Anti brute")
    local v = pulse.seq[(seq.sent + (brute and pulse.shift or 0)) % 6 + 1] * amount * (brute and pulse.mirror or 1)
    if ui.get(c.pulse_lopsided) then
        local big = math.floor(globals.realtime() / 3) % 2 == 0 and -1 or 1
        if (v >= 0 and 1 or -1) ~= big then v = v * 0.5 end
    end
    if amount ~= 0 then v = v + client.random_int(-3, 3) end
    pulse.sent, pulse.c, pulse.amount, pulse.value = seq.sent, c, amount, util.normalize(v)
    return pulse.value
end


antiaim.SLOW_PRO, antiaim.PULSE = "\aD97757FFSlow Pro\r", "\aD97757FFPulse\r"
antiaim.manual_yaw, antiaim.knife_range = {left = -90, right = 90, forward = 180}, 400 * 400

function antiaim.inverter(body, delay)
    local step = body ~= "Off" and delay > 1 and delay or 1
    return math.floor(math.max(0, seq.sent - 1) / step) % 2 == 0 and 1 or -1
end

function antiaim.apply(cond, move_cond, cmd)
    local A = ref.aa
    local c = move.config(cond, move_cond)
    aa.set(A.enabled, true)
    aa.set(A.pitch, "Minimal")
    aa.set(A.pitch_add, 0)
    aa.set(A.yaw_base, ui.get(c.yaw_base))
    local yaw_add = ui.get(c.yaw_add)
    local jitter = ui.get(c.yaw_jitter)
    local offset
    if jitter == antiaim.SLOW_PRO then
        offset = slow_pro.offset(c, cmd, cond == "manual" and 0 or ui.get(c.yaw_jit_add))
    elseif jitter == antiaim.PULSE then
        offset = pulse.offset(c, cond == "manual" and 0 or ui.get(c.yaw_jit_add))
    end
    local fs_requested = cond ~= "manual" and state.fs_requested
    local options = fs_requested and ui.get(gui.fs_options)
    local fs_no_jitter = options and util.contains(options, "Disable yaw jitter")
    local fs_no_body = options and util.contains(options, "Disable body yaw")
    state.fs_no_jitter = fs_no_jitter
    if cond == "manual" then
        yaw_add = antiaim.manual_yaw[state.manual] or yaw_add
        aa.set(A.yaw_base, "Local view")
        aa.set(A.body_yaw, "Off")
        aa.set(A.body_yaw_add, 0)
        aa.set(A.fs_body, false)
        aa.set(A.yaw_jitter, "Off")
        aa.set(A.yaw_jit_add, 0)
    else
        local body, delay = ui.get(c.body_yaw), ui.get(c.body_delay)
        local inverted = antiaim.inverter(body, delay)
        if not fs_no_jitter and ui.get(c.yaw_left_right) then
            local side = offset ~= nil and (offset >= 0 and 1 or -1) or inverted
            local spread = side == 1 and ui.get(c.left_randomization) or ui.get(c.right_randomization)
            local rand = spread > 0 and client.random_int(-spread, spread) or 0
            yaw_add = util.normalize(yaw_add + ((side == 1 and ui.get(c.left) or ui.get(c.right)) + rand))
        end
        local is_jitter, is_opposite = body:find("Jitter", 1, true) ~= nil, body:find("Opposite", 1, true) ~= nil
        if fs_no_body then
            aa.set(A.body_yaw, "Off")
            aa.set(A.body_yaw_add, 0)
        elseif body ~= "Off" and not is_opposite then
            local seed = ui.get(c.body_side) == "-" and -1 or 1
            local side = (is_jitter or delay > 1) and inverted * seed or seed
            local extras = jitter == antiaim.PULSE and ui.get(c.pulse_extras) or pulse.none
            local decouple = util.contains(extras, "Decouple body")
            if offset ~= nil and is_jitter and not decouple then side = ((fs_no_jitter and 0 or offset) >= 0 and 1 or -1) * seed end
            if decouple and util.contains(extras, "Anti brute") then side = side * pulse.body_flip end
            aa.set(A.body_yaw, "Static")
            aa.set(A.body_yaw_add, side * 90)
        else
            aa.set(A.body_yaw, is_opposite and "Opposite" or "Off")
            aa.set(A.body_yaw_add, 0)
        end
        aa.set(A.fs_body, false)
        if fs_no_jitter then
            aa.set(A.yaw_jitter, "Off")
            aa.set(A.yaw_jit_add, 0)
        elseif jitter == antiaim.SLOW_PRO or jitter == antiaim.PULSE then
            aa.set(A.yaw_jitter, "Off")
            aa.set(A.yaw_jit_add, 0)
            aa.jitter_offset = offset
            yaw_add = yaw_add + offset
        elseif jitter == "Slow" then
            aa.set(A.yaw_jitter, "Off")
            aa.set(A.yaw_jit_add, 0)
            local range = ui.get(c.yaw_jit_add)
            aa.jitter_offset = math.floor(math.max(0, seq.sent - 1) / 3) % 2 == 0 and -range or range
            yaw_add = yaw_add + aa.jitter_offset
        elseif jitter ~= "Off" then
            aa.set(A.yaw_jitter, "Center")
            aa.set(A.yaw_jit_add, ui.get(c.yaw_jit_add))
        else
            aa.set(A.yaw_jitter, "Off")
            aa.set(A.yaw_jit_add, 0)
        end
    end
    aa.set(A.yaw, "180")
    aa.set(A.yaw_add, util.normalize(yaw_add))
    aa.set(A.edge_yaw, cond ~= "manual" and state.edge)
    if fs_requested then aa.set(A.edge_yaw, false) end
    fl.apply(cond == "manual" and builder.Global or c)
    aa.set(A.roll, 0)
    return c
end

function antiaim.safe_head_selected(me)
    local weapon = entity.get_player_weapon(me)
    local class = weapon and entity.get_classname(weapon)
    if not class then return false end
    if class:find("Knife", 1, true) then return util.has(gui.safe_head, "Knife") end
    if class == "CWeaponTaser" then return util.has(gui.safe_head, "Taser") end
    if class == "CWeaponGlock" then return util.has(gui.safe_head, "Glock-18") end
    return false
end

function antiaim.lock(pitch, yaw_add)
    local A = ref.aa
    aa.set(A.pitch, pitch)
    aa.set(A.pitch_add, 0)
    aa.set(A.yaw_base, "At targets")
    aa.set(A.yaw, "180")
    aa.set(A.yaw_add, yaw_add)
    aa.set(A.yaw_jitter, "Off")
    aa.set(A.yaw_jit_add, 0)
    aa.set(A.body_yaw, "Off")
    aa.set(A.body_yaw_add, 0)
    aa.set(A.fs_body, false)
end

function antiaim.safe_head(cmd)
    cmd.force_defensive = false
    def.state.request, def.state.peeking = false, false
    def.clear(true)
    antiaim.lock("Down", 0)
end

function antiaim.backstab()
    antiaim.lock("Down", 180)
    aa.set(ref.aa.edge_yaw, false)
end

function antiaim.knife_threat(me, enemy, lx, ly, lz)
    local weapon = entity.get_player_weapon(enemy)
    if not weapon or entity.get_classname(weapon) ~= "CKnife" then return false end
    local x, y, z = entity.get_origin(enemy)
    if not x then return false end
    local dx, dy, dz = x - lx, y - ly, z - lz
    if dx * dx + dy * dy + dz * dz > antiaim.knife_range then return false end
    local hx, hy, hz = entity.hitbox_position(enemy, 4)
    local ex, ey, ez = client.eye_position()
    if not hx or not ex then return false end
    local fraction, hit = client.trace_line(enemy, hx, hy, hz, ex, ey, ez)
    return hit == me or (fraction or 0) > 0.97
end

function antiaim.backstab_threat(me)
    if not ui.get(gui.backstab) then return nil end
    local lx, ly, lz = entity.get_origin(me)
    if not lx then return nil end
    for _, enemy in ipairs(entity.get_players(true)) do
        if antiaim.knife_threat(me, enemy, lx, ly, lz) then return enemy end
    end
    return nil
end


fs.side, fs.active, fs.peek_until, fs.eye_offset, fs.tolerance = 0, false, -1, 0x78, 45

function fs.invalidate()
    state.fs_requested, state.fs_applied, state.fs_ready = false, false, false
end

function fs.native(active)
    active = active == true
    if not state.fs_ready then state.fs_ready = aa.set(ref.aa.fs_mode, "Always on") end
    if ui.get(ref.aa.freestand) ~= active then aa.set(ref.aa.freestand, active) end
    state.fs_applied = active and ui.get(ref.aa.freestand) == true
end

function fs.threat(me)
    local t = client.current_threat()
    if t and entity.is_alive(t) and not entity.is_dormant(t) then return t end
    local _, view = client.camera_angles()
    local mx, my = entity.get_origin(me)
    if not mx or not view then return end
    local best, best_d
    for _, e in ipairs(entity.get_players(true)) do
        local ex, ey = entity.get_origin(e)
        local d = ex and util.view_delta(ex, ey, mx, my, view)
        if d and (not best_d or d < best_d) then best, best_d = e, d end
    end
    return best
end

function fs.read_eye(me)
    local ptr = dormant.native and dormant.native.entity(me)
    if ptr == nil or not rh.mbi then return nil end
    local st = rh.anim_state(tonumber(ffi.cast("uintptr_t", ptr)))
    return st and rh.float(st, fs.eye_offset) or nil
end

function fs.eye_yaw(me)
    local ok, yaw = pcall(fs.read_eye, me)
    if ok and util.finite(yaw) then return yaw end
    local _, prop = entity.get_prop(me, "m_angEyeAngles")
    return util.finite(prop) and prop or nil
end

function fs.detect(me, cmd, requested)
    if not requested then
        fs.side = 0
        return
    end
    if not state.fs_applied or (cmd.chokedcommands or 0) ~= 0 then return end
    local threat, yaw = fs.threat(me), fs.eye_yaw(me)
    local mx, my = entity.get_origin(me)
    local tx, ty
    if threat then tx, ty = entity.get_origin(threat) end
    if not yaw or not mx or not tx then
        fs.side = 0
        return
    end
    local delta = util.normalize(yaw - (math.deg(math.atan2(ty - my, tx - mx)) + 180))
    if math.abs(delta - 90) <= fs.tolerance then
        fs.side = 1
    elseif math.abs(delta + 90) <= fs.tolerance then
        fs.side = -1
    else
        fs.side = 0
    end
end

function fs.peeking(me)
    if fs.side == 0 or not ui.get(builder["On peek"].enabled) then return false end
    local tick = globals.tickcount()
    if def.peeking(me) then fs.peek_until = tick + def.peek_hold end
    return tick <= fs.peek_until and tick >= fs.peek_until - def.peek_hold
end

function fs.paint()
    if fs.active and fs.side ~= 0 and util.live() then renderer.indicator(255, 255, 255, 255, "FS") end
end


hitlog.shots = {}
hitlog.groups = {[0] = "generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg", "neck", [10] = "gear"}

function hitlog.round(value)
    value = tonumber(value) or 0
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

function hitlog.backtrack(e)
    local api, tick = tonumber(e.backtrack), tonumber(e.tick)
    local delta
    if tick then
        delta = globals.tickcount() - tick
        if delta < 0 or delta > math.max(64, hitlog.round(1 / globals.tickinterval())) then delta = nil end
    end
    if delta and delta > 0 then return hitlog.round(delta) end
    if api and api > 0 then return hitlog.round(api) end
    if delta == 0 or api == 0 then return 0 end
end

function hitlog.fire(e)
    if ui.get(gui.master) and ui.get(gui.hitlog) and e.id and e.target then
        hitlog.shots[e.id] = {target = e.target, hitgroup = e.hitgroup, damage = e.damage, backtrack = hitlog.backtrack(e), hit_chance = e.hit_chance}
    end
end

function hitlog.finish(e, result)
    local shot = e.id and hitlog.shots[e.id]
    if e.id then hitlog.shots[e.id] = nil end
    if not shot or not ui.get(gui.master) or not ui.get(gui.hitlog) then return end
    if result == "Hit" then
        if e.damage ~= nil then shot.damage = e.damage end
        if e.hitgroup ~= nil then shot.hitgroup = e.hitgroup end
    end
    local name = shot.target and entity.get_player_name(shot.target)
    if not name or name == "" then name = tostring(shot.target or "unknown") end
    local group = type(shot.hitgroup) == "string" and shot.hitgroup ~= "" and shot.hitgroup:lower() or hitlog.groups[tonumber(shot.hitgroup) or 0] or "generic"
    style.log(string.format("%s %s in the %s for %d (bt:%s hc:%d)", result, name, group, hitlog.round(shot.damage),
        shot.backtrack == nil and "N/A" or tostring(shot.backtrack), hitlog.round(shot.hit_chance)))
end


rh.data, rh.shots, rh.factors, rh.enabled_last = {}, {}, {1, -1, 0.5, -0.5, 0}, false
rh.max_desync, rh.min_desync, rh.speed_loss = 58, 29, 0.116
rh.profiles, rh.osaa, rh.fired_until = {}, {}, {}
rh.deep_backtrack, rh.onshot_ticks, rh.learn_min, rh.learn_cap = 8, 10, 2, 8
rh.anim_offset = {state = 0x9960, owner = 0x60, duck = 0xA4, feet = 0xF8, stop = 0x11C, max = 0x334, size = 0x338}
rh.anim_cache = {}
do
    local ok = pcall(ffi.cdef, [[
        typedef struct { void* base; void* allocation_base; unsigned long allocation_protect; size_t region_size;
            unsigned long state; unsigned long protect; unsigned long type; } unoins_mbi;
        size_t VirtualQuery(const void* address, unoins_mbi* buffer, size_t length);
    ]])
    rh.mbi = ok and ffi.new("unoins_mbi") or nil
end
rh.no_sync = {"knife", "bayonet", "grenade", "molotov", "flashbang", "decoy", "c4"}

function rh.reset_player(idx)
    rh.data[idx] = {misses = 0, side = 1, brute_idx = 1, jitter_score = 0, jitter_sign = 1, override_active = false}
end

function rh.clear(idx)
    local d = rh.data[idx]
    if not d or not d.override_active then return true end
    d.restore_pending = true
    if d.owner ~= nil then
        local owner = entity.get_steam64(idx)
        if owner == nil then return false end
        if owner ~= d.owner then
            client.error_log("[Ünoins_qucy] Resolver restore skipped: player identity changed; new player left untouched.")
            d.override_active, d.restore_pending, d.applied_yaw = false, nil, nil
            return true
        end
    end
    plist.set(idx, "Force body yaw value", d.original_yaw)
    plist.set(idx, "Force body yaw", d.original_force)
    plist.set(idx, "Correction active", d.original_correction)
    d.applied_yaw, d.restore_pending, d.override_active = nil, nil, false
    return true
end

function rh.apply(idx, yaw)
    local d = rh.data[idx]
    if not d or d.restore_pending and not rh.clear(idx) then return false end
    yaw = math.max(-60, math.min(60, yaw or 0))
    yaw = yaw >= 0 and math.floor(yaw + 0.5) or math.ceil(yaw - 0.5)
    if d.override_active and d.applied_yaw == yaw then return true end
    if not d.override_active then
        local force, value, correction = plist.get(idx, "Force body yaw"), plist.get(idx, "Force body yaw value"), plist.get(idx, "Correction active")
        if type(force) ~= "boolean" or type(value) ~= "number" or type(correction) ~= "boolean" then return false end
        d.owner = entity.get_steam64(idx)
        d.original_force, d.original_yaw, d.original_correction = force, value, correction
    end
    d.override_active = true
    plist.set(idx, "Correction active", true)
    plist.set(idx, "Force body yaw value", yaw)
    plist.set(idx, "Force body yaw", true)
    d.applied_yaw = yaw
    return true
end

function rh.clear_all()
    for idx, d in pairs(rh.data) do
        if rh.clear(idx) then rh.data[idx] = nil else d.discard = true end
    end
    rh.shots, rh.fired_until, rh.anim_cache = {}, {}, {}
end

function rh.release_all()
    for idx in pairs(rh.data) do rh.clear(idx) end
    rh.shots, rh.fired_until, rh.anim_cache = {}, {}, {}
end

function rh.retry()
    local now = globals.realtime()
    if rh.retry_time and now >= rh.retry_time and now - rh.retry_time < 0.5 then return end
    rh.retry_time = now
    for idx, d in pairs(rh.data) do
        if d.restore_pending and rh.clear(idx) and d.discard then rh.data[idx] = nil end
    end
end

function rh.read_flags()
    local extras = ui.get(gui.resolver_extras)
    rh.learn, rh.onshot = util.contains(extras, "Learn per player"), util.contains(extras, "Onshot zero")
    rh.animstate = util.contains(extras, "Animstate (beta)")
end

function rh.float(base, offset)
    return ffi.cast("float*", base + offset)[0]
end

function rh.readable(address, size)
    local mbi = rh.mbi
    if address < 0x10000 or ffi.C.VirtualQuery(ffi.cast("const void*", address), mbi, ffi.sizeof(mbi)) == 0 then return false end
    local protect = tonumber(mbi.protect)
    return tonumber(mbi.state) == 0x1000 and bit.band(protect, 0x101) == 0 and bit.band(protect, 0xEE) ~= 0
        and address + size <= tonumber(ffi.cast("uintptr_t", mbi.base)) + tonumber(mbi.region_size)
end

function rh.anim_state(entity_address)
    local o, cached = rh.anim_offset, rh.anim_cache[entity_address]
    if cached ~= nil then return cached end
    local st = false
    if rh.readable(entity_address + o.state, 4) then
        local address = tonumber(ffi.cast("uintptr_t*", entity_address + o.state)[0])
        if address and address ~= 0 and rh.readable(address, o.size)
            and tonumber(ffi.cast("uintptr_t*", address + o.owner)[0]) == entity_address then st = address end
    end
    rh.anim_cache[entity_address] = st
    return st
end

function rh.read_anim(idx)
    local o, ptr = rh.anim_offset, dormant.native.entity(idx)
    if ptr == nil or not rh.mbi then return nil end
    local st = rh.anim_state(tonumber(ffi.cast("uintptr_t", ptr)))
    if not st then return nil end
    local duck, feet, stop, max = rh.float(st, o.duck), rh.float(st, o.feet), rh.float(st, o.stop), math.abs(rh.float(st, o.max))
    if not (util.finite(duck) and util.finite(feet) and util.finite(stop) and util.finite(max)) or max <= 0 or max > 90 then return nil end
    local speed = util.clamp(feet, 0, 1)
    local ymod = (util.clamp(stop, 0, 1) * -0.3 - 0.2) * speed + 1
    if duck > 0 then ymod = ymod + util.clamp(duck, 0, 1) * speed * (0.5 - ymod) end
    return util.clamp(ymod, 0.5, 1) * max
end

function rh.anim_cap(idx)
    if not rh.animstate or not dormant.native then return nil end
    local ok, cap = pcall(rh.read_anim, idx)
    return ok and util.finite(cap) and cap or nil
end

function rh.magnitude(idx)
    local cap = rh.anim_cap(idx)
    if cap then return cap end
    if not util.on_ground(idx) then return rh.min_desync end
    return math.max(rh.min_desync, rh.max_desync - util.speed(idx) * rh.speed_loss)
end

function rh.state_key(idx)
    if not util.on_ground(idx) then return "air" end
    if (entity.get_prop(idx, "m_flDuckAmount") or 0) >= 0.4 then return "duck" end
    return util.speed(idx) >= 10 and "move" or "stand"
end

function rh.profile(id, key)
    local list = rh.profiles[id]
    if not list then
        list = {}
        rh.profiles[id] = list
    end
    local p = list[key]
    if not p then
        p = {side = 0, hits = 0}
        list[key] = p
    end
    return p
end

function rh.hideshots(id)
    local s = rh.osaa[id]
    return s ~= nil and s.miss >= 2 and s.miss > s.hit
end

function rh.count_onshot(id, field)
    local s = rh.osaa[id] or {hit = 0, miss = 0}
    s[field] = s[field] + 1
    rh.osaa[id] = s
end

function rh.weapon_fire(e)
    local idx = client.userid_to_entindex(e.userid)
    if not idx or idx == entity.get_local_player() or not entity.is_enemy(idx) then return end
    local weapon = e.weapon or ""
    for _, name in ipairs(rh.no_sync) do
        if weapon:find(name, 1, true) then return end
    end
    rh.fired_until[idx] = globals.tickcount() + rh.onshot_ticks
end

function rh.gamesense_side(idx)
    local pose = entity.get_prop(idx, "m_flPoseParameter", 11)
    if not util.finite(pose) then return 1 end
    return pose * 120 - 60 >= 0 and 1 or -1
end

function rh.feedback(e)
    local shot = e.id and rh.shots[e.id]
    if e.id then rh.shots[e.id] = nil end
    if not shot or e.target and e.target ~= shot.target then return end
    local d, now = rh.data[shot.target], globals.realtime()
    if not d or d ~= shot.state or now - shot.time > 2 or now < shot.time then return end
    return d, shot
end

function rh.update_player(idx)
    if not rh.data[idx] then rh.reset_player(idx) end
    local d = rh.data[idx]
    local id = entity.get_steam64(idx)
    if id ~= nil then
        if d.memory_id ~= nil and d.memory_id ~= id then
            if not rh.clear(idx) then return end
            rh.reset_player(idx)
            d = rh.data[idx]
        end
        d.memory_id = id
    end
    if not entity.is_alive(idx) or entity.is_dormant(idx) then
        d.last_simtime, d.last_eye_yaw = nil, nil
        rh.clear(idx)
        return
    end
    local simtime = entity.get_prop(idx, "m_flSimulationTime")
    if simtime and d.last_simtime ~= simtime then
        local _, eye_yaw = entity.get_prop(idx, "m_angEyeAngles")
        if eye_yaw and d.last_eye_yaw and d.last_simtime and simtime > d.last_simtime then
            local delta = util.normalize(eye_yaw - d.last_eye_yaw)
            if math.abs(delta) >= 20 then
                d.jitter_score, d.jitter_sign = math.min(4, d.jitter_score + 1), delta > 0 and 1 or -1
            else
                d.jitter_score = math.max(0, d.jitter_score - 0.5)
            end
        end
        d.last_eye_yaw, d.last_simtime = eye_yaw, simtime
    end
    local id, tick = d.memory_id or idx, globals.tickcount()
    d.fired = rh.onshot and tick <= (rh.fired_until[idx] or -1) and tick >= (rh.fired_until[idx] or 0) - rh.onshot_ticks and not rh.hideshots(id)
    d.profiled = false
    if d.fired then
        rh.apply(idx, 0)
        return
    end
    if d.misses == 0 then
        local p = rh.learn and rh.profile(id, rh.state_key(idx))
        if p and p.side ~= 0 and p.hits >= rh.learn_min then
            d.profiled = true
            rh.apply(idx, p.side * rh.magnitude(idx))
        else
            rh.clear(idx)
        end
        return
    end
    rh.apply(idx, rh.factors[d.brute_idx] * d.side * (d.jitter_score >= 2 and d.jitter_sign or 1) * rh.magnitude(idx))
end

function rh.net_update_end()
    if util.live() and ui.get(gui.resolver) then
        rh.enabled_last = true
        rh.read_flags()
        local now = globals.realtime()
        for id, shot in pairs(rh.shots) do
            if now - shot.time > 2 or now < shot.time then rh.shots[id] = nil end
        end
        local seen = {}
        for _, idx in ipairs(entity.get_players(true)) do
            seen[idx] = true
            rh.update_player(idx)
        end
        for idx, d in pairs(rh.data) do
            if not seen[idx] then
                d.last_simtime, d.last_eye_yaw = nil, nil
                rh.clear(idx)
            end
        end
    elseif rh.enabled_last then
        rh.release_all()
        rh.enabled_last = false
    end
end

function rh.fire(e)
    if not ui.get(gui.master) or not ui.get(gui.resolver) or not e.id or not e.target then return end
    if not rh.data[e.target] then rh.reset_player(e.target) end
    local d = rh.data[e.target]
    rh.shots[e.id] = {target = e.target, state = d, time = globals.realtime(), overridden = d.override_active and d.applied_yaw ~= nil,
        brute_idx = d.brute_idx, gs_side = rh.gamesense_side(e.target), jitter = d.jitter_score >= 2, jitter_sign = d.jitter_sign,
        lc = e.teleported or e.extrapolated, id = d.memory_id or e.target, key = rh.state_key(e.target), yaw = d.applied_yaw,
        fired = d.fired, profiled = d.profiled, backtrack = hitlog.backtrack(e) or 0}
end

function rh.hit(e)
    if not ui.get(gui.master) or not ui.get(gui.resolver) then return end
    rh.read_flags()
    local d, shot = rh.feedback(e)
    if not d then return end
    if shot.fired then
        rh.count_onshot(shot.id, "hit")
        return
    end
    if not rh.learn then return end
    local side = shot.gs_side
    if shot.overridden then side = shot.yaw and shot.yaw ~= 0 and (shot.yaw > 0 and 1 or -1) or 0 end
    if side == 0 then return end
    local p = rh.profile(shot.id, shot.key)
    p.side, p.hits = side, math.min(rh.learn_cap, (p.side == side and p.hits or 0) + 1)
end

function rh.miss(e)
    if not ui.get(gui.master) or not ui.get(gui.resolver) then return end
    rh.read_flags()
    local d, shot = rh.feedback(e)
    if not d or e.reason ~= "?" or shot.lc or shot.backtrack > rh.deep_backtrack then return end
    if shot.fired then
        rh.count_onshot(shot.id, "miss")
        return
    end
    if shot.profiled then
        local p = rh.profile(shot.id, shot.key)
        p.hits = math.max(0, p.hits - 1)
        if p.hits == 0 then p.side = 0 end
    end
    if not shot.overridden or d.misses == 0 then
        d.side, d.brute_idx = -shot.gs_side * (shot.jitter and shot.jitter_sign or 1), 1
    else
        d.brute_idx = shot.brute_idx % #rh.factors + 1
    end
    d.misses = d.misses + 1
end

function rh.player_death(e)
    local idx = e.userid and client.userid_to_entindex(e.userid)
    if idx then rh.fired_until[idx] = nil end
    if idx and rh.data[idx] then rh.clear(idx) end
end


dormant.prev, dormant.round_start, dormant.snipers = {}, 0, {[9] = true, [40] = true, [11] = true, [38] = true}
dormant.min_alpha, dormant.duck_scale, dormant.spread_scale, dormant.stop_ratio, dormant.steady_ratio = 0.795, 2.94117647, 600, 0.33, 0.34
-- inaccuracy: C_WeaponCSBase::GetInaccuracy; some builds use 483. If shooting dormant targets crashes the game, try 483.
dormant.vtable = {entity_list = 3, inaccuracy = 482}
dormant.group_of = {[1] = 3, [64] = 4, [40] = 5, [9] = 6, [11] = 7, [38] = 7}
for group, ids in pairs({[2] = {2, 3, 4, 30, 32, 36, 61, 63}, [8] = {7, 8, 10, 13, 16, 39, 60}, [9] = {17, 19, 23, 24, 26, 33, 34}, [10] = {14, 25, 27, 28, 29, 35}}) do
    for _, id in ipairs(ids) do dormant.group_of[id] = group end
end

function util.vtable_entry(instance, index, ctype)
    return ffi.cast(ctype, ffi.cast("void***", instance)[0][index])
end

-- Binds a virtual function of an engine interface; the interface pointer is passed as `this`.
function util.vtable_bind(modules, interface, index, typestring)
    local instance
    for _, module in ipairs(modules) do
        instance = client.create_interface(module, interface)
        if instance then break end
    end
    if not instance then error("interface not found: " .. interface) end
    local fn = util.vtable_entry(instance, index, ffi.typeof(typestring))
    return function(...) return fn(instance, ...) end
end

-- Calls a virtual function on an arbitrary object pointer passed as the first argument.
function util.vtable_thunk(index, typestring)
    local ctype = ffi.typeof(typestring)
    return function(instance, ...) return util.vtable_entry(instance, index, ctype)(instance, ...) end
end

do
    local vt = dormant.vtable
    local ok, native_fn = pcall(function()
        return {
            -- client_panorama.dll was renamed to client.dll in 2021; keep the old name as a fallback.
            entity = util.vtable_bind({"client.dll", "client_panorama.dll"}, "VClientEntityList003", vt.entity_list, "void*(__thiscall*)(void*, int)"),
            inaccuracy = util.vtable_thunk(vt.inaccuracy, "float(__thiscall*)(void*)"),
        }
    end)
    dormant.native = ok and native_fn or nil
end

-- Only called with the local player's gun (dormant.command checks dormant.is_gun first),
-- so no virtual IsWeapon call is needed.
function dormant.read_inaccuracy(weapon)
    local ptr = dormant.native.entity(weapon)
    if ptr == nil then return nil end
    return dormant.native.inaccuracy(ptr)
end

-- A value outside [0, 1] means the vtable index is wrong for this build: stop using it.
function dormant.inaccuracy(weapon)
    if not dormant.native or dormant.inaccuracy_broken then return nil end
    local ok, value = pcall(dormant.read_inaccuracy, weapon)
    value = ok and tonumber(value) or nil
    if value ~= nil and not (util.finite(value) and value >= 0 and value <= 1) then
        dormant.inaccuracy_broken = true
        client.error_log("[Ünoins_qucy] Weapon inaccuracy read returned " .. tostring(value) .. "; using the movement-based fallback.")
        return nil
    end
    return value
end

function dormant.is_gun(class)
    if class == "CAK47" or class == "CDEagle" then return true end
    return class:sub(1, 7) == "CWeapon" and class ~= "CWeaponTaser" and class ~= "CWeaponShield" and class ~= "CWeaponZoneRepulsor"
end

function dormant.settings(id)
    local i = dormant.group_of[id]
    if not i or not ui.get(gui["dormant_" .. i .. "_on"]) then i = 1 end
    return ui.get(gui["dormant_" .. i .. "_dmg"]), ui.get(gui["dormant_" .. i .. "_hc"])
end

function dormant.slow(cmd, speed)
    local moving = math.sqrt(cmd.forwardmove * cmd.forwardmove + cmd.sidemove * cmd.sidemove)
    if speed <= 0 or moving <= 0 then return end
    if cmd.in_duck == 1 then speed = speed * dormant.duck_scale end
    if moving <= speed then return end
    cmd.forwardmove, cmd.sidemove = cmd.forwardmove * speed / moving, cmd.sidemove * speed / moving
end

function dormant.fire(cmd, me, weapon, id, hc_min, tx, ty, tz, ex, ey, ez)
    local scoped, on_ground = util.scoped(me), util.on_ground(me)
    local maxspeed = entity.get_prop(me, "m_flMaxspeed") or 250
    if util.has(gui.dormant_auto, "Auto stop") then dormant.slow(cmd, maxspeed * dormant.stop_ratio) end
    if dormant.snipers[id] and not scoped and on_ground and cmd.in_jump == 0 and util.has(gui.dormant_auto, "Auto scope") then cmd.in_attack2 = 1 end
    local dx, dy, dz = tx - ex, ty - ey, tz - ez
    local inaccuracy = dormant.inaccuracy(weapon)
    local steady
    if inaccuracy then
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        steady = inaccuracy <= 0 or distance <= 0 or math.min(100, dormant.spread_scale / (distance * inaccuracy)) >= hc_min
    else
        steady = on_ground and util.speed(me) <= maxspeed * dormant.steady_ratio and (scoped or not dormant.snipers[id])
    end
    if not steady or cmd.chokedcommands ~= 0 then return false end
    cmd.pitch = -math.deg(math.atan2(dz, math.sqrt(dx * dx + dy * dy)))
    cmd.yaw = math.deg(math.atan2(dy, dx))
    cmd.in_attack = 1
    return true
end

function dormant.command(cmd)
    local live, me = util.live()
    local found = {}
    dormant.prev = found
    dormant.indicator = live and ui.get(gui.dormant) and util.has(gui.dormant_auto, "Indicator")
    if not live or not ui.get(gui.dormant) then return end
    local tick = globals.tickcount()
    if tick < dormant.round_start and dormant.round_start - tick < 4096 then return end
    local weapon = entity.get_player_weapon(me)
    local class = weapon and entity.get_classname(weapon)
    if not class or not dormant.is_gun(class) or (entity.get_prop(weapon, "m_iClip1") or 0) <= 0 then return end
    local ex, ey, ez = client.eye_position()
    local resource = entity.get_player_resource()
    local can_shoot, armed = util.can_fire(me, weapon), ui.get(gui.dormant_key)
    local id = util.weapon_id(me)
    local min_dmg, hc_min = dormant.settings(id)
    for player = 1, globals.maxplayers() do
        if entity.get_prop(resource, "m_bConnected", player) == 1 and entity.get_prop(resource, "m_bAlive", player) == 1
            and entity.is_dormant(player) and entity.is_enemy(player) and not plist.get(player, "Add to whitelist") then
            local ox, oy, oz = entity.get_origin(player)
            local _, _, _, _, alpha = entity.get_bounding_box(player)
            if ox and ox ~= 0 and alpha and alpha > dormant.min_alpha then
                local tx, ty, tz = ox, oy, oz + 40 - 10 * (entity.get_prop(player, "m_flDuckAmount") or 0)
                local _, damage = client.trace_bullet(me, ex, ey, ez, tx, ty, tz, true)
                local need = min_dmg > 0 and min_dmg or math.min(tonumber(entity.get_prop(resource, "m_iHealth", player)) or 100, 50)
                local hit = (tonumber(damage) or 0) >= need and not client.visible(tx, ty, tz)
                found[player] = hit
                if hit and can_shoot and armed and dormant.fire(cmd, me, weapon, id, hc_min, tx, ty, tz, ex, ey, ez) then can_shoot = false end
            end
        end
    end
end

function dormant.round_prestart()
    dormant.round_start = globals.tickcount() + math.floor(((tonumber(cvar.mp_freezetime:get_float()) or 0) + 1) / globals.tickinterval())
end

function dormant.flag(player)
    return dormant.indicator and dormant.prev[player] == true
end

function dormant.paint()
    if not dormant.indicator or not util.live() or not ui.get(gui.dormant_key) then return end
    local r, g, b = 241, 231, 226
    for _, hit in pairs(dormant.prev) do
        if hit then
            r, g, b = style.accent()
            break
        end
    end
    renderer.indicator(r, g, b, 245, "DA")
end


qs.state, qs.names = {}, {[40] = "SSG 08", [9] = "AWP"}

function qs.knife(me)
    for _, ent in ipairs(util.weapons(me)) do
        if (entity.get_classname(ent) or ""):find("Knife", 1, true) then return ent end
    end
end

function qs.fire()
    local live, me = util.live()
    if not live or not util.has(gui.quick_switch_list, qs.names[util.weapon_id(me)] or "")
        or not (ui.get(ref.peek) and ui.get(ref.peek_key)) then return end
    qs.state = {weapon = entity.get_player_weapon(me), start = globals.tickcount(), phase = "knife"}
end

function qs.command(cmd)
    local q, me, tick = qs.state, entity.get_local_player(), globals.tickcount()
    if not q.phase then return end
    if not ui.get(gui.master) or not me or not entity.is_alive(me) or tick - q.start > 64 or tick < q.start then
        qs.state = {}
        return
    end
    if tick <= q.start then return end
    local current = entity.get_player_weapon(me)
    if q.phase == "knife" then
        local knife = qs.knife(me)
        if not knife then
            qs.state = {}
            return
        end
        if current ~= knife then
            cmd.weaponselect = knife
            return
        end
        q.phase = "back"
    end
    if current == q.weapon or entity.get_prop(q.weapon, "m_hOwnerEntity") ~= me then
        qs.state = {}
        return
    end
    cmd.weaponselect = q.weapon
end


function hc.control()
    local live, me = util.live()
    local id, weapon
    if live then id, weapon = util.weapon_id(me) end
    local tools = live and ui.get(gui.aim_tools)
    local release = tools and ui.get(gui.aim_release) and hc.release[id]
    local wanted = release and ui.get(release) >= 0 and state.cond == "Moving"
    if wanted then
        local flags, movetype = entity.get_prop(me, "m_fFlags") or 0, entity.get_prop(me, "m_MoveType")
        wanted = util.speed(me) > 5 and util.on_ground(me) and bit.band(flags, 64) == 0 and movetype ~= 8 and movetype ~= 9
            and (entity.get_prop(me, "m_flDuckAmount") or 1) ~= 1 and not ui.get(ref.slow_key) and not util.hotkey(ref.dt)
    end
    if not wanted or hc.release_weapon ~= weapon then hc.release_used = false end
    hc.release_weapon = wanted and weapon or nil
    wanted = wanted and not hc.release_used and (id == 1 or id == 64 or util.scoped(me))
    local value
    if wanted then
        value = ui.get(release)
    elseif tools and ui.get(gui.aim_noscope) and hc.noscope[id] and entity.get_prop(weapon, "m_zoomLevel") == 0 then
        value = ui.get(hc.noscope[id])
        if value == -1 then value = nil end
    end
    hc.write(hc.groups[id], value)
end

function hc.switch(name)
    return pcall(ui.set, ref.weapon_type, name) and ui.get(ref.weapon_type) == name
end

function hc.write(group, value)
    if not ref.weapon_type then return override.set("moving_hitchance", ref.hitchance, value) end
    local target = value and group and group .. ":" .. value or nil
    if target == hc.target and (target or not next(hc.saved)) then return end
    hc.target = target
    local shown = ui.get(ref.weapon_type)
    for name, saved in pairs(hc.saved) do
        if not target or name ~= group and name ~= "Global" then
            if hc.switch(name) and ui.get(ref.hitchance) == saved.written then ui.set(ref.hitchance, saved.before) end
            hc.saved[name] = nil
        end
    end
    if target then
        for _, name in ipairs({group, "Global"}) do
            if hc.switch(name) then
                local current, saved = ui.get(ref.hitchance), hc.saved[name]
                if not saved then
                    saved = {before = current}
                    hc.saved[name] = saved
                elseif current ~= saved.written then
                    saved.before = current
                end
                if current ~= value then ui.set(ref.hitchance, value) end
                saved.written = value
            end
        end
    end
    hc.switch(shown)
end


stop.boxes = {0, 4}

function stop.visible(camera_yaw)
    local ex, ey = client.eye_position()
    if not ex or not camera_yaw then return false end
    local candidates, fov = {}, ui.get(gui.stop_fov)
    for _, ent in ipairs(entity.get_players(true)) do
        local x, y = entity.hitbox_position(ent, 0)
        local delta = x and util.view_delta(x, y, ex, ey, camera_yaw)
        if delta and delta <= fov then candidates[#candidates + 1] = {ent = ent, d = delta} end
    end
    table.sort(candidates, util.by_distance)
    for i = 1, math.min(3, #candidates) do
        for _, box in ipairs(stop.boxes) do
            local x, y, z = entity.hitbox_position(candidates[i].ent, box)
            if x and client.visible(x, y, z) then return true end
        end
    end
    return false
end

function stop.command(cmd, me)
    if not ui.get(gui.aim_tools) or not ui.get(gui.aim_quickstop) or ui.is_menu_open() then return end
    local mode = ui.get(gui.quick_stop_mode)
    local flags, movetype = entity.get_prop(me, "m_fFlags") or 0, entity.get_prop(me, "m_MoveType")
    if bit.band(flags, 1) == 0 or bit.band(flags, 64) ~= 0 or movetype == 8 or movetype == 9 or util.pressed(cmd.in_jump) or util.pressed(cmd.in_use)
        or util.pressed(cmd.in_attack2) or ui.get(ref.duck) or drop.state.queue and #drop.state.queue > 0 then return end
    local weapon = entity.get_player_weapon(me)
    local class = weapon and entity.get_classname(weapon) or ""
    if not weapon or class == "CC4" or class:find("Knife", 1, true) or class == "CWeaponTaser" or drop.grenades[class] then return end
    local clip = entity.get_prop(weapon, "m_iClip1")
    if not util.finite(clip) or clip <= 0 or util.pressed(entity.get_prop(weapon, "m_bInReload")) then return end
    if not util.can_fire(me, weapon, globals.tickinterval()) then return end
    local _, camera_yaw = client.camera_angles()
    if not util.pressed(cmd.in_attack) and (mode ~= "Visible target" or not stop.visible(camera_yaw)) then return end
    local vx, vy = util.velocity(me)
    local speed = math.sqrt(vx * vx + vy * vy)
    if speed <= ui.get(gui.stop_speed) then
        cmd.forwardmove, cmd.sidemove = 0, 0
        return
    end
    local yaw = math.rad(cmd.move_yaw or cmd.yaw or camera_yaw)
    local gain = math.min(450, speed * 4) / speed
    cmd.forwardmove = (-vx * math.cos(yaw) - vy * math.sin(yaw)) * gain
    cmd.sidemove = (-vx * math.sin(yaw) + vy * math.cos(yaw)) * gain
end


override.native, override.cvars = {}, {}

function override.set(key, r, value)
    local saved = override.native[key]
    r = saved and saved.ref or r
    local current = ui.get(r)
    if value == nil then
        if saved and current == saved.written then ui.set(r, saved.before) end
        override.native[key] = nil
        return
    end
    if not saved then
        saved = {ref = r, before = current}
        override.native[key] = saved
    elseif current ~= saved.written then
        saved.before = current
    end
    if current ~= value then ui.set(r, value) end
    saved.written = value
end

function override.cvar(key, name, value)
    local saved = override.cvars[key]
    local cv = saved and saved.ref or cvar[name]
    if not cv then return end
    local current = tostring(cv:get_string())
    if value == nil then
        if saved and current == saved.written then cv:set_string(saved.before) end
        override.cvars[key] = nil
        return
    end
    if not saved then
        saved = {ref = cv, before = current}
        override.cvars[key] = saved
    elseif saved.written and current ~= saved.written then
        saved.before = current
    end
    if current ~= tostring(value) then
        if type(value) == "number" then cv:set_int(value) else cv:set_string(value) end
    end
    saved.written = tostring(cv:get_string())
end


comm.key, comm.cvars, comm.players, comm.loaded, comm.recovering = "unoins.pro.communication.v1", {}, {}, false, true
comm.names = {"cl_chatfilters", "voice_enable"}

function comm.read(name)
    local value = cvar[name]:get_string()
    return value ~= nil and tostring(value) or nil
end

function comm.write(name, value)
    cvar[name]:set_string(value)
    return comm.read(name) == value
end

function comm.warn(reason)
    if comm.warned == reason then return end
    comm.warned = reason
    client.error_log("[Ünoins_qucy] Communication: " .. reason)
end

function comm.save()
    database.write(comm.key, {version = 1, cvars = comm.cvars, players = comm.players})
end

function comm.load()
    if comm.loaded then return end
    local saved = database.read(comm.key)
    if type(saved) == "table" and saved.version == 1 then
        for _, name in ipairs(comm.names) do
            local value = type(saved.cvars) == "table" and saved.cvars[name]
            if type(value) == "string" and value:match("^%d+$") then comm.cvars[name] = value end
        end
        if type(saved.players) == "table" then
            for xuid, owned in pairs(saved.players) do
                if owned == true and type(xuid) == "string" and xuid:match("^%d+$") and xuid ~= "0" then comm.players[xuid] = true end
            end
        end
    end
    comm.loaded = true
end

function comm.bridge()
    comm.ready = false
    local me = entity.get_local_player()
    if not me or me < 1 then
        comm.panorama = nil
        return
    end
    if not comm.panorama then
        local ok, bridge = pcall(function()
            return panorama.loadstring([[
                return {
                    ready: function(me) {
                        if (!me || me < 1 || me > 64) return false;
                        var xuid = GameStateAPI.GetPlayerXuidStringFromEntIndex(me);
                        return !!xuid && xuid !== "0";
                    },
                    collect: function(me) {
                        var result = [];
                        for (var i = 1; i <= 64; i++) {
                            if (i === me) continue;
                            var xuid = GameStateAPI.GetPlayerXuidStringFromEntIndex(i);
                            if (xuid && xuid !== "0" && !GameStateAPI.IsSelectedPlayerMuted(xuid)) result.push(xuid);
                        }
                        return result.join(",");
                    },
                    set_muted: function(xuid, muted) {
                        if (GameStateAPI.IsSelectedPlayerMuted(xuid) !== muted) GameStateAPI.ToggleMute(xuid);
                        return GameStateAPI.IsSelectedPlayerMuted(xuid) === muted;
                    }
                };
            ]], "CSGOHud")()
        end)
        if ok then comm.panorama = bridge end
    end
    if not comm.panorama then return end
    local ok, ready = pcall(comm.panorama.ready, me)
    comm.ready = ok and ready == true
    if not ok then comm.panorama = nil end
    return comm.ready and comm.panorama or nil
end

function comm.restore()
    comm.load()
    local changed, pending = false, {}
    for name, value in pairs(comm.cvars) do
        local current = comm.read(name)
        if current and (current ~= "0" or comm.write(name, value)) then
            comm.cvars[name] = nil
            changed = true
        else
            pending[#pending + 1] = name .. " expected=" .. value .. " read=" .. tostring(current)
        end
    end
    if next(comm.players) then
        local bridge = comm.bridge()
        if bridge then
            for xuid in pairs(comm.players) do
                local ok, restored = pcall(bridge.set_muted, xuid, false)
                if ok and restored == true then
                    comm.players[xuid] = nil
                    changed = true
                elseif not ok then
                    comm.panorama = nil
                end
            end
        end
    end
    if changed or comm.unsaved then
        comm.save()
        comm.unsaved = nil
    end
    comm.recovering = next(comm.cvars) ~= nil or next(comm.players) ~= nil
    if comm.recovering then
        local players = 0
        for _ in pairs(comm.players) do players = players + 1 end
        if players > 0 and comm.ready then pending[#pending + 1] = "player unmutes unconfirmed=" .. players end
        table.sort(pending)
        if #pending > 0 then comm.warn("restore pending: " .. table.concat(pending, "; ") .. "; recovery records retained") else comm.warned = nil end
    else
        comm.warned = nil
    end
end

function comm.block()
    comm.load()
    if comm.recovering then
        comm.restore()
        if comm.recovering then return end
    end
    local bridge = comm.bridge()
    if not bridge then return end
    local values = {}
    for _, name in ipairs(comm.names) do
        local value = comm.read(name)
        if not value or not value:match("^%d+$") then
            comm.warn("auto mute blocked: unreadable numeric " .. name .. " (" .. tostring(value) .. ")")
            return
        end
        values[name] = value
    end
    local dirty = false
    for name, value in pairs(values) do
        if comm.cvars[name] == nil or value ~= "0" and comm.cvars[name] ~= value then
            comm.cvars[name] = value
            dirty = true
        end
    end
    local ok, players = pcall(bridge.collect, entity.get_local_player() or 0)
    if ok and type(players) == "string" then
        for xuid in players:gmatch("%d+") do
            if xuid ~= "0" and not comm.players[xuid] then
                comm.players[xuid] = true
                dirty = true
            end
        end
    elseif not ok then
        comm.panorama = nil
    end
    if dirty or comm.unsaved then
        comm.save()
        comm.unsaved = nil
    end
    for name, value in pairs(values) do
        if value ~= "0" and not comm.write(name, "0") then
            comm.warn("auto mute write unconfirmed: " .. name .. " expected=0 read=" .. tostring(comm.read(name)))
        end
    end
    for xuid in pairs(comm.players) do
        if not pcall(bridge.set_muted, xuid, true) then comm.panorama = nil end
    end
end

function comm.sync()
    if core.config_loading then return end
    if ui.get(gui.master) and ui.get(gui.mute) then comm.block() else comm.restore() end
end

function comm.tick()
    local now = globals.realtime()
    if not comm.time or now < comm.time or now - comm.time >= 0.5 then
        comm.time = now
        comm.sync()
    end
end


-- In-game language switcher: a row injected into the Panorama settings page.
-- Reloads resource/csgo_<lang>.txt through the game's ILocalize interface; the choice is saved
-- in the gamesense database and re-applied every time the script loads.
lang.db_key, lang.interval, lang.host_wait = "unoins_language", 0.25, 5
lang.by_code, lang.items, lang.status = {}, "", ""
-- Languages CS:GO ships (Steam API codes).
lang.catalog = {
    {"english", "English"}, {"schinese", "简体中文"}, {"tchinese", "繁體中文"}, {"japanese", "日本語"},
    {"koreana", "한국어"}, {"thai", "ไทย"}, {"bulgarian", "Български"}, {"czech", "Čeština"},
    {"danish", "Dansk"}, {"german", "Deutsch"}, {"spanish", "Español - España"}, {"latam", "Español - Latinoamérica"},
    {"greek", "Ελληνικά"}, {"french", "Français"}, {"italian", "Italiano"}, {"hungarian", "Magyar"},
    {"dutch", "Nederlands"}, {"norwegian", "Norsk"}, {"polish", "Polski"}, {"portuguese", "Português"},
    {"brazilian", "Português - Brasil"}, {"romanian", "Română"}, {"russian", "Русский"}, {"finnish", "Suomi"},
    {"swedish", "Svenska"}, {"turkish", "Türkçe"}, {"vietnamese", "Tiếng Việt"}, {"ukrainian", "Українська"}
}
do
    local items = {}
    for _, entry in ipairs(lang.catalog) do
        lang.by_code[entry[1]] = entry
        items[#items + 1] = entry[1] .. "=" .. entry[2]
    end
    lang.items = table.concat(items, "|")
end
-- Round-end notices: present in every csgo_<lang>.txt and translated in each.
lang.probe_tokens = {"SFUI_Notice_Terrorists_Win", "SFUI_Notice_CTs_Win", "SFUI_Notice_Target_Bombed",
    "SFUI_Notice_Bomb_Defused", "SFUI_Notice_Round_Draw"}

-- Language the game is running in, as far as the engine reports it.
function lang.detect()
    local ok, value = pcall(function() return cvar.cl_language:get_string() end)
    if ok and type(value) == "string" and lang.by_code[value:lower()] then return value:lower() end
    return "english"
end

function lang.init()
    lang.ready = true
    lang.current = lang.detect()
    lang.selected, lang.status = lang.current, "Active"
    local saved = database.read(lang.db_key)
    if type(saved) == "string" and lang.by_code[saved] then
        lang.selected = saved
        if saved ~= lang.current then lang.auto = saved end
    end
end

-- Reads a NUL-terminated UTF-16 string owned by the game; only used to compare values.
function lang.wide(ptr)
    local out = {}
    for i = 0, 511 do
        local c = ptr[i]
        if c == 0 then break end
        out[#out + 1] = c
    end
    return table.concat(out, ",")
end

-- ILocalize (localize.dll, Localize_001): IAppSystem takes indices 0-8, then AddFile 9, RemoveAll 10, Find 11.
function lang.api()
    if lang.localize ~= nil then return lang.localize or nil end
    local ok, api = pcall(function()
        local instance = client.create_interface("localize.dll", "Localize_001")
        if not instance then error("Localize_001 not found") end
        local this = ffi.cast("void*", instance)
        local vtable = ffi.cast("void***", this)[0]
        local add_file = ffi.cast("bool(__thiscall*)(void*, const char*, const char*, bool)", vtable[9])
        local remove_all = ffi.cast("void(__thiscall*)(void*)", vtable[10])
        local find = ffi.cast("const uint16_t*(__thiscall*)(void*, const char*)", vtable[11])
        return {
            add_file = function(code) return add_file(this, "resource/csgo_" .. code .. ".txt", "GAME", false) == true end,
            remove_all = function() remove_all(this) end,
            find = function(token)
                local wide = find(this, token)
                if wide == nil then return nil end
                return lang.wide(wide)
            end
        }
    end)
    if not ok then client.error_log("[Ünoins_qucy] Language switcher: " .. tostring(api)) end
    lang.localize = ok and api or false
    return lang.localize or nil
end

function lang.snapshot(api)
    local values, known = {}, 0
    for i, token in ipairs(lang.probe_tokens) do
        values[i] = api.find(token) or ""
        if values[i] ~= "" then known = known + 1 end
    end
    return table.concat(values, "|"), known
end

-- Whether AddFile replaces strings that are already loaded is detected at runtime:
-- overlay the target file; if nothing changed, add English on top. If English changes the strings,
-- files overwrite (the target was already active, so restore it); if not, the first loaded value
-- wins, so rebuild the table with the target first and English after it as the fallback.
function lang.hot_swap(code)
    local api = lang.api()
    if not api then return false, "ILocalize unavailable" end
    local before, known = lang.snapshot(api)
    if not api.add_file(code) then return false, "not installed" end
    if known == 0 then return true, "loaded, unverified" end
    local overlaid = lang.snapshot(api)
    if overlaid ~= before then return true, "overlay" end
    -- For English the probe below cannot tell the two behaviours apart, and a rebuild with
    -- only the English file is correct under either one.
    if code ~= "english" then
        api.add_file("english")
        if lang.snapshot(api) ~= overlaid then
            api.add_file(code)
            return true, "already active"
        end
    end
    api.remove_all()
    api.add_file(code)
    if code ~= "english" then api.add_file("english") end
    local rebuilt, now_known = lang.snapshot(api)
    if now_known == 0 then
        api.add_file(lang.current or "english")
        return false, "strings missing after reload"
    end
    return true, rebuilt ~= before and "rebuilt" or "already active"
end

function lang.apply(code, persist)
    local entry = lang.by_code[code]
    if not entry then return end
    local ok, swapped, detail = pcall(lang.hot_swap, code)
    if not ok then swapped, detail = false, swapped end
    if swapped then
        lang.current, lang.selected = code, code
        pcall(function() cvar.cl_language:set_string(code) end)
        if persist then database.write(lang.db_key, code) end
        lang.status = detail == "already active" and "Active" or "Applied · reopen pages to refresh"
    else
        lang.selected = lang.current
        lang.status = detail == "not installed" and entry[2] .. " is not installed" or "Switch failed"
    end
    style.log(string.format("language %s: %s", entry[2], swapped and detail or "failed (" .. tostring(detail) .. ")"))
end

lang.js = [[
    var ROW_ID = "UnoinsLanguageRow", PREFIX = "unoins_lang_";
    var HOSTS = ["JsSettings", "SettingsMenu", "Settings", "MainMenuSettings", "JsSettingsMenu"];
    var host = null, row = null, drop = null, status = null, built = "", applied = "", pending = "";
    function valid(p) { return p !== null && p !== undefined && p.IsValid(); }
    function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
    function children(p) {
        try { var c = p.Children(); if (c) return c; } catch (e) {}
        var out = [];
        try { for (var i = 0; i < p.GetChildCount(); i++) out.push(p.GetChild(i)); } catch (e) {}
        return out;
    }
    // Breadth-first walk over the main menu, at most `limit` panels.
    function walk(fn, limit) {
        var queue = [$.GetContextPanel()], seen = 0;
        while (queue.length > 0 && seen < limit) {
            var p = queue.shift();
            if (!valid(p)) continue;
            seen++;
            if (fn(p)) return p;
            var c = children(p);
            for (var i = 0; i < c.length; i++) queue.push(c[i]);
        }
        return null;
    }
    function find_host(allow_root) {
        if (valid(host)) return host;
        var root = $.GetContextPanel();
        for (var i = 0; i < HOSTS.length; i++) {
            var p = root.FindChildTraverse(HOSTS[i]);
            if (valid(p)) { host = p; return p; }
        }
        var named = walk(function (p) { return /^(js)?settings(menu)?$/i.test(p.id || ""); }, 6000);
        if (named) { host = named; return named; }
        if (allow_root) { host = root; return root; }
        return null;
    }
    function layout(items, styled) {
        var options = "", list = items.split("|");
        for (var i = 0; i < list.length; i++) {
            var pair = list[i].split("=");
            if (pair.length === 2) options += '<Label id="' + PREFIX + esc(pair[0]) + '" text="' + esc(pair[1]) + '" style="margin: 4px 12px; font-size: 18px; color: #ffffff;" />';
        }
        return '<root>' + (styled ? '<styles><include src="file://{resources}/styles/csgostyles.css" /></styles>' : '') +
            '<Panel style="horizontal-align: right; vertical-align: top; margin-top: 96px; margin-right: 48px; padding: 8px 14px; flow-children: right; background-color: #000000b0; border-radius: 3px; z-index: 50;">' +
            '<Label text="Language · 语言" style="vertical-align: center; margin-right: 12px; font-size: 18px; color: #ffffffd0;" />' +
            '<DropDown id="UnoinsLanguageDrop"' + (styled ? ' class="PopupButton" menuclass="DropDownMenu" style="width: 280px; vertical-align: center;"'
                : ' style="width: 280px; vertical-align: center; padding: 4px 8px; background-color: #262626f0;"') + '>' + options + '</DropDown>' +
            '<Label id="UnoinsLanguageStatus" text="" style="vertical-align: center; margin-left: 12px; font-size: 15px; color: #d97757;" />' +
            '</Panel></root>';
    }
    function build(parent, items) {
        var stale = parent.FindChildTraverse(ROW_ID);
        if (valid(stale)) { stale.visible = false; stale.DeleteAsync(0.0); }
        row = $.CreatePanel("Panel", parent, ROW_ID);
        var loaded = false;
        try { loaded = row.BLoadLayoutFromString(layout(items, true), false, false); } catch (e) {}
        if (!loaded) { try { loaded = row.BLoadLayoutFromString(layout(items, false), false, false); } catch (e) {} }
        if (!loaded) { row.DeleteAsync(0.0); row = null; return false; }
        drop = row.FindChildTraverse("UnoinsLanguageDrop");
        status = row.FindChildTraverse("UnoinsLanguageStatus");
        if (valid(drop)) {
            try { drop.SetPanelEvent("oninputsubmit", function () { var s = drop.GetSelected(); if (valid(s)) pending = s.id; }); } catch (e) {}
        }
        built = items; applied = ""; pending = "";
        return true;
    }
    return {
        sync: function (items, selected, text, allow_root) {
            var parent = find_host(allow_root);
            if (!parent) return "no_host";
            if (!valid(row) || built !== items) {
                if (valid(row)) row.DeleteAsync(0.0);
                if (!build(parent, items)) return "layout_failed";
            }
            if (valid(drop) && applied !== selected) { drop.SetSelected(PREFIX + selected); applied = selected; pending = ""; }
            if (valid(status) && status.text !== text) status.text = text;
            return "ok|" + (parent.id || "(no id)");
        },
        diagnose: function () {
            var root = $.GetContextPanel(), top = [], like = [];
            var c = children(root);
            for (var i = 0; i < c.length && i < 25; i++) top.push(c[i].id || "?");
            walk(function (p) {
                if (/setting/i.test(p.id || "") && like.length < 25) like.push(p.id + (p.visible ? "" : "(hidden)"));
                return false;
            }, 6000);
            return "root=" + (root.id || "?") + "; top=[" + top.join(", ") + "]; settings-like=[" + like.join(", ") + "]";
        },
        poll: function () {
            var picked = pending;
            pending = "";
            if (!picked && valid(drop)) { var s = drop.GetSelected(); if (valid(s)) picked = s.id; }
            picked = picked && picked.indexOf(PREFIX) === 0 ? picked.substr(PREFIX.length) : "";
            if (!picked || picked === applied) return "";
            applied = picked;
            return picked;
        },
        remove: function () {
            if (valid(row)) { row.visible = false; row.DeleteAsync(0.0); }
            host = row = drop = status = null;
            built = applied = pending = "";
        }
    };
]]

function lang.bridge()
    if lang.panorama then return lang.panorama end
    local ok, bridge = pcall(function() return panorama.loadstring(lang.js, "CSGOMainMenu")() end)
    if ok and bridge then
        lang.panorama = bridge
    elseif not lang.bridge_warned then
        lang.bridge_warned = true
        client.error_log("[Ünoins_qucy] Language switcher: Panorama bridge failed: " .. tostring(bridge))
    end
    return lang.panorama
end

function lang.detach()
    if lang.panorama then pcall(lang.panorama.remove) end
    lang.panorama = nil
end

function lang.tick()
    local now = globals.realtime()
    if lang.time and now >= lang.time and now - lang.time < lang.interval then return end
    lang.time = now
    if not ui.get(gui.master) then return lang.detach() end
    if not lang.ready then lang.init() end
    if lang.disabled then return end
    if lang.auto then
        local code = lang.auto
        lang.auto = nil
        lang.apply(code, false)
    end
    local bridge = lang.bridge()
    if not bridge then return end
    local ok, picked = pcall(bridge.poll)
    if ok and type(picked) == "string" and picked ~= "" and picked ~= lang.selected and lang.by_code[picked] then lang.apply(picked, true) end
    local ok_sync, result = ok, picked
    if ok then ok_sync, result = pcall(bridge.sync, lang.items, lang.selected, lang.status, lang.use_root == true) end
    if not ok_sync then
        lang.panorama = nil
        if lang.js_error ~= tostring(result) then
            lang.js_error = tostring(result)
            client.error_log("[Ünoins_qucy] Language switcher: Panorama call failed: " .. lang.js_error)
        end
        return
    end
    local outcome, where = tostring(result):match("^([^|]*)|?(.*)$")
    if outcome == "ok" then
        lang.missing_since = nil
        if lang.attached ~= where then
            lang.attached = where
            style.log("language switcher attached to Panorama panel '" .. where .. "'"
                .. (lang.use_root and " (settings panel not found: shown on the main menu instead)" or ""))
        end
        return
    end
    lang.missing_since = lang.missing_since or now
    if lang.diagnosed or outcome ~= "layout_failed" and now - lang.missing_since < lang.host_wait then return end
    lang.diagnosed = true
    local ok_info, info = pcall(bridge.diagnose)
    client.error_log("[Ünoins_qucy] Language switcher: " .. (outcome == "layout_failed" and "could not build the row" or "settings panel not found")
        .. "; " .. (ok_info and tostring(info) or "diagnose failed: " .. tostring(info)))
    if outcome == "no_host" then lang.use_root = true end
end


clan.chars, clan.idx, clan.dir, clan.timer, clan.prev_mode = {}, 1, 1, 0, "Off"
for mode, tag in pairs({["Half-life.beta"] = "Half-life.lua", ["Ünoins_qucy"] = "Ünoins_qucy", ["gamesense"] = "gamesense", ["Ideal Yaw"] = "Ideal Yaw"}) do
    local chars = {}
    for char in tag:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = char end
    clan.chars[mode] = chars
end

function clan.set(tag)
    if clan.current == (tag ~= "" and tag or nil) then return end
    client.set_clan_tag(tag)
    clan.current = tag ~= "" and tag or nil
end

function clan.reset()
    clan.idx, clan.dir, clan.timer, clan.prev_mode = 1, 1, 0, "Off"
    clan.set("")
end

function clan.net_update_start()
    if not ui.get(gui.master) then return end
    local mode = ui.get(gui.clan)
    if mode ~= clan.prev_mode then clan.idx, clan.dir, clan.timer, clan.prev_mode = 1, 1, 0, mode end
    local chars = clan.chars[mode]
    if not chars then
        clan.set("")
        return
    end
    clan.timer = clan.timer + 1
    if clan.timer < 20 then return end
    clan.timer = 0
    clan.set(table.concat(chars, "", 1, clan.idx))
    clan.idx = clan.idx + clan.dir
    if clan.idx >= #chars then clan.dir = -1 elseif clan.idx <= 1 then clan.dir = 1 end
end


perf.effects = {
    Blood = {violence_hblood = 0}, Bloom = {mat_disable_bloom = 1}, Decals = {r_drawdecals = 0},
    Shadows = {r_shadows = 0, cl_csm_static_prop_shadows = 0, cl_csm_shadows = 0},
    Ropes = {r_drawropes = 0}, Debris = {func_break_max_pieces = 0, props_break_max_pieces = 0},
    ["Weapon effects"] = {muzzleflash_light = 0, r_drawtracers_firstperson = 0}
}

function perf.console(on)
    if on and not perf.console_on then
        client.exec('con_filter_text "gamesense"; con_filter_enable 1')
        perf.console_on = true
    elseif not on and perf.console_on then
        client.exec('con_filter_enable 0; con_filter_text ""')
        perf.console_on = false
    end
end

function perf.nearest(me)
    local mx, my, mz = entity.get_origin(me)
    if not mx then return end
    local nearest, best
    for _, e in ipairs(entity.get_players(true)) do
        local ex, ey, ez = entity.get_origin(e)
        local d = ex and (ex - mx) ^ 2 + (ey - my) ^ 2 + (ez - mz) ^ 2
        if d and (not best or d < best) then nearest, best = e, d end
    end
    return nearest, best
end

function perf.resolver(me, move_cond)
    local off = false
    if me and ui.get(gui.aim_tools) and ui.get(gui.aim_resolver_off) and move_cond == "Moving" and util.weapon_id(me) == 40 and not util.scoped(me) then
        local nearest, distance = perf.nearest(me)
        off = nearest ~= nil and distance > (ui.get(gui.resolver_off_range) * 12) ^ 2 and (entity.get_prop(nearest, "m_iHealth") or 0) >= ui.get(gui.resolver_off_health)
    end
    if off then override.set("resolver", ref.resolver, false) else override.set("resolver", ref.resolver, nil) end
end


anim.pose = {}

function anim.restore()
    local me = entity.get_local_player()
    for index, saved in pairs(anim.pose) do
        if me == saved.me and entity.is_alive(me) then
            local value = entity.get_prop(me, "m_flPoseParameter", index)
            if util.finite(value) and math.abs(value - saved.written) < 0.00001 then entity.set_prop(me, "m_flPoseParameter", saved.before, index) end
        end
    end
    anim.pose = {}
end

function anim.write(me, index, value)
    local before = entity.get_prop(me, "m_flPoseParameter", index)
    if not util.finite(before) then return end
    value = math.max(0, math.min(1, value))
    entity.set_prop(me, "m_flPoseParameter", value, index)
    anim.pose[index] = {me = me, before = before, written = value}
end

function anim.enabled()
    return ui.get(gui.anim_ground_pose) ~= "Off" or ui.get(gui.anim_air_pose) ~= "Off" or ui.get(gui.anim_land)
end

function anim.frame()
    anim.restore()
    local live, me = util.live()
    if not live or not anim.enabled() then
        override.set("legs", ref.legs, nil)
        return
    end
    local ground, tick, amount = util.on_ground(me), globals.tickcount(), ui.get(gui.anim_amount) / 100
    if ground and anim.was_ground == false then anim.land_until = tick + 2 end
    anim.was_ground = ground
    if ground then
        local mode = ui.get(gui.anim_ground_pose)
        if mode == "Static" or mode == "Jitter" then
            anim.write(me, 0, mode == "Jitter" and (math.floor(tick / ui.get(gui.anim_delay)) % 2 == 0 and amount or 1 - amount) or amount)
            override.set("legs", ref.legs, "Always slide")
        elseif mode == "Moonwalk" then
            anim.write(me, 7, 0)
            override.set("legs", ref.legs, "Never slide")
        else
            override.set("legs", ref.legs, nil)
        end
        if ui.get(gui.anim_land) and anim.land_until and tick < anim.land_until then anim.write(me, 12, 0.5) end
    else
        override.set("legs", ref.legs, nil)
        local mode = ui.get(gui.anim_air_pose)
        if mode ~= "Off" then anim.write(me, 6, mode == "Cycle" and (0.5 + 0.5 * math.sin(tick * 0.35)) * amount or amount) end
    end
end


drop.state = {}
drop.grenades = {CHEGrenade = "HE", CSmokeGrenade = "Smoke", CMolotovGrenade = "Fire", CIncendiaryGrenade = "Fire", CFlashbang = "Flash", CDecoyGrenade = "Decoy"}

function drop.inventory(me)
    local result, seen, types = {}, {}, ui.get(gui.drop_types)
    for _, ent in ipairs(util.weapons(me)) do
        local kind = drop.grenades[entity.get_classname(ent) or ""]
        if kind and not seen[ent] and util.contains(types, kind) then
            result[#result + 1] = {ent = ent, kind = kind}
            seen[ent] = true
        end
    end
    return result
end

function drop.command(cmd, me)
    local active = ui.get(gui.drop) and ui.get(gui.drop_key)
    local tick, weapon = globals.tickcount(), entity.get_player_weapon(me)
    local s = drop.state
    if not active or ui.is_menu_open() or util.pressed(cmd.in_attack) or util.pressed(cmd.in_attack2) or util.pressed(cmd.in_use)
        or not weapon or (entity.get_prop(weapon, "m_fThrowTime") or 0) > 0 then
        drop.state = {held = active}
        return
    end
    if not s.held then s.queue, s.next_tick, s.started = drop.inventory(me), tick, tick end
    s.held = active
    if s.last_command == cmd.command_number then return end
    s.last_command = cmd.command_number
    if tick < (s.started or tick) or tick - (s.started or tick) > 96 then
        drop.state = {held = active}
        return
    end
    if tick < (s.next_tick or 0) or not s.queue or #s.queue == 0 then return end
    local item, owned = s.queue[1], false
    for _, entry in ipairs(drop.inventory(me)) do
        if entry.ent == item.ent and entry.kind == item.kind then owned = true end
    end
    if not owned or s.select_tick and tick - s.select_tick > 16 then
        table.remove(s.queue, 1)
        s.select_tick = nil
        return
    end
    if weapon ~= item.ent then
        cmd.weaponselect = item.ent
        s.select_tick = s.select_tick or tick
        return
    end
    client.exec("drop")
    table.remove(s.queue, 1)
    s.select_tick, s.next_tick = nil, tick + 4
end


function fd.restore()
    if not fd.saved then return end
    local _, mode, key = ui.get(ref.duck)
    if mode == 1 and key == 0 then ui.set(ref.duck, native.hotkey_modes[fd.saved.mode + 1], fd.saved.key) end
    fd.saved = nil
end

function fd.command(cmd, me)
    if not (ui.get(gui.duck_fd) and not ui.is_menu_open() and util.pressed(cmd.in_duck) and util.on_ground(me) and (entity.get_prop(me, "m_flDuckAmount") or 0) > 0.75) then
        fd.restore()
        return
    end
    if fd.saved then return end
    local active, mode, key = ui.get(ref.duck)
    if active and native.hotkey_modes[(tonumber(mode) or -1) + 1] and type(key) == "number" then
        ui.set(ref.duck, "On hotkey", 0)
        fd.saved = {mode = mode, key = key}
    end
end


tp.hidden = {}

function tp.nodraw(ent, hidden)
    local fx = entity.get_prop(ent, "m_fEffects")
    if not fx then return false end
    local has = bit.band(fx, 32) ~= 0
    if hidden and not has then
        entity.set_prop(ent, "m_fEffects", bit.bor(fx, 32))
        return true
    end
    if not hidden and has then entity.set_prop(ent, "m_fEffects", bit.band(fx, bit.bnot(32))) end
    return false
end

function tp.restore()
    for ent in pairs(tp.hidden) do tp.nodraw(ent, false) end
    tp.hidden = {}
end

function tp.thirdperson(me)
    local cx, cy, cz = client.camera_position()
    local ex, ey, ez = client.eye_position()
    local dx, dy, dz = cx - ex, cy - ey, cz - ez
    return math.sqrt(dx * dx + dy * dy + dz * dz) > 5
end

function tp.update()
    local me = entity.get_local_player()
    local weapon = me and ui.get(gui.master) and ui.get(gui.hide_weapon) and entity.is_alive(me) and tp.thirdperson(me) and entity.get_player_weapon(me)
    if not weapon or weapon == 0 then
        if next(tp.hidden) then tp.restore() end
        return
    end
    local world = entity.get_prop(weapon, "m_hWeaponWorldModel")
    for ent, parent in pairs(tp.hidden) do
        if ent ~= weapon and ent ~= world then
            if parent == ent and entity.get_prop(ent, "m_hOwnerEntity") ~= me then tp.nodraw(ent, false) end
            tp.hidden[ent] = nil
        end
    end
    if tp.nodraw(weapon, true) then tp.hidden[weapon] = weapon end
    if world and world > 0 and tp.nodraw(world, true) then tp.hidden[world] = weapon end
end


scope.alpha = 0
scope.widths = {Thin = 1, Regular = 2, Bold = 3}
scope.arms = {{"Top", 0, -1}, {"Bottom", 0, 1}, {"Left", -1, 0}, {"Right", 1, 0}}

function scope.state()
    local live, me = util.live()
    if not live or not ui.get(gui.scope) or not util.scoped(me) then return false, false end
    local weapon = entity.get_player_weapon(me)
    if not weapon or weapon == 0 then return false, false end
    local zoom = entity.get_prop(weapon, "m_zoomLevel")
    return true, util.finite(zoom) and zoom > 0 and not util.pressed(entity.get_prop(me, "m_bResumeZoom"))
end

function scope.control(phase)
    local owned, active = scope.state()
    local value
    if owned then value = phase ~= "paint" end
    override.set("scope", ref.scope, value)
    return active
end

function scope.paint()
    local active = scope.control("paint")
    if not util.live() or not ui.get(gui.scope) then
        scope.alpha = 0
        return
    end
    scope.alpha = scope.alpha + ((active and 1 or 0) - scope.alpha) * (1 - math.exp(-util.frame_dt() * 16))
    local alpha = scope.alpha
    if alpha < 0.01 then return end
    local sw, sh = client.screen_size()
    local x, y = math.floor(sw / 2), math.floor(sh / 2)
    local r, g, b, a = ui.get(gui.scope_color)
    local gap, length, width = ui.get(gui.scope_gap), ui.get(gui.scope_length), scope.widths[ui.get(gui.scope_thickness)] or 1
    local style_name, hidden = ui.get(gui.scope_style), ui.get(gui.scope_exclude)
    if style_name ~= "Diagonal" then
        local fa = math.floor(a * alpha)
        local fade = style_name == "Soft" and 0 or fa
        local o = math.floor((width - 1) / 2)
        for _, arm in ipairs(scope.arms) do
            if not util.contains(hidden, arm[1]) then
                local dx, dy = arm[2], arm[3]
                if dx == 0 then
                    renderer.gradient(x - o, dy < 0 and y - gap - length or y + gap + 1, width, length, r, g, b, dy > 0 and fa or fade, r, g, b, dy > 0 and fade or fa, false)
                else
                    renderer.gradient(dx < 0 and x - gap - length or x + gap + 1, y - o, length, width, r, g, b, dx > 0 and fa or fade, r, g, b, dx > 0 and fade or fa, true)
                end
            end
        end
        return
    end
    local fa, reach = math.floor(a * alpha * (width == 1 and 0.6 or 1)), gap + length
    for _, arm in ipairs(scope.arms) do
        if not util.contains(hidden, arm[1]) then
            local dx, dy = (arm[2] - arm[3]) * 0.7071, (arm[2] + arm[3]) * 0.7071
            for w = 0, width - 1 do
                local offset = w - (width - 1) / 2
                local ox, oy = -dy * offset, dx * offset
                renderer.line(x + dx * gap + ox, y + dy * gap + oy, x + dx * reach + ox, y + dy * reach + oy, r, g, b, fa)
            end
        end
    end
end


hud.state = {}

function hud.paint()
    local live, me = util.live()
    local now, dt = globals.realtime(), util.frame_dt()
    if not ui.get(gui.master) then
        hud.state, hud.preview, hud.visual = {}, nil, nil
        return
    end
    if not ui.get(gui.velocity) then
        hud.state, hud.preview = {}, nil
        hud.fade(now)
        return
    end
    local value = live and entity.get_prop(me, "m_flVelocityModifier")
    local valid = util.finite(value) and value >= 0 and value <= 1
    if not valid then hud.state = {} end
    local s = hud.state
    if s.time and now < s.time then
        hud.state = {}
        s = hud.state
    end
    local visible = false
    if valid then
        if value < 0.995 and not s.slow then s.pulse = now end
        if value >= 0.995 and s.slow then s.recovered = now end
        if s.raw and value < s.raw - 0.025 then s.pulse = now end
        s.slow, s.raw, s.time = value < 0.995, value, now
        visible = s.slow or s.recovered and now - s.recovered < 0.55
        s.alpha = (s.alpha or 0) + ((visible and 1 or 0) - (s.alpha or 0)) * (1 - math.exp(-dt * (visible and 13 or 8)))
        s.display = (s.display or value) + (value - (s.display or value)) * (1 - math.exp(-dt * 11))
    end
    if ui.is_menu_open() and not visible then
        local visual = hud.visual
        local preview = hud.preview or {alpha = visual and visual.fade_start and visual.alpha or 1, display = 1}
        hud.preview = preview
        local elapsed = preview.start and now - preview.start
        if elapsed and elapsed < 0 then preview.start, elapsed = nil, nil end
        local t = elapsed and math.min(1, elapsed / 0.75) or 1
        preview.display = t * t * (3 - 2 * t)
        preview.alpha = preview.alpha + (1 - preview.alpha) * (1 - math.exp(-dt * 16))
        hud.draw(preview.display, preview, now, true)
        return
    end
    hud.preview = nil
    if valid and s.alpha >= 0.01 then
        hud.draw(value, s, now, false)
    elseif hud.visual and hud.visual.preview then
        hud.fade(now)
    else
        hud.visual = nil
    end
end

function hud.fade(now)
    local visual = hud.visual
    if not visual then return end
    if not visual.fade_start then visual.fade_start, visual.fade_alpha = now, visual.alpha end
    local t = (now - visual.fade_start) / 0.30
    if t < 0 or t >= 1 then
        hud.visual = nil
        return
    end
    visual.alpha = visual.fade_alpha * (1 - t * t * (3 - 2 * t))
    hud.draw(visual.value, visual, now, visual.preview, true)
end

function hud.rect(x, y, w, h, r, g, b, a)
    renderer.rectangle(x, y, w, h, r, g, b, math.floor(a * hud.alpha))
end

function hud.line(x1, y1, x2, y2, r, g, b, a)
    renderer.line(x1, y1, x2, y2, r, g, b, math.floor(a * hud.alpha))
end

function hud.draw(value, s, now, preview, fading)
    if not fading then
        local visual = hud.visual or {}
        visual.value, visual.display, visual.alpha = value, s.display, s.alpha
        visual.pulse, visual.slow, visual.preview = s.pulse, s.slow, preview
        visual.fade_start, visual.fade_alpha = nil, nil
        hud.visual = visual
    end
    local sw, sh = client.screen_size()
    local w, h = 190, 49
    local x = math.max(4, math.min(sw - w - 4, sw * 0.5 - w / 2))
    local y = math.max(4, math.min(sh - h - 4, sh * 0.32 - h / 2)) - (1 - s.alpha) * 8
    local cr, cg, cb, ca = style.accent()
    local recovered = value >= 0.995
    if recovered then cr, cg, cb = 242, 198, 180 end
    hud.alpha = s.alpha
    local rect, line = hud.rect, hud.line
    rect(x - 2, y - 2, w + 4, h + 4, 0, 0, 0, 35)
    rect(x, y, w, h, 20, 18, 17, 222)
    rect(x, y, 2, h, cr, cg, cb, ca)
    line(x + 2, y, x + w, y, 51, 48, 46, 140)
    local cx, cy = x + 26, y + 23
    local pulse = s.pulse and math.max(0, 1 - (now - s.pulse) / 0.65) or 0
    local progress = math.max(0, math.min(1, s.display))
    for i = 0, 39 do
        local layer = i % 2
        local angle = (now * (layer == 0 and 0.16 or -0.12) + math.floor(i / 2) / 20 + layer * 0.025) * math.pi * 2
        local shimmer = 0.5 + 0.5 * math.sin(now * 3.2 + i * 1.7)
        local radius = 15.6 + layer * 2.6 + math.sin(now * 2 + i) * 0.35 + pulse * 0.55
        local size = math.max(1, 1.05 + shimmer * 0.25 + pulse * 0.2)
        local px, py = cx + math.cos(angle) * radius, cy + math.sin(angle) * radius
        local halo = size + 1.6
        renderer.rectangle(px - halo / 2, py - halo / 2, halo, halo, cr, cg, cb, math.floor(ca * s.alpha * (0.06 + shimmer * 0.08)))
        renderer.rectangle(px - size / 2, py - size / 2, size, size, cr, cg, cb, math.floor(ca * s.alpha * (0.36 + shimmer * 0.44)))
    end
    for i = 0, 23 do
        local a1, a2 = math.rad(135 + i * 270 / 24 + 1.5), math.rad(135 + (i + 1) * 270 / 24 - 1.5)
        local active = i / 24 < progress
        local radius = 13 + (active and pulse * 0.9 or 0)
        line(cx + math.cos(a1) * radius, cy + math.sin(a1) * radius, cx + math.cos(a2) * radius, cy + math.sin(a2) * radius,
            active and cr or 64, active and cg or 56, active and cb or 52, active and ca or 150)
    end
    local angle = math.rad(135 + 270 * progress)
    line(cx, cy, cx + math.cos(angle) * 9, cy + math.sin(angle) * 9, cr, cg, cb, ca)
    rect(cx - 1, cy - 1, 2, 2, 241, 231, 226, ca)
    for i = 0, 2 do
        local shift = (now * 30 + i * 7) % 21
        line(cx - 7 - shift, cy + 17 + i * 2, cx - 2 - shift, cy + 17 + i * 2, cr, cg, cb, (1 - shift / 21) * pulse * 90)
    end
    local tx = x + 49
    renderer.text(tx, y + 8, cr, cg, cb, math.floor(ca * s.alpha), "b", 0, preview and "PREVIEW" or recovered and "RECOVERED" or "MOMENTUM")
    renderer.text(x + w - 10, y + 8, 241, 231, 226, math.floor(ca * s.alpha), "r", 0, string.format("%d%%", math.floor(value * 100 + 0.5)))
    renderer.text(tx, y + 23, 141, 133, 128, math.floor(210 * s.alpha), "-", 0, preview and "Animation preview" or recovered and "Movement restored" or "Movement slowed")
    local bw = w - 61
    rect(tx, y + h - 8, bw, 2, 46, 40, 37, 190)
    rect(tx, y + h - 8, bw * progress, 2, cr, cg, cb, ca)
    if s.slow or preview then
        local light = (now * 0.7) % 1 * bw * progress
        rect(tx + light, y + h - 8, math.min(10, math.max(0, bw * progress - light)), 2, 241, 231, 226, 65)
    end
end

function hud.changed()
    local enabled = ui.get(gui.velocity)
    if enabled and not hud.enabled and ui.get(gui.master) then
        local visual = hud.visual
        hud.state = {}
        hud.preview = {start = globals.realtime(), alpha = visual and visual.fade_start and visual.alpha or 1, display = 0}
    elseif not enabled and hud.enabled then
        local visual = hud.visual
        if visual and not visual.fade_start then visual.fade_start, visual.fade_alpha = globals.realtime(), visual.alpha end
    end
    hud.enabled = enabled
    core.changed()
end


ind.dt_state, ind.dt_until, ind.dt_was = "off", 0, false
ind.manual_dir = {left = "< LEFT", right = "RIGHT >", forward = "^ FORWARD"}
ind.qucy, ind.flag_keys, ind.title = {alpha = 0, channels = {}, data = {flags = {}}}, {"DT", "HS", "FS", "FD"}, {}
for ch in ("ÜNOINS_QUCY"):gmatch("[%z\1-\127\194-\244][\128-\191]*") do ind.title[#ind.title + 1] = ch end

function ind.body_side()
    local me = entity.get_local_player()
    local pose = me and entity.get_prop(me, "m_flPoseParameter", 11)
    if not pose then return "R" end
    local d = pose * 120 - 60
    return d > 25 and "R" or d < -25 and "L" or "B"
end

function ind.damage()
    if not util.has(gui.ind_extras, "Damage") then return end
    local dmg
    if ui.get(ref.md[2]) then dmg = ui.get(ref.md[3]) end
    return tostring(dmg or ui.get(ref.mindmg[1]))
end

function ind.segment(x, y, text, r, g, b, a)
    renderer.text(x, y, r, g, b, a, "-", 0, text)
    return x + renderer.measure_text("-", text) + 1.2
end

function ind.paint()
    if not util.live() then return end
    local sw, sh = client.screen_size()
    local dmg = ind.damage()
    if dmg then renderer.text(sw / 2 + 10, sh / 2 - 17, style.text[1], style.text[2], style.text[3], 255, "b", 0, dmg) end
    local now = globals.realtime()
    local dt = util.hotkey(ref.dt)
    if dt ~= ind.dt_was then
        ind.dt_state, ind.dt_until = "lc", now + 0.25
    elseif ind.dt_state == "lc" and now >= ind.dt_until then
        ind.dt_state = dt and "active" or "off"
    end
    ind.dt_was = dt
    local mode = ui.get(gui.indicator)
    if mode == "Half-life" then
        local t = (math.sin(now * 2.5) + 1) * 0.5
        local dr, dg, db, da = 255, 255, 255, 80
        if ind.dt_state == "active" then dr, dg, db, da = 110, 200, 70, 255 elseif ind.dt_state == "lc" then dr, dg, db, da = 255, 0, 0, 255 end
        local _, lh = renderer.measure_text("-", "X")
        local x, y, seg = sw * 0.5, sh * 0.52, ind.segment
        seg(seg(x, y, "HALF-LIFE", 255, 255, 255, 255), y, " BETA", math.floor(130 + t * 100), math.floor(100 + t * 80), math.floor(70 + t * 70), 255)
        y = y + lh + 1.2
        seg(seg(x, y, "BODY YAW: ", 255, 255, 255, 255), y, ind.body_side(), 255, 255, 255, 255)
        y = y + lh + 1.2
        seg(x, y, "DT", dr, dg, db, da)
        y = y + lh + 1.2
        local bx = seg(x, y, "BAIM", 255, 255, 255, util.hotkey(ref.baim) and 255 or 80)
        seg(seg(bx, y, " MD", 255, 255, 255, util.hotkey(ref.md) and 255 or 80), y, " OS", 255, 255, 255, util.hotkey(ref.os) and 255 or 80)
    elseif mode == "Ideal yaw" then
        local cx, cy = sw / 2, sh / 2
        renderer.text(cx, cy + 40, 215, 114, 44, 255, "", 0, "IDEAL YAW")
        renderer.text(cx, cy + 50, 199, 132, 216, 255, "", 0, "DYNAMIC")
        if ind.dt_state == "active" then renderer.text(cx, cy + 60, 10, 245, 5, 255, "", 0, "DT")
        elseif ind.dt_state == "lc" then renderer.text(cx, cy + 60, 245, 10, 5, 255, "", 0, "DT") end
    end
end

function ind.read(d, me)
    local f = d.flags
    d.tone = nil
    if not me then
        d.label, f.DT, f.HS, f.FS, f.FD = "MENU", false, false, false, false
        return
    end
    f.DT, f.HS, f.FD = util.hotkey(ref.dt), util.hotkey(ref.os), ui.get(ref.duck) == true
    f.FS = fs.active == true or state.fs_applied == true and ui.get(gui.fs_key) == true and ui.get(ref.aa.freestand) == true
    if not entity.is_alive(me) then
        d.label, d.tone = "DEAD", "dim"
    elseif state.layer == "safety" then
        d.label, d.tone = "KNIFE SAFE", "alert"
    elseif state.cond == "manual" then
        d.label = (ind.manual_dir[state.manual] or "MANUAL"):upper()
    elseif state.layer == "safe_head" then
        d.label = "SAFE HEAD"
    elseif state.layer == "request" and def.state.peeking then
        d.label = "PEEK"
    else
        d.label = tostring(state.cond):upper()
        if state.edge and state.layer == "normal" then d.label = d.label .. " EDGE" end
    end
end

function ind.alpha(a)
    return math.floor(util.clamp(a * ind.fade * ind.ca / 255, 0, 255) + 0.5)
end

function ind.text(x, y, r, g, b, a, label, flags)
    renderer.text(x + 1, y + 1, 0, 0, 0, ind.alpha(a * 0.85), flags or "", 0, label)
    renderer.text(x, y, r, g, b, ind.alpha(a), flags or "", 0, label)
end

function ind.pill(x, y, w, h, r, g, b, a)
    local alpha = ind.alpha(a)
    renderer.rectangle(x + 1, y, w - 2, h, r, g, b, alpha)
    renderer.rectangle(x, y + 1, 1, h - 2, r, g, b, alpha)
    renderer.rectangle(x + w - 1, y + 1, 1, h - 2, r, g, b, alpha)
end

function ind.shine(pos, sweep)
    return math.max(0, 1 - math.abs(pos - sweep) / 1.4)
end

function ind.line_alpha(pos, sweep)
    return ind.alpha(90 + 165 * ind.shine(pos, sweep))
end

function ind.width(label, flags)
    return renderer.measure_text(flags or "", label) or #label * 7
end

function ind.draw(data, s, now, style_name)
    local sw, sh = client.screen_size()
    local cr, cg, cb, ca = ui.get(gui.qucy_color)
    local text, w = ind.text, ind.width
    ind.fade, ind.ca = s.alpha, ca
    local _, fh = renderer.measure_text("", "X")
    fh = fh or 13
    local tx, ty = 14, math.floor(sh / 2 - 20)
    if style_name == "new" then
        tx = math.floor(util.clamp(sw / 2 + 6, 4, sw - 130))
        ty = math.floor(util.clamp(sh / 2 + ui.get(gui.qucy_offset), 4, sh - 50))
    end
    if style_name == "new" or util.has(gui.ind_extras, "Group name") then
        local px, ly, title = tx, ty + fh + 1, ind.title
        local sweep = (now * 0.3 % 1) * (#title + 4) - 2
        for i, ch in ipairs(title) do
            local cw, shine = w(ch, "b"), ind.shine(i, sweep)
            local half = math.floor(cw / 2)
            local a0, a1, a2 = ind.line_alpha(i - 0.5, sweep), ind.line_alpha(i, sweep), ind.line_alpha(i + 0.5, sweep)
            text(px, ty, 241, 231, 226, 255, ch, "b")
            if shine > 0.03 then renderer.text(px, ty, cr, cg, cb, ind.alpha(shine * 255), "b", 0, ch) end
            renderer.gradient(px, ly, half, 1, cr, cg, cb, a0, cr, cg, cb, a1, true)
            renderer.gradient(px + half, ly, cw - half, 1, cr, cg, cb, a1, cr, cg, cb, a2, true)
            px = px + cw
        end
    else
        ty = ty - fh - 2
    end
    local py = ty + fh + 5
    if style_name ~= "new" then
        ind.grid(s, tx, py, fh, cr, cg, cb)
        return
    end
    local lr, lg, lb = cr, cg, cb
    if data.tone == "alert" then lr, lg, lb = 232, 93, 70 elseif data.tone == "dim" then lr, lg, lb = 141, 133, 128 end
    ind.pill(tx, py, w(data.label) + 10, fh + 2, lr, lg, lb, 51)
    text(tx + 5, py + 1, lr, lg, lb, 255, data.label)
    local fx, fy = tx, py + fh + 6
    for _, key in ipairs(ind.flag_keys) do
        local on = s.channels[key] or 0
        local dot_r, dot_g, dot_b = math.floor(110 + (cr - 110) * on), math.floor(103 + (cg - 103) * on), math.floor(99 + (cb - 99) * on)
        renderer.rectangle(fx, fy + math.floor((fh - 5) / 2), 5, 5, dot_r, dot_g, dot_b, ind.alpha(153 + 102 * on))
        text(fx + 8, fy, math.floor(141 + 100 * on), math.floor(133 + 98 * on), math.floor(128 + 98 * on), 190 + 65 * on, key)
        fx = fx + w(key) + 16
    end
end

function ind.grid(s, tx, py, fh, cr, cg, cb)
    local text, w = ind.text, ind.width
    local me = entity.get_local_player()
    local hour, minute = client.system_time()
    local ping = me and math.floor((client.latency() or 0) * 1000 + 0.5)
    local grid = {
        {"FPS", s.fps and tostring(math.floor(s.fps + 0.5)) or "--", "PING", ping and (ping .. "ms") or "--"},
        {"TICK", tostring(math.floor(1 / globals.tickinterval() + 0.5)), "CHOKE", me and tostring(globals.chokedcommands() or 0) or "--"},
        {"TIME", string.format("%02d:%02d", hour or 0, minute or 0), "JITTER", me and s.jitter and (math.floor(s.jitter + 0.5) .. "ms") or "--"},
    }
    local pad, gap, row_h = 7, 16, fh + 3
    local lab1, lab2, val1, val2 = 0, 0, w("0000"), w("0000")
    for _, row in ipairs(grid) do
        lab1, lab2 = math.max(lab1, w(row[1])), math.max(lab2, w(row[3]))
        val1, val2 = math.max(val1, w(row[2])), math.max(val2, w(row[4]))
    end
    local col1, col2 = lab1 + 8 + val1, lab2 + 8 + val2
    local user = menu.player_name()
    local bw = math.max(pad * 2 + col1 + gap + col2, pad * 2 + w("USER") + 8 + w(user))
    local bh = pad + row_h + 5 + row_h * #grid + pad - 3
    renderer.rectangle(tx + 1, py + 1, bw, bh, 0, 0, 0, ind.alpha(90))
    ind.pill(tx, py, bw, bh, 20, 18, 17, 228)
    renderer.rectangle(tx + 1, py, bw - 2, 1, cr, cg, cb, ind.alpha(230))
    local y = py + pad - 2
    text(tx + pad, y, cr, cg, cb, 220, "USER")
    text(tx + bw - pad - w(user), y, 241, 231, 226, 255, user)
    y = y + row_h + 1
    renderer.rectangle(tx + pad, y, bw - pad * 2, 1, 51, 48, 46, ind.alpha(255))
    y = y + 4
    local x2 = tx + pad + col1 + gap
    renderer.rectangle(x2 - math.floor(gap / 2), y, 1, row_h * #grid - 3, 51, 48, 46, ind.alpha(255))
    for _, row in ipairs(grid) do
        text(tx + pad, y, cr, cg, cb, 220, row[1])
        text(tx + pad + col1 - w(row[2]), y, 241, 231, 226, 255, row[2])
        text(x2, y, cr, cg, cb, 220, row[3])
        text(x2 + col2 - w(row[4]), y, 241, 231, 226, 255, row[4])
        y = y + row_h
    end
end

function ind.qucy_paint()
    local s = ind.qucy
    local now = globals.realtime()
    local dt = util.clamp(s.time and now - s.time or globals.frametime(), 0, 0.1)
    s.time = now
    local me = entity.get_local_player()
    local sel = ui.get(gui.indicator)
    local style_name = sel == "Ünoins_qucy new" and "new" or sel == "Ünoins_qucy" and "side" or nil
    local wanted = ui.get(gui.master) and style_name ~= nil and (me ~= nil or ui.is_menu_open())
    local step = 1 - math.exp(-dt * 14)
    s.alpha = s.alpha + ((wanted and 1 or 0) - s.alpha) * step
    if not wanted and s.alpha < 0.003 then
        s.alpha, s.shown = 0, false
        return
    end
    if wanted then
        ind.read(s.data, me)
        s.style, s.shown = style_name, true
    end
    if not s.shown then return end
    local frame = globals.absoluteframetime()
    if frame and frame > 0 then s.fps = s.fps and s.fps + (1 / frame - s.fps) * math.min(1, dt * 4) or 1 / frame end
    local latency = (client.latency() or 0) * 1000
    if s.last_latency then s.jitter = (s.jitter or 0) + (math.abs(latency - s.last_latency) - (s.jitter or 0)) * math.min(1, dt * 2) end
    s.last_latency = latency
    for _, key in ipairs(ind.flag_keys) do
        local value = s.channels[key] or 0
        s.channels[key] = value + ((s.data.flags[key] and 1 or 0) - value) * step
    end
    ind.draw(s.data, s, now, s.style)
end


octo.x, octo.face, octo.px, octo.py, octo.pk = 0, 1, {}, {}, {}
octo.ARM = {down = {{-1, 0}, {0, 0}, {-1, 1}, {0, 1}}, out = {{-2, 0}, {-1, 0}, {0, 0}, {-2, -1}}, up = {{0, 0}, {-1, -1}, {0, -1}, {-1, -2}, {-1, -3}}, tuck = {}}
octo.LEGS = {
    stand = {{4, 2}, {6, 2}, {11, 2}, {13, 2}}, walkA = {{4, 1}, {6, 2}, {11, 1}, {13, 2}}, walkB = {{4, 2}, {6, 1}, {11, 2}, {13, 1}},
    swingA = {{4, 3}, {6, 2}, {11, 2}, {13, 3}}, swingB = {{4, 2}, {6, 3}, {11, 3}, {13, 2}}, splay = {{3, 1}, {5, 1}, {12, 1}, {14, 1}}, none = {}
}
octo.FX = {
    q = {{0, 0}, {1, 0}, {2, 0}, {2, 1}, {1, 2}, {2, 2}, {1, 4}},
    spark = {{0, 0}, {-1, 0}, {1, 0}, {0, -1}, {0, 1}},
    z = {{0, 0}, {1, 0}, {2, 0}, {1, 1}, {0, 2}, {1, 2}, {2, 2}}
}
octo.CHEER_SPOTS, octo.EYES = {{-3, -3}, {20, -2}, {17, -6}}, {5, 12}

function octo.play(name, duration)
    octo.ev = {n = name, t0 = globals.realtime(), d = duration}
end

function octo.base()
    return {h = 8, y = 0, eye = "open", dx = 0, aL = "down", aR = "down", legs = "stand", fx = {}}
end

function octo.preset(name, t)
    local p = octo.base()
    if name == "walk" then
        p.legs, p.dx = math.floor(t * 8) % 2 == 1 and "walkA" or "walkB", octo.face
    elseif name == "sleep" then
        p.h, p.eye, p.legs, p.aL, p.aR = 6, "blink", "splay", "tuck", "tuck"
        local k = t * 0.8 % 3
        p.fx[1] = {"z", 16 + math.floor(k), -4 - math.floor(k * 2)}
    elseif name == "look" then
        p.dx = math.floor(t * 1.6) % 2 == 1 and 1 or -1
        p.legs = math.floor(t * 1.5) % 2 == 1 and "swingA" or "swingB"
    elseif name == "yawn" then
        p.h, p.aL, p.aR, p.eye = 9, "up", "up", "blink"
    else
        p.legs = math.floor(t * 1.5) % 2 == 1 and "swingA" or "swingB"
        if t % 3.7 < 0.13 then p.eye = "blink" end
        if t % 2.4 > 1.9 then p.aL, p.aR = "out", "out" end
    end
    return p
end

function octo.event_pose(t)
    local e = octo.ev
    if not e then return end
    local u = (t - e.t0) / e.d
    if u < 0 or u >= 1 then
        octo.ev = nil
        return
    end
    local p = octo.base()
    if e.n == "wave" or e.n == "goodbye" then
        p.aR = math.floor(t * 5.5) % 2 == 1 and "up" or "out"
        p.eye = e.n == "goodbye" and u > 0.6 and "blink" or "happy"
    elseif e.n == "cheer" or e.n == "kill" then
        p.y = u < 0.45 and -2 or u < 0.65 and -1 or 0
        p.aL, p.aR, p.eye = "up", "up", "happy"
        for i = 1, e.n == "kill" and 3 or 2 do
            if math.floor(t * 8 + i) % 2 == 1 then p.fx[#p.fx + 1] = {"spark", octo.CHEER_SPOTS[i][1], octo.CHEER_SPOTS[i][2]} end
        end
    elseif e.n == "confused" then
        p.fx[1] = {"q", 15, -7}
        p.dx = math.floor(t * 2.5) % 2 == 1 and 1 or -1
    end
    return p
end

function octo.update(dt, t, idle_for, dead)
    if dead then
        local p = octo.base()
        p.h, p.y, p.eye, p.legs, p.dim = 6, 1, "x", "splay", true
        return p
    end
    local e = octo.event_pose(t)
    if e then return e end
    if idle_for >= 30 then return octo.preset("sleep", t) end
    local i = octo.idle_state
    if not i or t >= i.stop then
        local r = client.random_float(0, 1)
        if r < 0.45 then i = {n = "stand", stop = t + client.random_float(2, 4)}
        elseif r < 0.75 then i = {n = "walk", x = client.random_int(-90, 30), stop = t + 10}
        elseif r < 0.92 then i = {n = "look", stop = t + 2}
        else i = {n = "yawn", stop = t + 1.4} end
        octo.idle_state = i
    end
    if i.n == "walk" then
        if math.abs(i.x - octo.x) < 0.6 then
            octo.idle_state = {n = "stand", stop = t + client.random_float(1.5, 3)}
            return octo.preset("stand", t)
        end
        octo.face = i.x > octo.x and 1 or -1
        octo.x = octo.x + octo.face * 14 * dt
        return octo.preset("walk", t)
    end
    return octo.preset(i.n, t)
end

function octo.put(x, y, k)
    local n = octo.n + 1
    octo.n, octo.px[n], octo.py[n], octo.pk[n] = n, x, y + octo.dy, k
end

function octo.build(p)
    local put = octo.put
    octo.n, octo.dy = 0, p.y
    local top = 8 - p.h
    local er = top + math.floor(p.h / 4)
    for y = top, 7 do for x = 3, 14 do put(x, y, 1) end end
    for _, cx in ipairs(octo.EYES) do
        local e, d = p.eye, p.dx
        if e == "open" then put(cx + d, er, 2); put(cx + d, er + 1, 2)
        elseif e == "blink" then put(cx + d, er + 1, 2)
        elseif e == "happy" then put(cx - 1, er + 1, 2); put(cx, er, 2); put(cx + 1, er + 1, 2)
        elseif e == "x" then put(cx - 1, er, 2); put(cx + 1, er, 2); put(cx, er + 1, 2); put(cx - 1, er + 2, 2); put(cx + 1, er + 2, 2) end
    end
    for _, o in ipairs(octo.ARM[p.aL]) do put(2 + o[1], 4 + o[2], 1) end
    for _, o in ipairs(octo.ARM[p.aR]) do put(15 - o[1], 4 + o[2], 1) end
    for _, leg in ipairs(octo.LEGS[p.legs]) do
        for i = 0, leg[2] - 1 do put(leg[1], 8 + i, 1) end
    end
    for _, f in ipairs(p.fx) do
        for _, o in ipairs(octo.FX[f[1]]) do put(f[2] + o[1], f[3] + o[2], 3) end
    end
    return octo.n
end

function octo.draw(ox, oy, p, cr, cg, cb, a)
    local n = octo.build(p)
    local X, Y, K = octo.px, octo.py, octo.pk
    for i = 1, n do
        if K[i] ~= 2 then renderer.rectangle(ox + X[i] * 2 + 1, oy + Y[i] * 2 + 1, 2, 2, 0, 0, 0, math.floor(140 * a)) end
    end
    for i = 1, n do
        local k, r, g, b = K[i], cr, cg, cb
        if k == 2 then r, g, b = 22, 22, 24
        elseif k == 3 then r, g, b = 245, 245, 240
        elseif p.dim then r, g, b = cr * 0.45 + 40, cg * 0.45 + 40, cb * 0.45 + 40 end
        renderer.rectangle(ox + X[i] * 2, oy + Y[i] * 2, 2, 2, r, g, b, math.floor(255 * a))
    end
end

function octo.player_death(e)
    local me = entity.get_local_player()
    if me and client.userid_to_entindex(e.attacker) == me and client.userid_to_entindex(e.userid) ~= me then octo.play("kill", 1.5) end
end


menu.loaded_at, menu.icons = globals.realtime(), {}
menu.icon_svg = {
    Home = '<path d="M3 8 8 3.5 13 8M4.5 7v6h7V7" fill="none" stroke="#fff" stroke-width="1.5"/>',
    Builder = '<path d="M3 4h10M3 8h10M3 12h10" stroke="#fff" stroke-width="1.4"/><circle cx="6" cy="4" r="1.7" fill="#fff"/>'
        .. '<circle cx="10" cy="8" r="1.7" fill="#fff"/><circle cx="5" cy="12" r="1.7" fill="#fff"/>',
    Defensive = '<path d="M8 2.5 13 4.5v3.5c0 3-2.2 5-5 6-2.8-1-5-3-5-6V4.5z" fill="none" stroke="#fff" stroke-width="1.5"/>'
        .. '<path d="M8 2.5v11.5" stroke="#fff" stroke-width="1.5"/>',
    Binds = '<rect x="2" y="4.5" width="12" height="7.5" rx="1" fill="none" stroke="#fff" stroke-width="1.5"/>'
        .. '<path d="M4.5 7h1M7.5 7h1M10.5 7h1M5 9.6h6" stroke="#fff" stroke-width="1.5"/>',
    Rage = '<circle cx="8" cy="8" r="4.5" fill="none" stroke="#fff" stroke-width="1.5"/><path d="M8 1.5v3M8 11.5v3M1.5 8h3M11.5 8h3" stroke="#fff" stroke-width="1.5"/>',
    World = '<circle cx="8" cy="8" r="5.5" fill="none" stroke="#fff" stroke-width="1.5"/>'
        .. '<path d="M2.5 8h11M8 2.5c-2.4 3-2.4 8 0 11M8 2.5c2.4 3 2.4 8 0 11" fill="none" stroke="#fff" stroke-width="1.2"/>',
    Visuals = '<path d="M1.5 8s2.5-4.5 6.5-4.5S14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8z" fill="none" stroke="#fff" stroke-width="1.5"/>'
        .. '<circle cx="8" cy="8" r="2" fill="#fff"/>'
}

function menu.icon(name)
    if not menu.icons[name] then
        local svg = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">' .. menu.icon_svg[name] .. '</svg>'
        menu.icons[name] = renderer.load_svg(svg, 16, 16)
    end
    return menu.icons[name]
end

function menu.player_name()
    if menu.name == nil then
        local ok, name = pcall(function() return panorama.open().MyPersonaAPI.GetName() end)
        menu.name = ok and type(name) == "string" and name ~= "" and name or false
    end
    return menu.name or "player"
end

function menu.clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 3600 then return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60) end
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

function menu.update_labels(now)
    if ui.get(gui.page) ~= "Home" or menu.labels_at and now - menu.labels_at < 1 and now >= menu.labels_at then return end
    menu.labels_at = now
    local me = entity.get_local_player()
    for _, item in ipairs({
        {gui.welcome, "\aD97757FFWelcome back, " .. menu.player_name()},
        {gui.session[1], "Loaded  " .. menu.clock(now - menu.loaded_at)},
        {gui.session[2], "Ping  " .. (me and (math.floor((client.latency() or 0) * 1000 + 0.5) .. " ms") or "--")},
        {gui.session[3], "Map  " .. (me and globals.mapname() or "--")}
    }) do
        ui.set(item[1], item[2])
        ui.set_visible(item[1], true)
    end
end

function menu.track_tab(mx, my, cx, cy)
    local s = (tonumber(ui.get(ref.dpi):match("%d+") or "") or 100) / 100
    if cx < mx + 5 or cx > mx + 6 + 75 * s then return end
    local i = math.floor((cy - my - 19) / (64 * s + 1))
    if i >= 0 and i < 8 then menu.gs_tab = i end
end

function menu.paint()
    local now = globals.realtime()
    local dt = util.clamp(menu.t and now - menu.t or 0, 0, 0.1)
    menu.t = now
    local mouse_down = client.key_state(0x01)
    local clicked = mouse_down and not menu.mouse_down
    menu.mouse_down = mouse_down
    if not ui.is_menu_open() or not ui.get(gui.master) then return end
    menu.update_labels(now)
    local mx, my = ui.menu_position()
    local mw = ui.menu_size()
    local ar, ag, ab = style.accent()
    local cx, cy = ui.mouse_position()
    if cx ~= menu.cx or cy ~= menu.cy or mouse_down then menu.cx, menu.cy, menu.active_at = cx, cy, now end
    if clicked then menu.track_tab(mx, my, cx, cy) end
    local banner = ui.get(gui.banner) and (menu.gs_tab or 1) == 1
    local bh = 44
    local by = my - bh
    local top = banner and by or my
    if cx >= mx - 4 and cx <= mx + mw + 4 and cy >= top - 26 and cy <= my + 2 then menu.block_until = now + 0.15 end
    if banner then
        renderer.gradient(mx, by, mw, bh, 30, 25, 23, 255, 20, 18, 17, 255, false)
        renderer.rectangle(mx, by, mw, 1, 51, 48, 46, 255)
        renderer.rectangle(mx, by, 1, bh, 51, 48, 46, 255)
        renderer.rectangle(mx + mw - 1, by, 1, bh, 51, 48, 46, 255)
        local half = math.floor((mw - 20) / 2)
        renderer.gradient(mx + 10, by + bh - 1, half, 1, ar, ag, ab, 0, ar, ag, ab, 255, true)
        renderer.gradient(mx + 10 + half, by + bh - 1, half, 1, ar, ag, ab, 255, ar, ag, ab, 0, true)
        local lw = renderer.measure_text("b", "ÜNOINS") or 44
        renderer.text(mx + 14, by + 9, 241, 231, 226, 255, "b", 0, "ÜNOINS")
        renderer.text(mx + 14 + lw, by + 9, ar, ag, ab, 255, "b", 0, "_QUCY")
        renderer.text(mx + 14, by + 24, 141, 133, 128, 255, nil, 0, "v" .. style.version .. " · " .. menu.player_name() .. " · " .. menu.clock(now - menu.loaded_at))
        local current = ui.get(gui.page)
        local x = mx + mw - 10
        for i = #menu.tabs, 1, -1 do
            local name = menu.tabs[i]
            local active = name == current
            local tw = active and (renderer.measure_text(nil, name) or 30) + 34 or 28
            x = x - tw
            local tx, ty = x, by + 8
            local hover = cx >= tx and cx <= tx + tw and cy >= ty and cy <= ty + 28
            if active then
                renderer.rectangle(tx, ty, tw, 28, ar, ag, ab, 33)
                renderer.rectangle(tx, ty, tw, 1, ar, ag, ab, 90)
                renderer.rectangle(tx, ty + 27, tw, 1, ar, ag, ab, 90)
            elseif hover then
                renderer.rectangle(tx, ty, tw, 28, 241, 231, 226, 10)
            end
            local r, g, b = 125, 125, 125
            if active then r, g, b = 242, 198, 180 elseif hover then r, g, b = 220, 212, 207 end
            renderer.texture(menu.icon(name), tx + 6, ty + 6, 16, 16, r, g, b, 255, "f")
            if active then renderer.text(tx + 26, ty + 8, r, g, b, 255, nil, 0, name) end
            if clicked and hover and not active then
                ui.set(gui.page, name)
                menu.update()
            end
            x = x - 3
        end
    end
    if ui.get(gui.pet) then
        local me = entity.get_local_player()
        local p = octo.update(dt, now, now - (menu.active_at or now), me ~= nil and not entity.is_alive(me))
        local anchor = mx + mw - 150
        octo.x = math.max(mx + 10 - anchor, math.min(mx + mw - 46 - anchor, octo.x))
        octo.draw(anchor + math.floor(octo.x / 2 + 0.5) * 2, top - 16, p, ar, ag, ab, 1)
    end
    local in_server = entity.get_local_player() ~= nil
    if menu.in_server ~= nil and menu.in_server ~= in_server then octo.play(in_server and "wave" or "goodbye", in_server and 1.8 or 2) end
    menu.in_server = in_server
end

function menu.block_input(cmd)
    if ui.is_menu_open() and globals.realtime() < (menu.block_until or 0) then cmd.in_attack, cmd.in_attack2 = 0, 0 end
end


function core.cleanup()
    hc.write(nil, nil)
    perf.console(false)
    anim.restore()
    fd.restore()
    for key in pairs(override.cvars) do override.cvar(key, nil, nil) end
    for key in pairs(override.native) do override.set(key, nil, nil) end
    drop.state, hud.state, hud.preview, hud.visual = {}, {}, nil, nil
    scope.alpha, anim.was_ground, anim.land_until = 0, nil, nil
    fl.last.on = nil
end

function core.sync()
    if core.config_loading then return end
    hc.control()
    local live = util.live()
    local wanted = {}
    if live then
        for _, group in ipairs(ui.get(gui.fps_effects)) do
            for name, value in pairs(perf.effects[group] or {}) do
                wanted["fps:" .. name] = true
                override.cvar("fps:" .. name, name, value)
            end
        end
    end
    for key in pairs(override.cvars) do
        if key:sub(1, 4) == "fps:" and not wanted[key] then override.cvar(key, nil, nil) end
    end
    perf.console(live and ui.get(gui.console))
    if not live or not ui.get(gui.aim_tools) or not ui.get(gui.aim_resolver_off) then override.set("resolver", ref.resolver, nil) end
    if ui.get(gui.master) and ui.get(gui.dormant) and util.has(gui.dormant_auto, "Dormant ESP") then
        override.set("dormant_esp", ref.dormant_esp, true)
    else
        override.set("dormant_esp", ref.dormant_esp, nil)
    end
    if not live or not ui.get(gui.duck_fd) then fd.restore() end
    if not live or not ui.get(gui.drop) then drop.state = {} end
    if not live or not anim.enabled() then
        anim.restore()
        override.set("legs", ref.legs, nil)
        anim.was_ground, anim.land_until = nil, nil
    end
    if not live or not ui.get(gui.scope) then
        override.set("scope", ref.scope, nil)
        scope.alpha = 0
    end
    if not live or not ui.get(gui.velocity) then hud.state = {} end
    if not ui.get(gui.master) or not ui.get(gui.velocity) then hud.preview = nil end
end

function core.changed()
    if core.config_loading then return end
    fl.last.on = nil
    core.sync()
    scope.control()
    menu.update()
end

function core.paint_ui()
    local now = globals.realtime()
    if not core.sync_time or now < core.sync_time or now - core.sync_time >= 0.25 then
        core.sync_time = now
        core.sync()
    end
    scope.control("paint_ui")
    hud.paint()
end

function core.idle(layer)
    state.layer, fs.side, fs.active = layer, 0, false
    hc.write(nil, nil)
    override.set("resolver", ref.resolver, nil)
end

function core.command(cmd)
    aa.cancel()
    if not ui.get(gui.master) then return core.idle("disabled") end
    native.capture()
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then
        if rh.enabled_last then
            rh.clear_all()
            rh.enabled_last = false
        end
        state.fs_requested, fs.side, fs.active = false, 0, false
        fs.native(false)
        def.reset()
        return core.idle("dead")
    end
    fd.command(cmd, me)
    drop.command(cmd, me)
    if ui.get(gui.fast_ladder) then move.ladder(cmd, me) end
    def.state.choked = cmd.chokedcommands or 0
    move.manual()
    local move_cond
    state.cond, move_cond = move.get(me, cmd)
    hc.control()
    perf.resolver(me, move_cond)
    seq.update(cmd)
    slow_pro.update(cmd, me)
    aa.begin(state.cond == "manual" and 70 or state.fs_requested and 85 or 10)
    local c = antiaim.apply(state.cond, move_cond, cmd)
    fs.active = state.fs_requested and state.cond ~= "manual"
    def.state.opposite = false
    local safe_head = move_cond == "Air+" and antiaim.safe_head_selected(me)
    local threat = state.cond ~= "manual" and antiaim.backstab_threat(me)
    if threat then
        def.state.request = false
        def.clear(true)
        aa.owner(100)
        antiaim.backstab()
        state.layer = "safety"
    elseif safe_head then
        aa.owner(90)
        antiaim.safe_head(cmd)
        state.layer = "safe_head"
    elseif state.cond == "manual" then
        def.state.request, def.state.peeking = false, false
        def.clear(true)
        state.layer = "manual"
    else
        aa.owner(88)
        if def.apply(c, cmd, me) then
            state.layer = "defensive"
        elseif state.fs_requested then
            state.layer = "freestand"
        elseif def.state.request then
            state.layer = "request"
        else
            state.layer = "normal"
        end
    end
    aa.commit()
    fs.native(state.fs_requested and state.cond ~= "manual" and state.layer ~= "safety" and not def.state.opposite)
    move.micro(me, cmd)
    stop.command(cmd, me)
end

function core.reset_master()
    tp.restore()
    rh.clear_all()
    rh.enabled_last = false
    seq.reset()
    def.reset()
    fl.last.on, fl.last.mode, fl.last.limit = false, "", 0
    state.layer = "disabled"
    clan.reset()
end

function core.shutdown()
    core.cleanup()
    tp.restore()
    hitlog.shots = {}
    rh.clear_all()
    native.reset()
    fs.invalidate()
    seq.reset()
    def.reset()
    native.visible(true)
    clan.set("")
end

function core.player_death(e)
    if client.userid_to_entindex(e.userid) == entity.get_local_player() then core.cleanup() end
end


config.limit, config.prefix, config.items = 1048576, "Ünoins_qucy~", {}
config.b64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
config.b64_bytes, config.b64_values = {}, {}
for i = 1, #config.b64_chars do
    local byte = config.b64_chars:byte(i)
    config.b64_bytes[i - 1], config.b64_values[byte] = byte, i - 1
end

function config.reg(key, r, kind)
    config.items[#config.items + 1] = {key = key, ref = r, kind = kind}
end

for _, item in ipairs({
    {"defensive_backend", gui.backend}, {"safe_head_weapons", gui.safe_head}, {"freestanding_states", gui.fs_states}, {"freestanding_options", gui.fs_options},
    {"anti_backstab", gui.backstab}, {"fl_ground_mode", gui.fl_ground}, {"hide_vm_tp", gui.hide_weapon}, {"indicator_sel", gui.indicator},
    {"clan_tag_sel", gui.clan}, {"rh_enabled", gui.resolver},
    {"hitlog_enabled", gui.hitlog}, {"fast_ladder", gui.fast_ladder}, {"menu_pet", gui.pet}, {"menu_banner", gui.banner}, {"auto_mute_all", gui.mute}
}) do
    config.reg(item[1], item[2])
end
for _, c in ipairs(menu.controls) do
    if c.kind ~= "label" then config.reg("extra_" .. c.key, c.ref, c.kind) end
end
config.cond_fields = {"yaw_base", "yaw_add", "yaw_left_right", "left", {"left_rand", "left_randomization"}, "right", {"right_rand", "right_randomization"},
    "yaw_jitter", "yaw_jit_add", "pulse_lopsided", "pulse_extras", "slow_pro_degree", "slow_pro_random", "slow_pro_speed", "slow_pro_mode", "slow_pro_min", "slow_pro_max",
    "slow_pro_interval", "body_yaw", "body_side", "body_delay", "force_def", "def_mode", "def_trigger", "def_duration", "def_pitch", "def_pitch_val",
    "def_pitch_j1", "def_pitch_j2", "def_pitch_jdelay", "def_pitch_speed", "def_pitch_r1", "def_pitch_r2", "def_yaw",
    "def_yaw_val", "def_yaw_j1", "def_yaw_j2", "def_yaw_jdelay", "def_yaw_speed", "def_yaw_r1", "def_yaw_r2", "def_yaw_way_count"}
for _, cond in ipairs(conditions) do
    local c = builder[cond]
    if c.enabled then config.reg(cond .. "_enabled", c.enabled) end
    for _, field in ipairs(config.cond_fields) do
        if type(field) == "table" then config.reg(cond .. "_" .. field[1], c[field[2]]) else config.reg(cond .. "_" .. field, c[field]) end
    end
    for i = 1, 10 do config.reg(cond .. "_def_yaw_way_" .. i, c.def_yaw_ways[i]) end
    for _, field in ipairs({"def_body_yaw", "def_body_side", "def_body_delay", "fakelag", "fl_amount", "fl_variance", "fl_limit"}) do config.reg(cond .. "_" .. field, c[field]) end
end

function config.b64_encode(data)
    local result = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local word = bit.lshift(a, 16) + bit.lshift(b or 0, 8) + (c or 0)
        result[#result + 1] = string.char(config.b64_bytes[bit.rshift(word, 18)], config.b64_bytes[bit.band(bit.rshift(word, 12), 63)],
            b and config.b64_bytes[bit.band(bit.rshift(word, 6), 63)] or 61, c and config.b64_bytes[bit.band(word, 63)] or 61)
    end
    return table.concat(result)
end

function config.b64_decode(data)
    local result, buffer, bits = {}, 0, 0
    for i = 1, #data do
        local value = config.b64_values[data:byte(i)]
        if value then
            buffer, bits = bit.lshift(buffer, 6) + value, bits + 6
            if bits >= 8 then
                bits = bits - 8
                result[#result + 1] = string.char(bit.band(bit.rshift(buffer, bits), 255))
                buffer = bit.band(buffer, bit.lshift(1, bits) - 1)
            end
        end
    end
    return table.concat(result)
end

function config.u32(value)
    return string.char(bit.band(value, 255), bit.band(bit.rshift(value, 8), 255), bit.band(bit.rshift(value, 16), 255), bit.rshift(value, 24))
end

function config.read_u32(data, offset)
    local a, b, c, d = data:byte(offset, offset + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

function config.checksum(data)
    local a, b = 1, 0
    for i = 1, #data do
        a = (a + data:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

function config.compress(data)
    local output, heads, previous = {}, {}, {}
    local size, pos, literal, work = #data, 1, 1, 0
    local function insert(index)
        if index + 2 > size then return end
        local key = data:sub(index, index + 2)
        previous[index], heads[key] = heads[key], index
    end
    local function flush(finish)
        while literal <= finish do
            local count = math.min(128, finish - literal + 1)
            output[#output + 1] = string.char(count - 1) .. data:sub(literal, literal + count - 1)
            literal = literal + count
        end
    end
    while pos <= size do
        local candidate = pos + 2 <= size and heads[data:sub(pos, pos + 2)]
        local length, distance, tries = 0, 0, 0
        local maximum = math.min(130, size - pos + 1)
        while candidate and pos - candidate <= 65535 and tries < 32 do
            local matched = 3
            while matched < maximum and data:byte(candidate + matched) == data:byte(pos + matched) do
                matched, work = matched + 1, work + 1
                if work > size * 32 then return nil end
            end
            if matched > length then length, distance = matched, pos - candidate end
            if length == maximum then break end
            candidate, tries = previous[candidate], tries + 1
        end
        if length >= 4 then
            flush(pos - 1)
            output[#output + 1] = string.char(128 + length - 3, bit.band(distance, 255), bit.rshift(distance, 8))
            for i = pos, pos + length - 1 do insert(i) end
            pos = pos + length
            literal = pos
        else
            insert(pos)
            pos = pos + 1
            if pos - literal == 128 then flush(pos - 1) end
        end
    end
    flush(size)
    return table.concat(output)
end

function config.decompress(data, size)
    local output, pos, count = {}, 1, 0
    while pos <= #data do
        local control = data:byte(pos)
        pos = pos + 1
        if control < 128 then
            local length = control + 1
            if pos + length - 1 > #data or count + length > size then return nil end
            for i = pos, pos + length - 1 do
                count = count + 1
                output[count] = data:sub(i, i)
            end
            pos = pos + length
        else
            if pos + 1 > #data then return nil end
            local length, distance = control - 125, data:byte(pos) + data:byte(pos + 1) * 256
            if distance < 1 or distance > count or count + length > size then return nil end
            for _ = 1, length do
                count = count + 1
                output[count] = output[count - distance]
            end
            pos = pos + 2
        end
    end
    if count ~= size then return nil end
    return table.concat(output)
end

function config.encode(str)
    assert(#str <= config.limit, "config: serialized data exceeds 1 MiB")
    local packed = #str >= 32 and config.compress(str)
    local compressed = packed and #packed < #str
    return config.prefix .. config.b64_encode(config.u32(#str + (compressed and 0 or 2147483648)) .. config.u32(config.checksum(str)) .. (compressed and packed or str))
end

function config.decode(str)
    if type(str) ~= "string" or #str > config.limit * 2 or str:sub(1, #config.prefix) ~= config.prefix then return nil, "invalid config" end
    local encoded = str:sub(#config.prefix + 1):gsub("%s", "")
    if #encoded % 4 ~= 0 or encoded:find("[^A-Za-z0-9+/=]") then return nil, "invalid Base64" end
    local raw = config.b64_decode(encoded)
    if #raw < 8 or config.b64_encode(raw) ~= encoded then return nil, "invalid Base64 or header" end
    local size = config.read_u32(raw, 1)
    local plain = size >= 2147483648
    if plain then size = size - 2147483648 end
    if size > config.limit or size == 0 and not plain then return nil, "invalid decompressed size" end
    local data
    if plain then data = raw:sub(9) else data = config.decompress(raw:sub(9), size) end
    if not data or #data ~= size then return nil, "invalid compressed data" end
    if config.checksum(data) ~= config.read_u32(raw, 5) then return nil, "config checksum mismatch" end
    if data == "" then return nil, "empty config" end
    return data
end

function config.serialize(tbl)
    if util.json and util.json.stringify then return util.json.stringify(tbl) end
    local function escape(value) return (tostring(value):gsub("[^%w _%-]", function(c) return string.format("%%%02X", c:byte()) end)) end
    local function scalar(value)
        if type(value) == "boolean" then return value and "b1" or "b0" end
        if type(value) == "number" then return "n" .. tostring(value) end
        return "s" .. escape(value)
    end
    local parts = {}
    for k, v in pairs(tbl) do
        local value
        if type(v) == "table" then
            local sub = {}
            for _, sv in ipairs(v) do sub[#sub + 1] = scalar(sv) end
            value = "a" .. table.concat(sub, ",")
        else
            value = scalar(v)
        end
        parts[#parts + 1] = escape(k) .. "=" .. value
    end
    table.sort(parts)
    return "UCFG2\n" .. table.concat(parts, ";")
end

function config.parse(str)
    if util.json and util.json.parse and (str:sub(1, 1) == "{" or str:sub(1, 1) == "[") then
        local ok, tbl = pcall(util.json.parse, str)
        return ok and type(tbl) == "table" and tbl or nil
    end
    if str:sub(1, 6) ~= "UCFG2\n" then return nil end
    local function unescape(value) return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)) end
    local function scalar(value)
        local kind, raw = value:sub(1, 1), value:sub(2)
        if kind == "s" then return unescape(raw) end
        if kind == "n" then return tonumber(raw) end
        if value == "b1" then return true end
        if value == "b0" then return false end
    end
    local tbl = {}
    for entry in str:sub(7):gmatch("[^;]+") do
        local key, value = entry:match("^([^=]+)=(.*)$")
        if not key then return nil end
        local decoded
        if value:sub(1, 1) == "a" then
            decoded = {}
            for item in value:sub(2):gmatch("[^,]+") do
                local v = scalar(item)
                if v == nil then return nil end
                decoded[#decoded + 1] = v
            end
        else
            decoded = scalar(value)
        end
        if decoded == nil then return nil end
        tbl[unescape(key)] = decoded
    end
    return tbl
end

function config.dump()
    local data = {}
    for _, item in ipairs(config.items) do
        if item.kind == "color_picker" then
            data[item.key] = {ui.get(item.ref)}
        elseif item.kind == "hotkey" then
            local _, mode, key = ui.get(item.ref)
            data[item.key] = {mode or 1, key or 0}
        else
            data[item.key] = ui.get(item.ref)
        end
    end
    return data
end

function config.apply(data, action)
    local matched, failed = 0, 0
    core.config_loading = true
    for _, item in ipairs(config.items) do
        local val = data[item.key]
        if val ~= nil then
            matched = matched + 1
            if item.kind == "hotkey" and type(val) == "table" then
                local mode = native.hotkey_modes[(tonumber(val[1]) or 1) + 1]
                val = mode and {mode, tonumber(val[2]) or 0} or nil
            end
            local spread = type(val) == "table" and (item.kind == "color_picker" or item.kind == "hotkey")
            if val == nil or not pcall(function() if spread then ui.set(item.ref, unpack(val)) else ui.set(item.ref, val) end end) then
                failed = failed + 1
                client.error_log("[Ünoins_qucy] Invalid config field: " .. item.key)
            end
        end
    end
    core.config_loading = nil
    def.changed()
    if matched == 0 then
        style.log("config " .. action .. " failed: no recognized settings")
        return
    end
    fs.invalidate()
    comm.sync()
    core.sync()
    scope.control()
    menu.update()
    if failed > 0 then
        style.log(string.format("config %s partial: %d applied, %d failed; see errors above", action, matched - failed, failed))
    else
        style.log(action == "import" and "config imported" or "config loaded")
    end
end

function config.load(raw, action)
    local text, err = config.decode(raw)
    if not text then
        style.log("config " .. action .. " failed: " .. err)
        return
    end
    local data = config.parse(text)
    if data then config.apply(data, action) else style.log("config " .. action .. " failed: invalid data") end
end

function config.refresh()
    config.list = config.names()
    ui.update(gui.cfg_list, config.list)
end

config.refresh()
ui.set_callback(gui.cfg_list, function()
    local name = config.list[(ui.get(gui.cfg_list) or 0) + 1]
    if name and name ~= "-" then ui.set(gui.cfg_name, name) end
end)
ui.set_callback(gui.cfg_save, function()
    local name = ui.get(gui.cfg_name)
    if not name or name == "" then name = config.list[(ui.get(gui.cfg_list) or 0) + 1] or "default" end
    name = name:gsub("[%c%s]+$", ""):gsub("^[%c%s]+", "")
    if name == "" or name == "-" then name = "default" end
    local found = false
    for _, n in ipairs(config.list) do
        if n == name then found = true end
    end
    if not found then
        config.list[#config.list + 1] = name
        database.write("unoins_cfg_list", config.list)
    end
    database.write("unoins_cfg_" .. name, config.encode(config.serialize(config.dump())))
    config.refresh()
    style.log("config saved")
end)
ui.set_callback(gui.cfg_load, function()
    local name = config.list[(ui.get(gui.cfg_list) or 0) + 1]
    if not name or name == "-" then return end
    local raw = database.read("unoins_cfg_" .. name)
    if raw then config.load(raw, "load") end
end)
ui.set_callback(gui.cfg_delete, function()
    local name = config.list[(ui.get(gui.cfg_list) or 0) + 1]
    if not name or name == "-" then return end
    local list = {}
    for _, n in ipairs(config.list) do
        if n ~= name then list[#list + 1] = n end
    end
    if #list == 0 then list = {"default"} end
    config.list = list
    database.write("unoins_cfg_list", list)
    database.write("unoins_cfg_" .. name, nil)
    config.refresh()
    style.log("config deleted")
end)
ui.set_callback(gui.cfg_export, function()
    local ok, result = pcall(util.clipboard.set, config.encode(config.serialize(config.dump())))
    if not ok or result == false then
        style.log("config export failed: clipboard unavailable")
        return
    end
    style.log("config exported")
end)
ui.set_callback(gui.cfg_import, function()
    local ok, raw = pcall(util.clipboard.get)
    if not ok then
        style.log("config import failed: clipboard unavailable")
        return
    end
    if raw and raw ~= "" then config.load(raw, "import") end
end)


function menu.visible(page)
    for _, h in ipairs(menu.headers) do ui.set_visible(h.ref, h.page == page) end
    local indicator = ui.get(gui.indicator)
    for _, c in ipairs(menu.controls) do
        ui.set_visible(c.ref, menu.shown(c, page, indicator))
    end
end

function menu.shown(c, page, indicator)
    if c.page ~= page or c.parent and not util.active(gui[c.parent]) or c.parent2 and not util.active(gui[c.parent2]) then return false end
    if c.indicator and not c.indicator[indicator] then return false end
    local w = c.when
    if w then
        for i = 1, #w, 2 do
            if ui.get(gui[w[i]]) ~= w[i + 1] then return false end
        end
    end
    return true
end

function menu.refresh_aim()
    local items = {}
    for i, name in ipairs(menu.aim_names) do items[i] = ui.get(gui[menu.aim_keys[i]]) and name or name .. style.off end
    local key = table.concat(items, "|")
    if key ~= menu.aim_key then
        menu.aim_key = key
        ui.update(gui.aim_list, items)
    end
end

function menu.refresh_conditions()
    local items = {}
    local defensive = ui.get(gui.page) == "Defensive"
    for i, cond in ipairs(conditions) do
        local c = builder[cond]
        local off = defensive and not ui.get(c.force_def) or not defensive and c.enabled and not ui.get(c.enabled)
        items[i] = off and cond .. style.off or cond
    end
    local key = table.concat(items, "|")
    if key ~= menu.cond_key then
        menu.cond_key = key
        ui.update(gui.condition, items)
    end
end

function menu.update()
    local master_on = ui.get(gui.master)
    native.visible(not master_on)
    local page = master_on and ui.get(gui.page) or ""
    local home, builder_page, defensive = page == "Home", page == "Builder", page == "Defensive"
    local binds, rage, world, visuals = page == "Binds", page == "Rage", page == "World", page == "Visuals"
    ui.set_visible(gui.master, not master_on or home)
    ui.set_visible(gui.pet, home)
    ui.set_visible(gui.banner, home)
    ui.set_visible(gui.page, master_on and not ui.get(gui.banner))
    for _, r in ipairs({gui.cfg_list, gui.cfg_name, gui.cfg_load, gui.cfg_save, gui.cfg_delete, gui.cfg_import, gui.cfg_export}) do ui.set_visible(r, home) end
    ui.set_visible(gui.backend, defensive)
    local pro_visible = defensive and ui.get(gui.backend):find("Ünoins_qucy Pro", 1, true) ~= nil
    for _, r in ipairs({gui.safe_head, gui.backstab, gui.manual_left, gui.manual_right, gui.manual_fwd, gui.fs_key, gui.fs_states, gui.fs_options, gui.edge_key, gui.fast_ladder}) do
        ui.set_visible(r, binds)
    end
    ui.set_visible(gui.cond_header, builder_page or defensive)
    ui.set_visible(gui.condition, builder_page or defensive)
    ui.set_visible(gui.hide_weapon, visuals)
    ui.set_visible(gui.indicator, visuals)
    ui.set_visible(gui.resolver, rage)
    ui.set_visible(gui.hitlog, rage)
    ui.set_visible(gui.clan, world)
    ui.set_visible(gui.mute, world)
    menu.visible(page)
    menu.refresh_conditions()
    menu.refresh_aim()
    local sel = conditions[(ui.get(gui.condition) or 0) + 1] or "Global"
    ui.set_visible(gui.fl_ground, builder_page and ui.get(builder[sel].fakelag):find("Adaptive", 1, true) ~= nil)
    for _, cond in ipairs(conditions) do
        local c = builder[cond]
        local vis, dvis = builder_page and cond == sel, defensive and cond == sel
        if c.enabled then ui.set_visible(c.enabled, vis) end
        for _, r in ipairs({c.h_yaw, c.yaw_base, c.yaw_add, c.yaw_left_right, c.h_jit, c.yaw_jitter, c.h_body, c.body_yaw, c.fakelag}) do ui.set_visible(r, vis) end
        local lr_on = vis and ui.get(c.yaw_left_right)
        ui.set_visible(c.left, lr_on)
        ui.set_visible(c.left_randomization, lr_on)
        ui.set_visible(c.right, lr_on)
        ui.set_visible(c.right_randomization, lr_on)
        local fl_custom = vis and ui.get(c.fakelag) == "Always on"
        ui.set_visible(c.fl_amount, fl_custom)
        ui.set_visible(c.fl_variance, fl_custom)
        ui.set_visible(c.fl_limit, fl_custom)
        local jitter = ui.get(c.yaw_jitter)
        ui.set_visible(c.yaw_jit_add, vis and jitter ~= "Off")
        ui.set_visible(c.pulse_lopsided, vis and jitter == antiaim.PULSE)
        ui.set_visible(c.pulse_extras, vis and jitter == antiaim.PULSE)
        local pro_on = vis and jitter == antiaim.SLOW_PRO
        local lift_on = pro_on and ui.get(c.slow_pro_mode) == "Cycle lift"
        ui.set_visible(c.slow_pro_degree, pro_on)
        ui.set_visible(c.slow_pro_random, pro_on)
        ui.set_visible(c.slow_pro_speed, pro_on and not lift_on)
        ui.set_visible(c.slow_pro_mode, pro_on)
        ui.set_visible(c.slow_pro_min, lift_on)
        ui.set_visible(c.slow_pro_max, lift_on)
        ui.set_visible(c.slow_pro_interval, lift_on)
        local body = ui.get(c.body_yaw)
        local sided = vis and body ~= "Off" and not body:find("Opposite", 1, true)
        ui.set_visible(c.body_side, sided)
        ui.set_visible(c.body_delay, sided)
        local def_on = dvis and ui.get(c.force_def)
        ui.set_visible(c.force_def, dvis)
        for _, r in ipairs({c.def_mode, c.def_duration, c.h_pitch, c.def_pitch, c.h_dyaw, c.def_yaw, c.h_dbody, c.def_body_yaw}) do ui.set_visible(r, def_on) end
        ui.set_visible(c.def_trigger, def_on and not pro_visible)
        local dp = def_on and ui.get(c.def_pitch) or "Off"
        ui.set_visible(c.def_pitch_val, def_on and dp == "Custom")
        ui.set_visible(c.def_pitch_j1, def_on and dp == "Jitter")
        ui.set_visible(c.def_pitch_j2, def_on and dp == "Jitter")
        ui.set_visible(c.def_pitch_jdelay, def_on and dp == "Jitter")
        local dp_spin = def_on and (dp == "Spin" or dp == "Auto Spin")
        ui.set_visible(c.def_pitch_speed, dp_spin)
        ui.set_visible(c.def_pitch_r1, def_on and dp == "Random")
        ui.set_visible(c.def_pitch_r2, def_on and dp == "Random")
        local dy = def_on and ui.get(c.def_yaw) or "Off"
        ui.set_visible(c.def_yaw_val, def_on and dy == "Custom")
        ui.set_visible(c.def_yaw_j1, def_on and dy == "Jitter")
        ui.set_visible(c.def_yaw_j2, def_on and dy == "Jitter")
        ui.set_visible(c.def_yaw_jdelay, def_on and dy == "Jitter")
        local dy_spin = def_on and (dy == "Spin" or dy == "Auto Spin")
        ui.set_visible(c.def_yaw_speed, dy_spin)
        ui.set_visible(c.def_yaw_r1, def_on and dy == "Random")
        ui.set_visible(c.def_yaw_r2, def_on and dy == "Random")
        local cway = def_on and dy == "Custom Way"
        ui.set_visible(c.def_yaw_way_count, cway)
        local ways = cway and ui.get(c.def_yaw_way_count) or 0
        for i = 1, 10 do ui.set_visible(c.def_yaw_ways[i], cway and i <= ways) end
        local def_body = def_on and ui.get(c.def_body_yaw) or "Inherit"
        local body_sided = def_on and (def_body == "Jitter Pro" or def_body == "Static Pro")
        ui.set_visible(c.def_body_side, body_sided)
        ui.set_visible(c.def_body_delay, body_sided)
    end
end

function menu.double_click()
    local down = client.key_state(0x01)
    local pressed = down and not menu.cond_down
    menu.cond_down = down
    if not pressed or not ui.is_menu_open() or not ui.get(gui.master) or not menu.cond_anchor then return end
    local page, list = ui.get(gui.page), menu.cond_anchor[3]
    local valid = list == "aim" and page == "Rage" or list == "condition" and (page == "Builder" or page == "Defensive")
    if not valid or (menu.gs_tab or 1) ~= 1 then
        menu.cond_press = nil
        return
    end
    local mx, my = ui.menu_position()
    local cx, cy = ui.mouse_position()
    local rx, ry, a, now = cx - mx, cy - my, menu.cond_anchor, globals.realtime()
    local last = menu.cond_press
    menu.cond_press = {now, rx, ry}
    if math.abs(rx - a[1]) > 4 or math.abs(ry - a[2]) > 4 or not last or now - last[1] > 0.4 or now < last[1]
        or math.abs(last[2] - a[1]) > 4 or math.abs(last[3] - a[2]) > 4 then return end
    menu.cond_press = nil
    local box
    if list == "aim" then
        box = gui[menu.aim_keys[(ui.get(gui.aim_list) or 0) + 1]]
    else
        local c = builder[conditions[(ui.get(gui.condition) or 0) + 1] or "Global"]
        box = page == "Defensive" and c.force_def or c.enabled
    end
    if box then ui.set(box, not ui.get(box)) end
end

function menu.native_paint()
    if ui.is_menu_open() then native.visible(not ui.get(gui.master)) end
end

ui.set_callback(gui.page, menu.update)
ui.set_callback(gui.master, function()
    comm.sync()
    if not ui.get(gui.master) then
        hitlog.shots = {}
        core.cleanup()
        native.reset()
        fs.invalidate()
        core.reset_master()
    end
    menu.update()
end)
ui.set_callback(gui.backend, function()
    pro.reset()
    menu.update()
end)
function menu.anchor(list)
    local mx, my = ui.menu_position()
    local cx, cy = ui.mouse_position()
    menu.cond_anchor = {cx - mx, cy - my, list}
    menu.update()
end

ui.set_callback(gui.condition, function() menu.anchor("condition") end)
ui.set_callback(gui.indicator, menu.update)
ui.set_callback(gui.backstab, menu.update)
ui.set_callback(gui.hide_weapon, function()
    if not ui.get(gui.hide_weapon) then tp.restore() end
    menu.update()
end)
ui.set_callback(gui.hitlog, function()
    if not ui.get(gui.hitlog) then hitlog.shots = {} end
    menu.update()
end)
ui.set_callback(gui.mute, function()
    comm.sync()
    menu.update()
end)
ui.set_callback(gui.resolver, function()
    if not ui.get(gui.resolver) then
        rh.clear_all()
        rh.enabled_last = false
    end
    menu.update()
end)
ui.set_callback(gui.fl_ground, function() fl.last.on = nil end)
for _, cond in ipairs(conditions) do
    local c = builder[cond]
    for _, field in ipairs(def.key_fields) do ui.set_callback(c[field], def.changed) end
    for _, r in ipairs(c.def_yaw_ways) do ui.set_callback(r, def.changed) end
    for _, r in ipairs({c.def_pitch, c.def_yaw, c.def_yaw_way_count, c.def_body_yaw}) do ui.set_callback(r, def.refresh) end
    for _, r in ipairs({c.yaw_left_right, c.yaw_jitter, c.slow_pro_mode, c.body_yaw, c.force_def, c.fakelag}) do ui.set_callback(r, menu.update) end
    if c.enabled then ui.set_callback(c.enabled, menu.update) end
end
ui.set_callback(gui.banner, menu.update)
for _, c in ipairs(menu.controls) do ui.set_callback(c.ref, core.changed) end
ui.set_callback(gui.aim_list, function() menu.anchor("aim") end)
ui.set_callback(gui.velocity, hud.changed)


client.set_event_callback("setup_command", function(cmd)
    dormant.command(cmd)
    qs.command(cmd)
    core.command(cmd)
    menu.block_input(cmd)
end)
client.set_event_callback("run_command", function(cmd)
    def.run_command(cmd)
    pro.run_command(cmd)
end)
client.set_event_callback("predict_command", function(cmd)
    def.predict_command(cmd)
    pro.predict_command(cmd)
end)
client.set_event_callback("net_update_start", function()
    def.net_update_start()
    clan.net_update_start()
end)
client.set_event_callback("net_update_end", function()
    rh.net_update_end()
    tp.update()
end)
client.set_event_callback("pre_render", function()
    scope.control()
    anim.frame()
end)
client.set_event_callback("post_render", anim.restore)
client.set_event_callback("paint", function()
    fs.paint()
    dormant.paint()
    tp.update()
    ind.paint()
    scope.paint()
end)
client.set_event_callback("paint_ui", function()
    rh.retry()
    comm.tick()
    lang.tick()
    core.paint_ui()
    menu.paint()
    ind.qucy_paint()
    menu.double_click()
    menu.native_paint()
end)
client.set_event_callback("aim_fire", function(e)
    hc.release_used = true
    hitlog.fire(e)
    rh.fire(e)
    qs.fire()
end)
client.set_event_callback("aim_hit", function(e)
    hitlog.finish(e, "Hit")
    rh.hit(e)
    octo.play("cheer", 0.9)
end)
client.set_event_callback("aim_miss", function(e)
    hitlog.finish(e, "Miss")
    rh.miss(e)
    if e.reason == "?" then octo.play("confused", 1.4) end
end)
client.set_event_callback("player_spawn", function(e)
    def.reset_local(e)
    if client.userid_to_entindex(e.userid) == entity.get_local_player() then octo.play("wave", 1.8) end
end)
client.set_event_callback("player_death", function(e)
    def.reset_local(e)
    rh.player_death(e)
    core.player_death(e)
    octo.player_death(e)
end)
client.set_event_callback("level_init", function()
    def.read_proc()
    seq.reset()
    def.reset()
    hitlog.shots = {}
    rh.clear_all()
    tp.hidden = {}
    core.cleanup()
end)
client.set_event_callback("round_prestart", function()
    def.reset()
    hitlog.shots = {}
    rh.release_all()
    dormant.round_prestart()
    core.cleanup()
end)
client.set_event_callback("round_start", comm.sync)
client.set_event_callback("player_hurt", pulse.player_hurt)
client.set_event_callback("bullet_impact", pulse.bullet_impact)
client.set_event_callback("weapon_fire", rh.weapon_fire)
client.set_event_callback("post_config_load", function()
    native.snapshot = nil
    def.changed()
    comm.sync()
end)
client.set_event_callback("shutdown", function()
    comm.restore()
    lang.detach()
    core.shutdown()
end)
client.register_esp_flag("DA", 255, 255, 255, dormant.flag)

comm.restore()
menu.update()
core.changed()
