const std = @import("std");
const win32 = @import("win32.zig");
const resource = @import("resource.zig");
const settings = @import("settings.zig");
const theme = @import("theme.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

const WM_HIDE_TO_TRAY: win32.UINT = win32.WM_APP + 2;

extern var g_hwnd: win32.HWND;
extern var g_hwnd_list: win32.HWND;
extern var g_hwnd_sort_group: win32.HWND;
extern var g_sort_btns: [settings.COL_COUNT]win32.HWND;
extern var g_sort_btn_cols: [settings.COL_COUNT]i32;
extern var g_sort_btn_count: i32;
extern var g_prefs: settings.SortPrefs;

extern fn do_refresh() callconv(.c) void;

fn sortGroupProc(hwnd: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM, id: win32.UINT_PTR, data: win32.DWORD_PTR) callconv(.c) win32.LRESULT {
	_ = id;
	_ = data;
	if (msg == win32.WM_COMMAND) return win32.SendMessageW(g_hwnd, msg, wp, lp);
	if (msg == win32.WM_CTLCOLORBTN or msg == win32.WM_CTLCOLORSTATIC) {
		const r = win32.SendMessageW(g_hwnd, msg, wp, lp);
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
			_ = win32.PostMessageW(g_hwnd, WM_HIDE_TO_TRAY, 0, 0);
			return 0;
		}
		if (wp == win32.VK_RETURN) {
			const ctrl_id: win32.WPARAM = @intCast(win32.GetDlgCtrlID(hwnd));
			_ = win32.PostMessageW(g_hwnd, win32.WM_COMMAND, ctrl_id, @bitCast(@intFromPtr(hwnd)));
			return 0;
		}
		if (wp == win32.VK_LEFT or wp == win32.VK_RIGHT) {
			var idx: i32 = -1;
			var i: i32 = 0;
			while (i < g_sort_btn_count) : (i += 1) {
				if (g_sort_btns[@intCast(i)] == hwnd) {
					idx = i;
					break;
				}
			}
			if (idx >= 0) {
				const next: i32 = if (wp == win32.VK_RIGHT) idx + 1 else idx - 1;
				if (next < 0 or next >= g_sort_btn_count) return 0;
				const cid: usize = @intCast(g_sort_btn_cols[@intCast(next)]);
				g_prefs.field = settings.COLUMNS[cid].field;
				var buf: [64:0]u16 = std.mem.zeroes([64:0]u16);
				const fi: usize = @intCast(@intFromEnum(g_prefs.field));
				_ = win32.wnsprintfW(&buf, 64, L("%s (%s)"), settings.COLUMNS[cid].label, if (g_prefs.desc[fi] != 0) @as(win32.LPCWSTR, L("descending")) else @as(win32.LPCWSTR, L("ascending")));
				_ = win32.SetWindowTextW(g_sort_btns[@intCast(next)], &buf);
				_ = win32.SendMessageW(g_sort_btns[@intCast(next)], win32.BM_SETCHECK, win32.BST_CHECKED, 0);
				update_tab_stop();
				_ = win32.SetFocus(g_sort_btns[@intCast(next)]);
				update_sort_ui();
				do_refresh();
				settings.settings_save(&g_prefs);
				return 0;
			}
		}
		if (wp == win32.VK_UP or wp == win32.VK_DOWN) return 0;
	}
	return win32.DefSubclassProc(hwnd, msg, wp, lp);
}

pub export fn update_tab_stop() callconv(.c) void {
	var i: i32 = 0;
	while (i < g_sort_btn_count) : (i += 1) {
		const idx: usize = @intCast(i);
		var style = win32.GetWindowLongPtrW(g_sort_btns[idx], win32.GWL_STYLE);
		const cid: usize = @intCast(g_sort_btn_cols[idx]);
		style = if (settings.COLUMNS[cid].field == g_prefs.field)
			style | @as(win32.LONG_PTR, win32.WS_TABSTOP)
		else
			style & ~@as(win32.LONG_PTR, win32.WS_TABSTOP);
		_ = win32.SetWindowLongPtrW(g_sort_btns[idx], win32.GWL_STYLE, style);
	}
}

