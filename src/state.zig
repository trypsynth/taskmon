// Shared application state. wndproc.zig depends on every other UI module
// (theme, tray, sortbar, treeview, listview, process, settings, run), so
// those modules can't @import wndproc.zig back to reach state it owns -
// that's a real import cycle, not a migration leftover. Hoisting the
// shared bits into this leaf module (which only depends on win32.zig,
// settings.zig, and process_types.zig, none of which depend on anything
// above them) lets every UI module reach them with a normal @import
// instead of extern var/export var C-ABI symbol linking.
const std = @import("std");
const win32 = @import("win32.zig");
const settings = @import("settings.zig");
const pt = @import("process_types.zig");

pub var hwnd: win32.HWND = null;
pub var hwnd_list: win32.HWND = null;
pub var hwnd_tree: win32.HWND = null;
pub var hwnd_sort_group: win32.HWND = null;
pub var hwnd_status: win32.HWND = null;
pub var sort_btns: [settings.COL_COUNT]win32.HWND = std.mem.zeroes([settings.COL_COUNT]win32.HWND);
pub var sort_btn_cols: [settings.COL_COUNT]i32 = std.mem.zeroes([settings.COL_COUNT]i32);
pub var sort_btn_count: i32 = 0;
pub var prefs: settings.SortPrefs = undefined;
pub var snapshots: [pt.SNAPSHOT_CAPACITY]pt.SnapshotEntry = std.mem.zeroes([pt.SNAPSHOT_CAPACITY]pt.SnapshotEntry);
pub var mutex: win32.HANDLE = null;
