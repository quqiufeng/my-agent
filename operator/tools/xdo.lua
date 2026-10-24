local ffi = require("ffi")

ffi.cdef[[
typedef unsigned long Window;
typedef unsigned long Atom;
typedef unsigned char Bool;
typedef struct _XDisplay Display;
typedef struct xdo xdo_t;
typedef struct {
    char *res_name;
    char *res_class;
} XClassHint;
void free(void *ptr);

Display *XOpenDisplay(const char *name);
int XCloseDisplay(Display *display);
Window XDefaultRootWindow(Display *display);
Atom XInternAtom(Display *display, const char *name, Bool only_if_exists);
int XGetWindowProperty(Display *display, Window w, Atom property,
    long offset, long length, Bool delete, Atom req_type,
    Atom *actual_type, int *actual_format, unsigned long *nitems,
    unsigned long *bytes_after, unsigned char **prop);
int XFree(void *data);
int XFetchName(Display *display, Window w, char **name);
int XGetGeometry(Display *display, unsigned long drawable, Window *root,
    int *x, int *y, unsigned int *width, unsigned int *height,
    unsigned int *border_width, unsigned int *depth);
int XTranslateCoordinates(Display *display, Window src, Window dst,
    int src_x, int src_y, int *dest_x, int *dest_y, Window *child);
int XMapWindow(Display *display, Window w);
int XUnmapWindow(Display *display, Window w);
int XGetClassHint(Display *display, Window w, XClassHint *class_hints);
int XSync(Display *display, Bool discard);

xdo_t *xdo_new(const char *display);
void xdo_free(xdo_t *xdo);
int xdo_get_window_name(const xdo_t *xdo, Window window,
    unsigned char **name_ret, int *name_len_ret, int *name_type);
int xdo_get_active_window(const xdo_t *xdo, Window *window_ret);
int xdo_activate_window(const xdo_t *xdo, Window wid);
int xdo_focus_window(const xdo_t *xdo, Window wid);
int xdo_raise_window(const xdo_t *xdo, Window wid);
int xdo_minimize_window(const xdo_t *xdo, Window wid);
int xdo_move_mouse(const xdo_t *xdo, int x, int y, int screen);
int xdo_move_mouse_relative_to_window(const xdo_t *xdo, Window window, int x, int y);
int xdo_click_window(const xdo_t *xdo, Window window, int button);
int xdo_send_keysequence_window(const xdo_t *xdo, Window window,
    const char *keysequence, unsigned int delay);
int xdo_enter_text_window(const xdo_t *xdo, Window window,
    const char *string, unsigned int delay);
]]

local X11 = ffi.load("X11")
local lib
for _, name in ipairs({ "xdo", "libxdo.so.3", "libxdo.so" }) do
    local ok, handle = pcall(ffi.load, name)
    if ok then lib = handle; break end
end
assert(lib, "无法加载 libxdo（安装 libxdo3）")

local Xdo = {}
Xdo.__index = Xdo

local function x11_string(ptr, len)
    if ptr == nil then return nil end
    local s = ffi.string(ptr, tonumber(len))
    return s
end

function Xdo.new(display)
    local xdpy = X11.XOpenDisplay(display and ffi.cast("const char *", display) or nil)
    if xdpy == nil then return nil, "XOpenDisplay 失败（DISPLAY?）" end
    local handle = lib.xdo_new(display and ffi.cast("const char *", display) or nil)
    if handle == nil then X11.XCloseDisplay(xdpy); return nil, "xdo_new 失败" end
    return setmetatable({ handle = handle, dpy = xdpy }, Xdo)
end

function Xdo:close()
    if self.handle ~= nil then lib.xdo_free(self.handle); self.handle = nil end
    if self.dpy ~= nil then X11.XCloseDisplay(self.dpy); self.dpy = nil end
end

function Xdo:_name(win)
    local atom = X11.XInternAtom(self.dpy, "_NET_WM_NAME", 0)
    local actual, fmt = ffi.new("Atom[1]"), ffi.new("int[1]")
    local n, after = ffi.new("unsigned long[1]"), ffi.new("unsigned long[1]")
    local prop = ffi.new("unsigned char *[1]")
    local rc = X11.XGetWindowProperty(self.dpy, win, atom, 0, 1024, 0, 0,
        actual, fmt, n, after, prop)
    if rc == 0 and prop[0] ~= nil and n[0] > 0 then
        local s = x11_string(prop[0], n[0])
        X11.XFree(prop[0])
        if s and #s > 0 then return s end
    end
    local name = ffi.new("char *[1]")
    if X11.XFetchName(self.dpy, win, name) ~= 0 and name[0] ~= nil then
        local s = ffi.string(name[0])
        X11.XFree(name[0])
        if #s > 0 then return s end
    end
    return nil
