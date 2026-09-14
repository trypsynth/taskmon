// Shared application state. wndproc.zig depends on every other UI module
// (theme, tray, sortbar, treeview, listview, process, settings, run), so
// those modules can't @import wndproc.zig back to reach state it owns.
// Hoisting the shared bits into this leaf module (which only depends on
// win32.zig, settings.zig, and process_types.zig, none of which depend on
// anything above them) lets every UI module reach them with a normal
// @import instead.
const std = @import("std");
const win32 = @import("win32.zig");
const settings = @import("settings.zig");
const pt = @import("process_types.zig");
const services = @import("services.zig");

// Private window messages. Kept together so the WM_APP numbering has a single
// owner: WM_HIDE_TO_TRAY is posted by every control subclass that handles
// Escape, so it cannot live next to the handlers in wndproc.zig.
pub const WM_TRAYICON: win32.UINT = win32.WM_APP + 1;
pub const WM_HIDE_TO_TRAY: win32.UINT = win32.WM_APP + 2;
pub const WM_COLUMN_DRAGGED: win32.UINT = win32.WM_APP + 3;

pub var hwnd: win32.HWND = null;
pub var hwnd_list: win32.HWND = null;
pub var hwnd_tree: win32.HWND = null;
pub var hwnd_sort_group: win32.HWND = null;
pub var hwnd_status: win32.HWND = null;
pub var sort_btns: [settings.COL_COUNT]win32.HWND = std.mem.zeroes([settings.COL_COUNT]win32.HWND);
pub var sort_btn_cols: [settings.COL_COUNT]i32 = std.mem.zeroes([settings.COL_COUNT]i32);
pub var sort_btn_count: i32 = 0;
pub var hwnd_tab: win32.HWND = null;
pub var hwnd_svc_list: win32.HWND = null;
pub var hwnd_svc_sort_group: win32.HWND = null;
pub var svc_sort_btns: [services.COL_COUNT]win32.HWND = std.mem.zeroes([services.COL_COUNT]win32.HWND);
pub var svc_sort_cols: [services.COL_COUNT]i32 = std.mem.zeroes([services.COL_COUNT]i32);
pub var svc_sort_count: i32 = 0;
pub var svc_field: services.SortField = .name;
pub var svc_desc: bool = false;
pub var active_tab: i32 = 0;

pub var prefs: settings.SortPrefs = undefined;
pub var snapshots: [pt.SNAPSHOT_CAPACITY]pt.SnapshotEntry = std.mem.zeroes([pt.SNAPSHOT_CAPACITY]pt.SnapshotEntry);
pub var mutex: win32.HANDLE = null;
