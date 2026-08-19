const std = @import("std");
const win32 = @import("win32.zig");
const resource = @import("resource.zig");
const settings = @import("settings.zig");
const theme = @import("theme.zig");
const listview = @import("listview.zig");
const state = @import("state.zig");
const wfmt = @import("wfmt.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

const WM_HIDE_TO_TRAY: win32.UINT = win32.WM_APP + 2;

fn sortGroupProc(hwnd: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM, id: win32.UINT_PTR, data: win32.DWORD_PTR) callconv(.c) win32.LRESULT {
	_ = id;
	_ = data;
	if (msg == win32.WM_COMMAND) return win32.SendMessageW(state.hwnd, msg, wp, lp);
	if (msg == win32.WM_CTLCOLORBTN or msg == win32.WM_CTLCOLORSTATIC) {
		const r = win32.SendMessageW(state.hwnd, msg, wp, lp);
		if (r != 0) return r;
	}
	return win32.DefSubclassProc(hwnd, msg, wp, lp);
}

fn sortBtnProc(hwnd: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM, id: win32.UINT_PTR, data: win32.DWORD_PTR) callconv(.c) win32.LRESULT {
	_ = id;
	_ = data;
	if (msg == win32.WM_GETDLGCODE) {
		var r = win32.DefSubclassProc(hwnd, msg, wp, lp) | win32.DLGC_WANTARROWS;
		const pmsg: ?*win32.MSG = @ptrFromInt(@as(usize, @bitCast(lp)));
		if (pmsg) |m| {
			if ((m.message == win32.WM_KEYDOWN and m.wParam == win32.VK_RETURN) or (m.message == win32.WM_CHAR and m.wParam == '\r')) r |= win32.DLGC_WANTMESSAGE;
		}
		return r;
	}
	if (msg == win32.WM_CHAR and wp == '\r') return 0;
	if (msg == win32.WM_KEYDOWN) {
		if (wp == win32.VK_ESCAPE) {
			_ = win32.PostMessageW(state.hwnd, WM_HIDE_TO_TRAY, 0, 0);
			return 0;
		}
		if (wp == win32.VK_RETURN) {
			const ctrl_id: win32.WPARAM = @intCast(win32.GetDlgCtrlID(hwnd));
			_ = win32.PostMessageW(state.hwnd, win32.WM_COMMAND, ctrl_id, @bitCast(@intFromPtr(hwnd)));
			return 0;
		}
		if (wp == win32.VK_LEFT or wp == win32.VK_RIGHT) {
			var idx: i32 = -1;
			var i: i32 = 0;
			while (i < state.sort_btn_count) : (i += 1) {
				if (state.sort_btns[@intCast(i)] == hwnd) {
					idx = i;
					break;
				}
			}
			if (idx >= 0) {
				const next: i32 = if (wp == win32.VK_RIGHT) idx + 1 else idx - 1;
				if (next < 0 or next >= state.sort_btn_count) return 0;
				const cid: usize = @intCast(state.sort_btn_cols[@intCast(next)]);
				state.prefs.field = settings.COLUMNS[cid].field;
				var buf: [64:0]u16 = std.mem.zeroes([64:0]u16);
				const fi: usize = @intCast(@intFromEnum(state.prefs.field));
				wfmt.format(&buf, 64, "%s (%s)", .{ settings.COLUMNS[cid].label, if (state.prefs.desc[fi]) @as(win32.LPCWSTR, L("descending")) else @as(win32.LPCWSTR, L("ascending")) });
				_ = win32.SetWindowTextW(state.sort_btns[@intCast(next)], &buf);
				_ = win32.SendMessageW(state.sort_btns[@intCast(next)], win32.BM_SETCHECK, win32.BST_CHECKED, 0);
				updateTabStop();
				_ = win32.SetFocus(state.sort_btns[@intCast(next)]);
				updateSortUi();
				// Tree order is always by name, so this has no visible effect while
				// the tree is showing - skip the rebuild (see the identical guard on
				// the sort-button click handler in wndproc.zig).
				if (!state.prefs.tree_mode) listview.resort();
				return 0;
			}
		}
		if (wp == win32.VK_UP or wp == win32.VK_DOWN) return 0;
	}
	return win32.DefSubclassProc(hwnd, msg, wp, lp);
}

pub fn updateTabStop() void {
	var i: i32 = 0;
	while (i < state.sort_btn_count) : (i += 1) {
		const idx: usize = @intCast(i);
		var style = win32.GetWindowLongPtrW(state.sort_btns[idx], win32.GWL_STYLE);
		const cid: usize = @intCast(state.sort_btn_cols[idx]);
		style = if (settings.COLUMNS[cid].field == state.prefs.field)
			style | @as(win32.LONG_PTR, win32.WS_TABSTOP)
		else
			style & ~@as(win32.LONG_PTR, win32.WS_TABSTOP);
		_ = win32.SetWindowLongPtrW(state.sort_btns[idx], win32.GWL_STYLE, style);
	}
}

pub fn updateSortUi() void {
	var i: i32 = 0;
	while (i < state.sort_btn_count) : (i += 1) {
		const idx: usize = @intCast(i);
		const cid: usize = @intCast(state.sort_btn_cols[idx]);
		const active = settings.COLUMNS[cid].field == state.prefs.field;
		var buf: [64:0]u16 = std.mem.zeroes([64:0]u16);
		if (active) {
			const fi: usize = @intCast(@intFromEnum(state.prefs.field));
			wfmt.format(&buf, 64, "%s (%s)", .{ settings.COLUMNS[cid].label, if (state.prefs.desc[fi]) @as(win32.LPCWSTR, L("descending")) else @as(win32.LPCWSTR, L("ascending")) });
		} else {
			_ = win32.lstrcpyW(&buf, settings.COLUMNS[cid].label);
		}
		_ = win32.SetWindowTextW(state.sort_btns[idx], &buf);
		_ = win32.SendMessageW(state.sort_btns[idx], win32.BM_SETCHECK, if (active) win32.BST_CHECKED else win32.BST_UNCHECKED, 0);
	}
	const header = win32.SendMessageW(state.hwnd_list, win32.LVM_GETHEADER, 0, 0);
	const header_hwnd: win32.HWND = @ptrFromInt(@as(usize, @bitCast(header)));
	i = 0;
	while (i < state.sort_btn_count) : (i += 1) {
		const idx: usize = @intCast(i);
		const cid: usize = @intCast(state.sort_btn_cols[idx]);
		var hdi: win32.HDITEMW = std.mem.zeroes(win32.HDITEMW);
		hdi.mask = win32.HDI_FORMAT;
		_ = win32.SendMessageW(header_hwnd, win32.HDM_GETITEMW, @intCast(i), @bitCast(@intFromPtr(&hdi)));
		hdi.fmt &= ~(win32.HDF_SORTUP | win32.HDF_SORTDOWN);
		if (settings.COLUMNS[cid].field == state.prefs.field) {
			const fi: usize = @intCast(@intFromEnum(state.prefs.field));
			hdi.fmt |= if (state.prefs.desc[fi]) win32.HDF_SORTDOWN else win32.HDF_SORTUP;
		}
		_ = win32.SendMessageW(header_hwnd, win32.HDM_SETITEMW, @intCast(i), @bitCast(@intFromPtr(&hdi)));
	}
}

pub fn applyColumns() void {
	var i: i32 = 0;
	while (i < state.sort_btn_count) : (i += 1) {
		const idx: usize = @intCast(i);
		_ = win32.DestroyWindow(state.sort_btns[idx]);
		state.sort_btns[idx] = null;
	}
	state.sort_btn_count = 0;

	const header = win32.SendMessageW(state.hwnd_list, win32.LVM_GETHEADER, 0, 0);
	const header_hwnd: win32.HWND = @ptrFromInt(@as(usize, @bitCast(header)));
	const lv_cols: i32 = @intCast(win32.SendMessageW(header_hwnd, win32.HDM_GETITEMCOUNT, 0, 0));
	i = lv_cols - 1;
	while (i >= 0) : (i -= 1) _ = win32.SendMessageW(state.hwnd_list, win32.LVM_DELETECOLUMN, @intCast(i), 0);

	const field_idx: usize = @intCast(@intFromEnum(state.prefs.field));
	if (!state.prefs.visible[field_idx]) state.prefs.field = .name;

	var btn_x: i32 = 0;
	var lv_col: i32 = 0;
	i = 0;
	while (i < settings.COL_COUNT) : (i += 1) {
		const ci: usize = @intCast(i);
		if (!state.prefs.visible[ci]) continue;
		const bi: usize = @intCast(state.sort_btn_count);
		state.sort_btns[bi] = win32.CreateWindowExW(0, L("BUTTON"), settings.COLUMNS[ci].label, win32.WS_CHILD | win32.WS_VISIBLE | win32.BS_RADIOBUTTON, btn_x, 0, settings.COLUMNS[ci].width, 1, state.hwnd_sort_group, @ptrFromInt(@as(usize, @intCast(resource.ID_SORT_BASE + i))), win32.GetModuleHandleW(null), null);
		_ = win32.SetWindowSubclass(state.sort_btns[bi], sortBtnProc, @intCast(state.sort_btn_count), 0);
		state.sort_btn_cols[bi] = @intCast(i);
		btn_x += settings.COLUMNS[ci].width;
		state.sort_btn_count += 1;
		var lvc: win32.LVCOLUMNW = std.mem.zeroes(win32.LVCOLUMNW);
		lvc.mask = win32.LVCF_TEXT | win32.LVCF_WIDTH | win32.LVCF_SUBITEM;
		lvc.pszText = @constCast(settings.COLUMNS[ci].header);
		lvc.cx = settings.COLUMNS[ci].width;
		lvc.iSubItem = lv_col;
		_ = win32.SendMessageW(state.hwnd_list, win32.LVM_INSERTCOLUMNW, @intCast(lv_col), @bitCast(@intFromPtr(&lvc)));
		lv_col += 1;
	}
	_ = win32.SetWindowPos(state.hwnd_sort_group, null, 0, 0, btn_x, 1, win32.SWP_NOMOVE | win32.SWP_NOZORDER | win32.SWP_NOACTIVATE);
	updateSortUi();
	updateTabStop();
	applyTheme();
}

pub fn applyTheme() void {
	theme.applyButton(state.hwnd_sort_group);
	var i: i32 = 0;
	while (i < state.sort_btn_count) : (i += 1) theme.applyButton(state.sort_btns[@intCast(i)]);
}

pub fn create(parent: win32.HWND) win32.HWND {
	const group = win32.CreateWindowExW(win32.WS_EX_CONTROLPARENT, L("BUTTON"), L("Sort by"), win32.WS_CHILD | win32.WS_VISIBLE | win32.BS_GROUPBOX, 0, 0, 0, 1, parent, null, win32.GetModuleHandleW(null), null);
	_ = win32.SetWindowSubclass(group, sortGroupProc, 0, 0);
	return group;
}