end

function Xdo:_geom(win)
    local root = ffi.new("Window[1]")
    local x, y = ffi.new("int[1]"), ffi.new("int[1]")
    local w, h = ffi.new("unsigned int[1]"), ffi.new("unsigned int[1]")
    local bw, depth = ffi.new("unsigned int[1]"), ffi.new("unsigned int[1]")
    if X11.XGetGeometry(self.dpy, win, root, x, y, w, h, bw, depth) == 0 then
        return nil
    end
    local rx, ry = ffi.new("int[1]"), ffi.new("int[1]")
    local child = ffi.new("Window[1]")
    X11.XTranslateCoordinates(self.dpy, win, root[0], 0, 0, rx, ry, child)
    return { x = tonumber(rx[0]), y = tonumber(ry[0]),
             w = tonumber(w[0]), h = tonumber(h[0]) }
end

function Xdo:windows()
    local root = X11.XDefaultRootWindow(self.dpy)
    local atom = X11.XInternAtom(self.dpy, "_NET_CLIENT_LIST", 0)
    local actual, fmt = ffi.new("Atom[1]"), ffi.new("int[1]")
    local n, after = ffi.new("unsigned long[1]"), ffi.new("unsigned long[1]")
    local prop = ffi.new("unsigned char *[1]")
    local rc = X11.XGetWindowProperty(self.dpy, root, atom, 0, 4096, 0, 33,
        actual, fmt, n, after, prop)
    if rc ~= 0 or prop[0] == nil then return {} end
    local list = ffi.cast("Window *", prop[0])
    local out = {}
    for i = 0, tonumber(n[0]) - 1 do
        local win = list[i]
        out[#out + 1] = { id = win, name = self:_name(win), geom = self:_geom(win) }
    end
    X11.XFree(prop[0])
    return out
end

function Xdo:find(pattern)
    local out = {}
    for _, w in ipairs(self:windows()) do
        if pattern == nil or (w.name and w.name:find(pattern)) then
            out[#out + 1] = w
        end
    end
    return out
end

function Xdo:find_class(pattern)
    local out = {}
    for _, w in ipairs(self:windows()) do
        local hint = ffi.new("XClassHint")
        if X11.XGetClassHint(self.dpy, w.id, hint) ~= 0 then
            local cls = hint.res_class ~= nil and ffi.string(hint.res_class) or ""
            if hint.res_name ~= nil then X11.XFree(hint.res_name) end
            if hint.res_class ~= nil then X11.XFree(hint.res_class) end
            if pattern == nil or cls:lower():find(pattern:lower(), 1, true) then
                out[#out + 1] = w
            end
        end
    end
    return out
end

function Xdo:name(win) return self:_name(win) end
function Xdo:geometry(win) return self:_geom(win) end

function Xdo:active()
    local win = ffi.new("Window[1]")
    if lib.xdo_get_active_window(self.handle, win) ~= 0 then return nil end
    return tonumber(win[0])
end

function Xdo:activate(win) return lib.xdo_activate_window(self.handle, win) == 0 end
function Xdo:focus(win) return lib.xdo_focus_window(self.handle, win) == 0 end
function Xdo:raise(win) return lib.xdo_raise_window(self.handle, win) == 0 end
function Xdo:minimize(win) return lib.xdo_minimize_window(self.handle, win) == 0 end
function Xdo:hide(win)
    local ok = X11.XUnmapWindow(self.dpy, win) ~= 0
    X11.XSync(self.dpy, 0)
    return ok
end
function Xdo:show(win)
    local ok = X11.XMapWindow(self.dpy, win) ~= 0
    X11.XSync(self.dpy, 0)
    return ok
end
function Xdo:move(win, x, y)
    return lib.xdo_move_mouse_relative_to_window(self.handle, win, x, y) == 0
end
function Xdo:move_abs(x, y) return lib.xdo_move_mouse(self.handle, x, y, 0) == 0 end
function Xdo:click(win, x, y, button)
    if not self:move(win, x, y) then return false end
    return lib.xdo_click_window(self.handle, win, button or 1) == 0
end
function Xdo:key(win, seq, delay)
    return lib.xdo_send_keysequence_window(self.handle, win, seq, delay or 12000) == 0
end
function Xdo:type(win, text, delay)
    return lib.xdo_enter_text_window(self.handle, win, text, delay or 12000) == 0
end

return Xdo
