const std = @import("std");
const win32 = @import("win32.zig");
const resource = @import("resource.zig");
const pt = @import("process_types.zig");
const settings = @import("settings.zig");
const theme = @import("theme.zig");
const tray = @import("tray.zig");
const run = @import("run.zig");
const sortbar = @import("sortbar.zig");
const treeview = @import("treeview.zig");
const listview = @import("listview.zig");
const process = @import("process.zig");
const state = @import("state.zig");
const wfmt = @import("wfmt.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

const ID_LISTVIEW = 105;
const ID_TREEVIEW = 106;
const ID_TRAY_RESTORE = 201;
const ID_TRAY_EXIT = 202;
const ID_CTX_OPEN_LOCATION = 301;
const ID_CTX_SUSPEND = 303;
const ID_CTX_RESUME = 304;
const ID_CTX_PRIORITY_BASE = 310; // +0=Idle +1=BelowNormal +2=Normal +3=AboveNormal +4=High +5=Realtime
const PRIORITY_CLASS_COUNT = 6;
const WM_TRAYICON: win32.UINT = win32.WM_APP + 1;
const WM_HIDE_TO_TRAY: win32.UINT = win32.WM_APP + 2;
const ID_REFRESH_TIMER = 1;
const ID_PRIME_TIMER = 2;
const ID_HOTKEY_TOGGLE = 1;

const PriorityEntry = struct {
	cls: win32.DWORD,
	label: win32.LPCWSTR,
};
const PRIORITY_CLASSES = [PRIORITY_CLASS_COUNT]PriorityEntry{
	.{ .cls = win32.IDLE_PRIORITY_CLASS, .label = L("Idle") },
	.{ .cls = win32.BELOW_NORMAL_PRIORITY_CLASS, .label = L("Below Normal") },
	.{ .cls = win32.NORMAL_PRIORITY_CLASS, .label = L("Normal") },
	.{ .cls = win32.ABOVE_NORMAL_PRIORITY_CLASS, .label = L("Above Normal") },
	.{ .cls = win32.HIGH_PRIORITY_CLASS, .label = L("High") },
	.{ .cls = win32.REALTIME_PRIORITY_CLASS, .label = L("Realtime") },
};

pub const CLASS_NAME = L("TaskmonWndClass").*;
pub const WINDOW_TITLE = L("Taskmon").*;

var last_focus: win32.HWND = null;

fn setRefreshInterval(hwnd: win32.HWND, ms_in: win32.UINT) void {
	var ms = ms_in;
	var found = false;
	for (settings.REFRESH_MS) |option| {
		if (option == ms) {
			found = true;
			break;
		}
	}
	if (!found) ms = 0;
	state.prefs.refresh_ms = ms;
	_ = win32.KillTimer(hwnd, ID_REFRESH_TIMER);
	if (ms > 0) _ = win32.SetTimer(hwnd, ID_REFRESH_TIMER, ms, null);
	settings.save(&state.prefs);
}

fn isElevated() bool {
	var token: win32.HANDLE = null;
	var elev: win32.TOKEN_ELEVATION = std.mem.zeroes(win32.TOKEN_ELEVATION);
	var size: win32.DWORD = @sizeOf(win32.TOKEN_ELEVATION);
	if (win32.OpenProcessToken(win32.GetCurrentProcess(), win32.TOKEN_QUERY, &token) == 0) return false;
	_ = win32.GetTokenInformation(token, win32.TokenElevation, &elev, size, &size);
	_ = win32.CloseHandle(token);
	return elev.TokenIsElevated != 0;
}

fn confirmEndTask(hwnd: win32.HWND, name: [*:0]const u16, pid: win32.DWORD) bool {
	if (state.prefs.skip_kill_confirm) return true;
	var message: [512:0]u16 = std.mem.zeroes([512:0]u16);
	wfmt.format(&message, 512, "End \"%s\" (PID %u)?\n\nUnsaved data may be lost.", .{ if (name[0] != 0) name else L("this process"), pid });
	return win32.MessageBoxW(hwnd, &message, L("Confirm End Task"), win32.MB_ICONQUESTION | win32.MB_YESNO | win32.MB_DEFBUTTON2) == win32.IDYES;
}

fn confirmEndTree(hwnd: win32.HWND, name: [*:0]const u16, pid: win32.DWORD) bool {
	if (state.prefs.skip_kill_confirm) return true;
	var message: [512:0]u16 = std.mem.zeroes([512:0]u16);
	wfmt.format(&message, 512, "End \"%s\" (PID %u) and all its descendant processes?\n\nUnsaved data may be lost.", .{ if (name[0] != 0) name else L("this process"), pid });
	return win32.MessageBoxW(hwnd, &message, L("Confirm End Process Tree"), win32.MB_ICONQUESTION | win32.MB_YESNO | win32.MB_DEFBUTTON2) == win32.IDYES;
}

fn openItemLocation(path: [*:0]const u16) bool {
	var folder: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
	_ = win32.lstrcpyW(&folder, path);
	_ = win32.PathRemoveFileSpecW(&folder);
	const folder_pidl = win32.ILCreateFromPathW(&folder);
	const item_pidl = win32.ILCreateFromPathW(path);
	if (folder_pidl == null or item_pidl == null) {
		if (folder_pidl != null) win32.ILFree(folder_pidl);
		if (item_pidl != null) win32.ILFree(item_pidl);
		return false;
	}
	const child = win32.ILFindLastID(item_pidl);
	const children = [1]win32.PUITEMID_CHILD{child};
	const hr = win32.SHOpenFolderAndSelectItems(folder_pidl, 1, &children, 0);
	win32.ILFree(item_pidl);
	win32.ILFree(folder_pidl);
	if (hr >= 0) return true;
	return @intFromPtr(win32.ShellExecuteW(null, L("open"), &folder, null, null, win32.SW_SHOW)) > 32;
}

fn createMenuBar(hwnd: win32.HWND) void {
	const bar = win32.CreateMenu();
	const file = win32.CreatePopupMenu();
	_ = win32.AppendMenuW(file, win32.MF_STRING, resource.ID_FILE_NEW_TASK, L("New task...\tCtrl+N"));
	_ = win32.AppendMenuW(file, win32.MF_SEPARATOR, 0, null);
	_ = win32.AppendMenuW(file, win32.MF_STRING | (if (isElevated()) win32.MF_GRAYED else 0), resource.ID_FILE_RESTART_AS_ADMIN, L("Restart as administrator"));
	_ = win32.AppendMenuW(file, win32.MF_SEPARATOR, 0, null);
	_ = win32.AppendMenuW(file, win32.MF_STRING, resource.ID_FILE_EXIT, L("Exit\tCtrl+Q"));
	_ = win32.AppendMenuW(bar, win32.MF_POPUP, @intFromPtr(file), L("&File"));
	const view = win32.CreatePopupMenu();
	_ = win32.AppendMenuW(view, win32.MF_STRING, resource.ID_VIEW_REFRESH, L("Refresh\tF5"));
	_ = win32.AppendMenuW(view, win32.MF_SEPARATOR, 0, null);
	_ = win32.AppendMenuW(view, win32.MF_STRING | (if (state.prefs.always_on_top) win32.MF_CHECKED else 0), resource.ID_VIEW_ALWAYS_ON_TOP, L("Always on Top"));
	_ = win32.AppendMenuW(view, win32.MF_STRING | (if (state.prefs.tree_mode) win32.MF_CHECKED else 0), resource.ID_VIEW_TREE_MODE, L("Process Tree\tCtrl+T"));
	_ = win32.AppendMenuW(view, win32.MF_SEPARATOR, 0, null);
	_ = win32.AppendMenuW(view, win32.MF_STRING, resource.ID_VIEW_SETTINGS, L("Settings...\tCtrl+,"));
	_ = win32.AppendMenuW(bar, win32.MF_POPUP, @intFromPtr(view), L("View"));
	_ = win32.SetMenu(hwnd, bar);
}

fn pointFromLparam(lp: win32.LPARAM) win32.POINT {
	const ulp: usize = @bitCast(lp);
	const x: i16 = @bitCast(@as(u16, @truncate(ulp)));
	const y: i16 = @bitCast(@as(u16, @truncate(ulp >> 16)));
	return .{ .x = x, .y = y };
}

fn getSelectedPid() win32.DWORD {
	if (state.prefs.tree_mode) return treeview.getSelectedPid();
	return listview.getItemPid(listview.getSelectedIndex());
}

fn buildPriorityMenu(pid: win32.DWORD) win32.HMENU {
	const pri_menu = win32.CreatePopupMenu();
	var cur_cls: win32.DWORD = 0;
	const ph = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
	if (ph != null) {
		cur_cls = win32.GetPriorityClass(ph);
		_ = win32.CloseHandle(ph);
	}
	for (0..PRIORITY_CLASS_COUNT) |idx| {
		const flags = win32.MF_STRING | (if (PRIORITY_CLASSES[idx].cls == cur_cls) win32.MF_CHECKED else 0);
		_ = win32.AppendMenuW(pri_menu, flags, @intCast(ID_CTX_PRIORITY_BASE + idx), PRIORITY_CLASSES[idx].label);
	}
	return pri_menu;
}

fn showProcessContextMenu(hwnd: win32.HWND, pid: win32.DWORD, point: win32.POINT, include_end_tree: bool) void {
	const menu = win32.CreatePopupMenu();
	var path: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
	process.getProcessPath(pid, &path, @intCast(win32.MAX_PATH));
	if (path[0] != 0) _ = win32.AppendMenuW(menu, win32.MF_STRING, ID_CTX_OPEN_LOCATION, L("Open file location"));
	if (process.isProcessSuspended(pid))
		_ = win32.AppendMenuW(menu, win32.MF_STRING, ID_CTX_RESUME, L("Resume"))
	else
		_ = win32.AppendMenuW(menu, win32.MF_STRING, ID_CTX_SUSPEND, L("Suspend"));
	_ = win32.AppendMenuW(menu, win32.MF_STRING, resource.ID_CTX_END_TASK, L("End task\tDelete"));
	if (include_end_tree) _ = win32.AppendMenuW(menu, win32.MF_STRING, resource.ID_CTX_END_PROCESS_TREE, L("End process tree"));
	const pri_menu = buildPriorityMenu(pid);
	_ = win32.AppendMenuW(menu, win32.MF_POPUP, @intFromPtr(pri_menu), L("Priority"));
	_ = win32.TrackPopupMenu(menu, win32.TPM_RIGHTBUTTON, point.x, point.y, 0, hwnd, null);
	_ = win32.DestroyMenu(menu);
}

fn handleCommand(hwnd: win32.HWND, wp: win32.WPARAM) win32.LRESULT {
	const id: u16 = @truncate(wp);
	if (id == ID_TRAY_RESTORE) {
		tray.restore();
		return 0;
	}
	if (id == ID_TRAY_EXIT) {
		_ = win32.DestroyWindow(hwnd);
		return 0;
	}
	if (id == win32.IDCANCEL) {
		_ = win32.PostMessageW(hwnd, WM_HIDE_TO_TRAY, 0, 0);
		return 0;
	}
	if (id == ID_CTX_SUSPEND or id == ID_CTX_RESUME) {
		const pid = getSelectedPid();
		if (pid != 0) {
			if (id == ID_CTX_SUSPEND) _ = process.suspendProcess(pid) else _ = process.resumeProcess(pid);
			listview.doRefresh();
		}
		return 0;
	}
	if (id == ID_CTX_OPEN_LOCATION or id == resource.ID_CTX_END_TASK) {
		if (state.prefs.tree_mode) {
			var name: [260:0]u16 = std.mem.zeroes([260:0]u16);
			treeview.getSelectedName(&name, 260);
			const pid = treeview.getSelectedPid();
			if (pid != 0) {
				if (id == ID_CTX_OPEN_LOCATION) {
					var path: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
					process.getProcessPath(pid, &path, @intCast(win32.MAX_PATH));
					if (path[0] != 0) _ = openItemLocation(&path);
				} else {
					if (confirmEndTask(hwnd, &name, pid)) {
						_ = process.terminateProcess(pid);
						listview.doRefresh();
					}
				}
			}
			return 0;
		}
		const selected = listview.getSelectedIndex();
		if (selected != -1) {
			const pid = listview.getItemPid(selected);
			var name: [260:0]u16 = std.mem.zeroes([260:0]u16);
			var get_text_lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
			get_text_lvi.iSubItem = 0;
			get_text_lvi.cchTextMax = 260;
			get_text_lvi.pszText = &name;
			_ = win32.SendMessageW(state.hwnd_list, win32.LVM_GETITEMTEXTW, @intCast(selected), @bitCast(@intFromPtr(&get_text_lvi)));
			if (id == ID_CTX_OPEN_LOCATION) {
				var path: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
				process.getProcessPath(pid, &path, @intCast(win32.MAX_PATH));
				if (path[0] != 0) _ = openItemLocation(&path);
			} else if (id == resource.ID_CTX_END_TASK) {
				if (confirmEndTask(hwnd, &name, pid)) {
					_ = process.terminateProcess(pid);
					listview.doRefresh();
					const count: i32 = @intCast(win32.SendMessageW(state.hwnd_list, win32.LVM_GETITEMCOUNT, 0, 0));
					var pid_still_present = false;
					for (0..@intCast(count)) |i| {
						if (listview.getItemPid(@intCast(i)) == pid) {
							pid_still_present = true;
							break;
						}
					}
					if (!pid_still_present and count > 0) {
						const new_sel: i32 = if (selected < count) selected else count - 1;
						listview.selectItem(new_sel);
						_ = win32.SendMessageW(state.hwnd_list, win32.LVM_ENSUREVISIBLE, @intCast(new_sel), 0);
					}
				}
			}
		}
		return 0;
	}
	if (id == resource.ID_CTX_END_PROCESS_TREE) {
		const sel = treeview.getSelection();
		if (sel != null) {
			var name: [260:0]u16 = std.mem.zeroes([260:0]u16);
			treeview.getSelectedName(&name, 260);
			const pid = treeview.getSelectedPid();
			if (confirmEndTree(hwnd, &name, pid)) {
				treeview.terminateFromItem(sel);
				listview.doRefresh();
			}
		}
		return 0;
	}
	if (id == resource.ID_VIEW_TREE_MODE) {
		state.prefs.tree_mode = !state.prefs.tree_mode;
		const view = win32.GetSubMenu(win32.GetMenu(hwnd), 1);
		_ = win32.CheckMenuItem(view, resource.ID_VIEW_TREE_MODE, if (state.prefs.tree_mode) win32.MF_CHECKED else win32.MF_UNCHECKED);
		if (state.prefs.tree_mode) {
			_ = win32.ShowWindow(state.hwnd_list, win32.SW_HIDE);
			_ = win32.ShowWindow(state.hwnd_tree, win32.SW_SHOW);
			_ = win32.SetFocus(state.hwnd_tree);
		} else {
			_ = win32.ShowWindow(state.hwnd_tree, win32.SW_HIDE);
			_ = win32.ShowWindow(state.hwnd_list, win32.SW_SHOW);
			_ = win32.SetFocus(state.hwnd_list);
		}
		listview.resort();
		settings.save(&state.prefs);
		return 0;
	}
	if (id >= ID_CTX_PRIORITY_BASE and id < ID_CTX_PRIORITY_BASE + PRIORITY_CLASS_COUNT) {
		const pid = getSelectedPid();
		if (pid != 0) {
			_ = process.setProcessPriority(pid, PRIORITY_CLASSES[id - ID_CTX_PRIORITY_BASE].cls);
			listview.doRefresh();
		}
		return 0;
	}
	if (id == resource.ID_FILE_NEW_TASK) {
		run.openDialog(hwnd);
		return 0;
	}
	if (id == resource.ID_FILE_RESTART_AS_ADMIN) {
		var path: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
		_ = win32.GetModuleFileNameW(null, &path, @intCast(win32.MAX_PATH));
		if (state.mutex != null) {
			_ = win32.CloseHandle(state.mutex);
			state.mutex = null;
		}
		if (@intFromPtr(win32.ShellExecuteW(null, L("runas"), &path, null, null, win32.SW_SHOW)) > 32)
			_ = win32.DestroyWindow(hwnd)
		else if (state.mutex == null)
			state.mutex = win32.CreateMutexW(null, 1, L("Local\\TaskmonSingleInstance"));
		return 0;
	}
	if (id == resource.ID_FILE_EXIT) {
		_ = win32.DestroyWindow(hwnd);
		return 0;
	}
	if (id == resource.ID_VIEW_ALWAYS_ON_TOP) {
		state.prefs.always_on_top = !state.prefs.always_on_top;
		const view = win32.GetSubMenu(win32.GetMenu(hwnd), 1);
		_ = win32.CheckMenuItem(view, resource.ID_VIEW_ALWAYS_ON_TOP, if (state.prefs.always_on_top) win32.MF_CHECKED else win32.MF_UNCHECKED);
		_ = win32.SetWindowPos(hwnd, if (state.prefs.always_on_top) win32.HWND_TOPMOST else win32.HWND_NOTOPMOST, 0, 0, 0, 0, win32.SWP_NOMOVE | win32.SWP_NOSIZE);
		settings.save(&state.prefs);
		return 0;
	}
	if (id == resource.ID_VIEW_REFRESH) {
		listview.doRefresh();
		return 0;
	}
	if (id == resource.ID_VIEW_SETTINGS) {
		var new_ms: win32.UINT = undefined;
		var new_visible: [settings.COL_COUNT]bool = undefined;
		var new_skip_confirm: bool = undefined;
		var new_start_minimized: bool = undefined;
		if (settings.open(hwnd, state.prefs.refresh_ms, &state.prefs.visible, state.prefs.skip_kill_confirm, state.prefs.start_minimized_to_tray, &new_ms, &new_visible, &new_skip_confirm, &new_start_minimized)) {
			const cols_changed = !std.mem.eql(bool, &new_visible, &state.prefs.visible);
			state.prefs.visible = new_visible;
			state.prefs.skip_kill_confirm = new_skip_confirm;
			state.prefs.start_minimized_to_tray = new_start_minimized;
			if (new_ms != state.prefs.refresh_ms) setRefreshInterval(hwnd, new_ms);
			if (cols_changed) {
				sortbar.applyColumns();
				listview.resort();
			}
			settings.save(&state.prefs);
		}
		return 0;
	}
	const hiword: u16 = @truncate(wp >> 16);
	if (hiword == win32.BN_CLICKED) {
		for (0..@intCast(state.sort_btn_count)) |idx| {
			if (resource.ID_SORT_BASE + state.sort_btn_cols[idx] == @as(i32, id)) {
				const cid: usize = @intCast(state.sort_btn_cols[idx]);
				if (settings.COLUMNS[cid].field == state.prefs.field) {
					const fi: usize = @intCast(@intFromEnum(state.prefs.field));
					state.prefs.desc[fi] = !state.prefs.desc[fi];
				} else {
					state.prefs.field = settings.COLUMNS[cid].field;
				}
				sortbar.updateSortUi();
				sortbar.updateTabStop();
				// Tree order is always by name (see listview.doRefresh/resort), so a
				// field/direction change here has no visible effect on it - skip the
				// rebuild rather than pay for one that changes nothing on screen.
				if (!state.prefs.tree_mode) listview.resort();
				// No settings.save() here: this fires on every arrow-key repeat or
				// click, and save() rewrites every column's desc/visible bit to the
				// INI unconditionally (~230ms, measured - by far the largest single
				// cost in this handler). WM_DESTROY saves the final state on exit,
				// same as every other transient UI interaction in this file.
				break;
			}
		}
	}
	return 0;
}

fn handleContextMenu(hwnd: win32.HWND, wp: win32.WPARAM, lp: win32.LPARAM) win32.LRESULT {
	const src_hwnd: win32.HWND = @ptrFromInt(@as(usize, @bitCast(wp)));
	if (src_hwnd == state.hwnd_tree) {
		var point = pointFromLparam(lp);
		var sel: win32.HTREEITEM = null;
		if (point.x == -1 and point.y == -1) {
			// Keyboard-triggered: use current selection
			sel = treeview.getSelection();
			if (sel != null) {
				var rc: win32.RECT align(8) = std.mem.zeroes(win32.RECT);
				@as(*win32.HTREEITEM, @ptrCast(@alignCast(&rc))).* = sel;
				if (win32.SendMessageW(state.hwnd_tree, win32.TVM_GETITEMRECT, 1, @bitCast(@intFromPtr(&rc))) != 0) {
					_ = win32.MapWindowPoints(state.hwnd_tree, win32.HWND_DESKTOP, @ptrCast(&rc), 2);
					point.x = rc.left;
					point.y = rc.bottom;
				}
			}
		} else {
			// Mouse-triggered: select item under cursor first
			var local = point;
			_ = win32.ScreenToClient(state.hwnd_tree, &local);
			var tvht: win32.TVHITTESTINFO = std.mem.zeroes(win32.TVHITTESTINFO);
			tvht.pt = local;
			const hit: win32.HTREEITEM = @ptrFromInt(@as(usize, @bitCast(win32.SendMessageW(state.hwnd_tree, win32.TVM_HITTEST, 0, @bitCast(@intFromPtr(&tvht))))));
			if (hit != null and (tvht.flags & win32.TVHT_ONITEM) != 0)
				_ = win32.SendMessageW(state.hwnd_tree, win32.TVM_SELECTITEM, win32.TVGN_CARET, @bitCast(@intFromPtr(hit)));
			sel = treeview.getSelection();
		}
		if (sel != null) {
			const pid = treeview.getSelectedPid();
			showProcessContextMenu(hwnd, pid, point, true);
		}
		return 0;
	}
	if (src_hwnd == state.hwnd_list) {
		const selected = listview.getSelectedIndex();
		if (selected != -1) {
			const pid = listview.getItemPid(selected);
			var point = pointFromLparam(lp);
			if (point.x == -1 and point.y == -1) {
				var rc: win32.RECT = std.mem.zeroes(win32.RECT);
				rc.left = win32.LVIR_BOUNDS;
				_ = win32.SendMessageW(state.hwnd_list, win32.LVM_GETITEMRECT, @intCast(selected), @bitCast(@intFromPtr(&rc)));
				_ = win32.MapWindowPoints(state.hwnd_list, win32.HWND_DESKTOP, @ptrCast(&rc), 2);
				point.x = rc.left + @divTrunc(rc.right - rc.left, 2);
				point.y = rc.top + @divTrunc(rc.bottom - rc.top, 2);
			}
			showProcessContextMenu(hwnd, pid, point, false);
		}
	}
	return 0;
}

pub fn wndProc(hwnd: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM) callconv(.c) win32.LRESULT {
	switch (msg) {
		win32.WM_ACTIVATE => {
			const low: u16 = @truncate(wp);
			if (low == win32.WA_INACTIVE) {
				last_focus = win32.GetFocus();
			} else {
				_ = win32.SetFocus(if (last_focus != null) last_focus else if (state.prefs.tree_mode) state.hwnd_tree else state.hwnd_list);
			}
			return 0;
		},
		win32.WM_CREATE => {
			state.hwnd = hwnd;
			_ = win32.RegisterHotKey(hwnd, ID_HOTKEY_TOGGLE, win32.MOD_CONTROL | win32.MOD_SHIFT | win32.MOD_NOREPEAT, @intCast(win32.VK_OEM_3));
			var icc: win32.INITCOMMONCONTROLSEX = .{ .dwSize = @sizeOf(win32.INITCOMMONCONTROLSEX), .dwICC = win32.ICC_LISTVIEW_CLASSES | win32.ICC_BAR_CLASSES | win32.ICC_TREEVIEW_CLASSES };
			_ = win32.InitCommonControlsEx(&icc);
			state.hwnd_sort_group = sortbar.create(hwnd);
			// Hidden label: GW_HWNDPREV of the list view points here, so MSAA/UIA
			// use "Processes" as the list's accessible name instead of the group box.
			_ = win32.CreateWindowExW(0, L("STATIC"), L("Processes"), win32.WS_CHILD | win32.SS_LEFT, 0, 0, 0, 0, hwnd, null, win32.GetModuleHandleW(null), null);
			state.hwnd_list = win32.CreateWindowExW(0, win32.WC_LISTVIEWW, L("Processes"), win32.WS_CHILD | win32.WS_VISIBLE | win32.WS_TABSTOP | win32.LVS_REPORT | win32.LVS_SHOWSELALWAYS, 0, 1, 760, 537, hwnd, @ptrFromInt(@as(usize, ID_LISTVIEW)), win32.GetModuleHandleW(null), null);
			_ = win32.SetWindowSubclass(state.hwnd_list, listview.listKeyProc, 0, 0);
			_ = win32.SendMessageW(state.hwnd_list, win32.LVM_SETEXTENDEDLISTVIEWSTYLE, 0, win32.LVS_EX_FULLROWSELECT | win32.LVS_EX_GRIDLINES | win32.LVS_EX_HEADERDRAGDROP);
			state.hwnd_tree = win32.CreateWindowExW(0, win32.WC_TREEVIEWW, null, win32.WS_CHILD | win32.WS_TABSTOP | win32.TVS_HASLINES | win32.TVS_HASBUTTONS | win32.TVS_LINESATROOT | win32.TVS_SHOWSELALWAYS, 0, 1, 760, 537, hwnd, @ptrFromInt(@as(usize, ID_TREEVIEW)), win32.GetModuleHandleW(null), null);
			_ = win32.SetWindowSubclass(state.hwnd_tree, treeview.keyProc, 0, 0);
			_ = win32.SendMessageW(state.hwnd_tree, win32.TVM_SETEXTENDEDSTYLE, win32.TVS_EX_DOUBLEBUFFER, win32.TVS_EX_DOUBLEBUFFER);
			state.hwnd_status = win32.CreateWindowExW(0, win32.STATUSCLASSNAMEW, null, win32.WS_CHILD | win32.WS_VISIBLE, 0, 0, 0, 0, hwnd, null, win32.GetModuleHandleW(null), null);
			settings.load(&state.prefs);
			theme.update();
			sortbar.applyColumns();
			theme.applyTitlebar(hwnd);
			theme.applyListview(state.hwnd_list);
			theme.applyTreeview(state.hwnd_tree);
			_ = win32.SetWindowTheme(state.hwnd_status, if (theme.isDark() != 0) L("DarkMode_Explorer") else L("Explorer"), null);
			if (state.prefs.tree_mode) {
				_ = win32.ShowWindow(state.hwnd_list, win32.SW_HIDE);
				_ = win32.ShowWindow(state.hwnd_tree, win32.SW_SHOW);
			}
			createMenuBar(hwnd);
			tray.add(hwnd, WM_TRAYICON, &WINDOW_TITLE);
			if (state.prefs.always_on_top)
				_ = win32.SetWindowPos(hwnd, win32.HWND_TOPMOST, 0, 0, 0, 0, win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOACTIVATE);
			if (state.prefs.window_width > 0) {
				const point = win32.POINT{ .x = state.prefs.window_left + 50, .y = state.prefs.window_top + 50 };
				if (win32.MonitorFromPoint(point, win32.MONITOR_DEFAULTTONULL) != null)
					_ = win32.SetWindowPos(hwnd, null, state.prefs.window_left, state.prefs.window_top, state.prefs.window_width, state.prefs.window_height, win32.SWP_NOZORDER | win32.SWP_NOACTIVATE);
			}
			// Prime the snapshot table so the first real refresh has deltas to work from.
			// Discard results: the list stays empty until ID_PRIME_TIMER fires with accurate CPU.
			{
				var count: i32 = 0;
				const primed = process.snapshotProcesses(&state.snapshots, &count, state.prefs.field, state.prefs.desc[@intCast(@intFromEnum(state.prefs.field))]);
				if (primed) |pr| process.freeProcessEntries(pr);
			}
			_ = win32.SetTimer(hwnd, ID_PRIME_TIMER, 250, null);
			setRefreshInterval(hwnd, state.prefs.refresh_ms);
			// Skip when starting minimized: SetFocus on a hidden window can still activate
			// it, stealing foreground from whatever the user was doing. WM_ACTIVATE already
			// assigns focus (falling back to state.hwnd_list/state.hwnd_tree) once the window is
			// actually shown via tray.restore().
			if (!state.prefs.start_minimized_to_tray)
				_ = win32.SetFocus(state.hwnd_list);
			return 0;
		},
		win32.WM_SIZE => {
			if (state.hwnd_list != null and state.hwnd_status != null) {
				const ulp: usize = @bitCast(lp);
				const w: i32 = @intCast(@as(u16, @truncate(ulp)));
				const h: i32 = @intCast(@as(u16, @truncate(ulp >> 16)));
				_ = win32.SendMessageW(state.hwnd_status, win32.WM_SIZE, wp, lp);
				var sr: win32.RECT = undefined;
				_ = win32.GetClientRect(state.hwnd_status, &sr);
				const view_h = h - 1 - (sr.bottom - sr.top);
				_ = win32.SetWindowPos(state.hwnd_list, null, 0, 1, w, view_h, win32.SWP_NOZORDER | win32.SWP_NOACTIVATE);
				if (state.hwnd_tree != null)
					_ = win32.SetWindowPos(state.hwnd_tree, null, 0, 1, w, view_h, win32.SWP_NOZORDER | win32.SWP_NOACTIVATE);
			}
			return 0;
		},
		WM_HIDE_TO_TRAY => {
			_ = win32.ShowWindow(hwnd, win32.SW_HIDE);
			return 0;
		},
		WM_TRAYICON => {
			if (lp == win32.WM_LBUTTONUP) {
				tray.restore();
			} else if (lp == win32.WM_RBUTTONUP) {
				const menu = win32.CreatePopupMenu();
				_ = win32.AppendMenuW(menu, win32.MF_STRING, ID_TRAY_RESTORE, L("Restore"));
				_ = win32.AppendMenuW(menu, win32.MF_STRING, ID_TRAY_EXIT, L("Exit"));
				var point: win32.POINT = undefined;
				_ = win32.GetCursorPos(&point);
				_ = win32.SetForegroundWindow(hwnd);
				_ = win32.TrackPopupMenu(menu, win32.TPM_RIGHTBUTTON, point.x, point.y, 0, hwnd, null);
				_ = win32.PostMessageW(hwnd, win32.WM_NULL, 0, 0);
				_ = win32.DestroyMenu(menu);
			}
			return 0;
		},
		win32.WM_COMMAND => return handleCommand(hwnd, wp),
		win32.WM_CONTEXTMENU => return handleContextMenu(hwnd, wp, lp),
		win32.WM_NOTIFY => {
			const hdr: *const win32.NMHDR = @ptrFromInt(@as(usize, @bitCast(lp)));
			if (hdr.idFrom == ID_LISTVIEW and hdr.code == @as(win32.UINT, @bitCast(win32.LVN_COLUMNCLICK))) {
				const nmlv: *const win32.NMLISTVIEW = @ptrFromInt(@as(usize, @bitCast(lp)));
				const col = nmlv.iSubItem;
				if (col >= 0 and col < state.sort_btn_count) {
					const cid: usize = @intCast(state.sort_btn_cols[@intCast(col)]);
					if (settings.COLUMNS[cid].field == state.prefs.field) {
						const fi: usize = @intCast(@intFromEnum(state.prefs.field));
						state.prefs.desc[fi] = !state.prefs.desc[fi];
					} else {
						state.prefs.field = settings.COLUMNS[cid].field;
					}
					sortbar.updateSortUi();
					sortbar.updateTabStop();
					// A column header is only clickable while the listview itself is
					// visible, i.e. never in tree mode, so no tree_mode guard is needed
					// here the way there is at the sort-button handler above. No
					// settings.save() either, for the same reason as that handler.
					listview.resort();
				}
			}
			return win32.DefWindowProcW(hwnd, msg, wp, lp);
		},
		win32.WM_TIMER => {
			if (wp == ID_PRIME_TIMER) {
				_ = win32.KillTimer(hwnd, ID_PRIME_TIMER);
				listview.doRefresh();
				return 0;
			}
			if (wp == ID_REFRESH_TIMER) {
				listview.doRefresh();
				return 0;
			}
		},
		win32.WM_HOTKEY => {
			if (wp == ID_HOTKEY_TOGGLE) {
				if (win32.IsWindowVisible(hwnd) == 0) {
					tray.restore();
				} else if (win32.GetForegroundWindow() != hwnd) {
					_ = win32.SetForegroundWindow(hwnd);
				} else {
					_ = win32.PostMessageW(hwnd, WM_HIDE_TO_TRAY, 0, 0);
				}
			}
			return 0;
		},
		win32.WM_SETTINGCHANGE => {
			if (lp != 0) {
				const s: win32.LPCWSTR = @ptrFromInt(@as(usize, @bitCast(lp)));
				if (win32.lstrcmpW(s, L("ImmersiveColorSet")) == 0) {
					theme.update();
					theme.applyTitlebar(hwnd);
					theme.applyListview(state.hwnd_list);
					theme.applyTreeview(state.hwnd_tree);
					_ = win32.SetWindowTheme(state.hwnd_status, if (theme.isDark() != 0) L("DarkMode_Explorer") else L("Explorer"), null);
					sortbar.applyTheme();
					_ = win32.RedrawWindow(hwnd, null, null, win32.RDW_INVALIDATE | win32.RDW_ERASE | win32.RDW_ALLCHILDREN);
				}
			}
			return 0;
		},
		win32.WM_ERASEBKGND => {
			const br = theme.bgBrush();
			if (br != null) {
				var rc: win32.RECT = undefined;
				_ = win32.GetClientRect(hwnd, &rc);
				_ = win32.FillRect(@ptrFromInt(@as(usize, @bitCast(wp))), &rc, br);
				return 1;
			}
		},
		win32.WM_CTLCOLORSTATIC, win32.WM_CTLCOLORBTN => {
			const br = theme.ctlColor(@ptrFromInt(@as(usize, @bitCast(wp))));
			if (br != null) return @bitCast(@intFromPtr(br));
		},
		win32.WM_DESTROY => {
			var wpl: win32.WINDOWPLACEMENT = std.mem.zeroes(win32.WINDOWPLACEMENT);
			wpl.length = @sizeOf(win32.WINDOWPLACEMENT);
			_ = win32.GetWindowPlacement(hwnd, &wpl);
			state.prefs.window_left = wpl.rcNormalPosition.left;
			state.prefs.window_top = wpl.rcNormalPosition.top;
			state.prefs.window_width = wpl.rcNormalPosition.right - wpl.rcNormalPosition.left;
			state.prefs.window_height = wpl.rcNormalPosition.bottom - wpl.rcNormalPosition.top;
			settings.save(&state.prefs);
			_ = win32.UnregisterHotKey(hwnd, ID_HOTKEY_TOGGLE);
			_ = win32.KillTimer(hwnd, ID_REFRESH_TIMER);
			tray.remove();
			process.gpuCleanup();
			win32.PostQuitMessage(0);
			return 0;
		},
		else => {},
	}
	return win32.DefWindowProcW(hwnd, msg, wp, lp);
}