pub export fn update_sort_ui() callconv(.c) void {
	var i: i32 = 0;
	while (i < g_sort_btn_count) : (i += 1) {
		const idx: usize = @intCast(i);
		const cid: usize = @intCast(g_sort_btn_cols[idx]);
		const active = settings.COLUMNS[cid].field == g_prefs.field;
		var buf: [64:0]u16 = std.mem.zeroes([64:0]u16);
		if (active) {
			const fi: usize = @intCast(@intFromEnum(g_prefs.field));
			_ = win32.wnsprintfW(&buf, 64, L("%s (%s)"), settings.COLUMNS[cid].label, if (g_prefs.desc[fi] != 0) @as(win32.LPCWSTR, L("descending")) else @as(win32.LPCWSTR, L("ascending")));
		} else {
			_ = win32.lstrcpyW(&buf, settings.COLUMNS[cid].label);
		}
		_ = win32.SetWindowTextW(g_sort_btns[idx], &buf);
		_ = win32.SendMessageW(g_sort_btns[idx], win32.BM_SETCHECK, if (active) win32.BST_CHECKED else win32.BST_UNCHECKED, 0);
	}
	const header = win32.SendMessageW(g_hwnd_list, win32.LVM_GETHEADER, 0, 0);
	const header_hwnd: win32.HWND = @ptrFromInt(@as(usize, @bitCast(header)));
	i = 0;
	while (i < g_sort_btn_count) : (i += 1) {
		const idx: usize = @intCast(i);
		const cid: usize = @intCast(g_sort_btn_cols[idx]);
		var hdi: win32.HDITEMW = std.mem.zeroes(win32.HDITEMW);
		hdi.mask = win32.HDI_FORMAT;
		_ = win32.SendMessageW(header_hwnd, win32.HDM_GETITEMW, @intCast(i), @bitCast(@intFromPtr(&hdi)));
		hdi.fmt &= ~(win32.HDF_SORTUP | win32.HDF_SORTDOWN);
		if (settings.COLUMNS[cid].field == g_prefs.field) {
			const fi: usize = @intCast(@intFromEnum(g_prefs.field));
			hdi.fmt |= if (g_prefs.desc[fi] != 0) win32.HDF_SORTDOWN else win32.HDF_SORTUP;
		}
		_ = win32.SendMessageW(header_hwnd, win32.HDM_SETITEMW, @intCast(i), @bitCast(@intFromPtr(&hdi)));
	}
}

pub export fn apply_columns() callconv(.c) void {
	var i: i32 = 0;
	while (i < g_sort_btn_count) : (i += 1) {
		const idx: usize = @intCast(i);
		_ = win32.DestroyWindow(g_sort_btns[idx]);
		g_sort_btns[idx] = null;
	}
	g_sort_btn_count = 0;

	const header = win32.SendMessageW(g_hwnd_list, win32.LVM_GETHEADER, 0, 0);
	const header_hwnd: win32.HWND = @ptrFromInt(@as(usize, @bitCast(header)));
	const lv_cols: i32 = @intCast(win32.SendMessageW(header_hwnd, win32.HDM_GETITEMCOUNT, 0, 0));
	i = lv_cols - 1;
	while (i >= 0) : (i -= 1) _ = win32.SendMessageW(g_hwnd_list, win32.LVM_DELETECOLUMN, @intCast(i), 0);

	const field_idx: usize = @intCast(@intFromEnum(g_prefs.field));
	if (g_prefs.visible[field_idx] == 0) g_prefs.field = .SORT_FIELD_NAME;

	var btn_x: i32 = 0;
	var lv_col: i32 = 0;
	i = 0;
	while (i < settings.COL_COUNT) : (i += 1) {
		const ci: usize = @intCast(i);
		if (g_prefs.visible[ci] == 0) continue;
		const bi: usize = @intCast(g_sort_btn_count);
		g_sort_btns[bi] = win32.CreateWindowExW(0, L("BUTTON"), settings.COLUMNS[ci].label, win32.WS_CHILD | win32.WS_VISIBLE | win32.BS_RADIOBUTTON, btn_x, 0, settings.COLUMNS[ci].width, 1, g_hwnd_sort_group, @ptrFromInt(@as(usize, @intCast(resource.ID_SORT_BASE + i))), win32.GetModuleHandleW(null), null);
		_ = win32.SetWindowSubclass(g_sort_btns[bi], sortBtnProc, @intCast(g_sort_btn_count), 0);
		g_sort_btn_cols[bi] = @intCast(i);
		btn_x += settings.COLUMNS[ci].width;
		g_sort_btn_count += 1;
		var lvc: win32.LVCOLUMNW = std.mem.zeroes(win32.LVCOLUMNW);
		lvc.mask = win32.LVCF_TEXT | win32.LVCF_WIDTH | win32.LVCF_SUBITEM;
		lvc.pszText = @constCast(settings.COLUMNS[ci].header);
		lvc.cx = settings.COLUMNS[ci].width;
		lvc.iSubItem = lv_col;
		_ = win32.SendMessageW(g_hwnd_list, win32.LVM_INSERTCOLUMNW, @intCast(lv_col), @bitCast(@intFromPtr(&lvc)));
		lv_col += 1;
	}
	_ = win32.SetWindowPos(g_hwnd_sort_group, null, 0, 0, btn_x, 1, win32.SWP_NOMOVE | win32.SWP_NOZORDER | win32.SWP_NOACTIVATE);
	update_sort_ui();
	update_tab_stop();
	sortbar_apply_theme();
}

pub export fn sortbar_apply_theme() callconv(.c) void {
	theme.theme_apply_button(g_hwnd_sort_group);
	var i: i32 = 0;
	while (i < g_sort_btn_count) : (i += 1) theme.theme_apply_button(g_sort_btns[@intCast(i)]);
}

pub export fn sortbar_create(parent: win32.HWND) callconv(.c) win32.HWND {
	const group = win32.CreateWindowExW(win32.WS_EX_CONTROLPARENT, L("BUTTON"), L("Sort by"), win32.WS_CHILD | win32.WS_VISIBLE | win32.BS_GROUPBOX, 0, 0, 0, 1, parent, null, win32.GetModuleHandleW(null), null);
	_ = win32.SetWindowSubclass(group, sortGroupProc, 0, 0);
	return group;
}
