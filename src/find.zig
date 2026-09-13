const std = @import("std");
const win32 = @import("win32.zig");
const resource = @import("resource.zig");
const services = @import("services.zig");
const state = @import("state.zig");
const theme = @import("theme.zig");
const wfmt = @import("wfmt.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

pub const QUERY_LEN = 128;
const TEXT_LEN = 300;
// Deep enough for the process tree on any machine that can still run; a tree
// larger than this simply stops being searchable past the cap rather than
// overrunning anything.
const MAX_TREE_ITEMS = 4096;

var query: [QUERY_LEN:0]u16 = std.mem.zeroes([QUERY_LEN:0]u16);

pub fn hasQuery() bool {
	return query[0] != 0;
}

fn matches(text: [*:0]const u16) bool {
	return win32.StrStrIW(text, &query) != null;
}

fn listItemText(lv: win32.HWND, item: i32, subitem: i32, buf: [*:0]u16) void {
	buf[0] = 0;
	var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
	lvi.iSubItem = subitem;
	lvi.pszText = buf;
	lvi.cchTextMax = TEXT_LEN;
	_ = win32.SendMessageW(lv, win32.LVM_GETITEMTEXTW, @intCast(item), @bitCast(@intFromPtr(&lvi)));
}

fn selectListItem(lv: win32.HWND, item: i32) void {
	var clear: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
	clear.stateMask = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
	_ = win32.SendMessageW(lv, win32.LVM_SETITEMSTATE, @bitCast(@as(isize, -1)), @bitCast(@intFromPtr(&clear)));
	var set: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
	set.stateMask = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
	set.state = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
	_ = win32.SendMessageW(lv, win32.LVM_SETITEMSTATE, @intCast(item), @bitCast(@intFromPtr(&set)));
	_ = win32.SendMessageW(lv, win32.LVM_ENSUREVISIBLE, @intCast(item), 0);
	_ = win32.SetFocus(lv);
}

// Walks out from the current selection and wraps, so repeated F3 cycles the
// whole list and stops where it started. subitem_count covers the services
// list, where the display name is what people actually recognise.
fn searchListview(lv: win32.HWND, subitem_count: i32, forward: bool) bool {
	const total: i32 = @intCast(win32.SendMessageW(lv, win32.LVM_GETITEMCOUNT, 0, 0));
	if (total == 0) return false;
	const current: i32 = @intCast(win32.SendMessageW(lv, win32.LVM_GETNEXTITEM, @bitCast(@as(isize, -1)), win32.LVNI_SELECTED));
	const from = if (current < 0) (if (forward) total - 1 else 0) else current;
	var step: i32 = 1;
	while (step <= total) : (step += 1) {
		const offset = if (forward) step else -step;
		const idx = @mod(from + offset + total * total, total);
		var buf: [TEXT_LEN:0]u16 = std.mem.zeroes([TEXT_LEN:0]u16);
		var sub: i32 = 0;
		while (sub < subitem_count) : (sub += 1) {
			listItemText(lv, idx, sub, &buf);
			if (buf[0] != 0 and matches(&buf)) {
				selectListItem(lv, idx);
				return true;
			}
		}
	}
	return false;
}

var tree_items: [MAX_TREE_ITEMS]win32.HTREEITEM = std.mem.zeroes([MAX_TREE_ITEMS]win32.HTREEITEM);
var tree_count: usize = 0;

fn treeNext(item: win32.HTREEITEM, flag: win32.WPARAM) win32.HTREEITEM {
	const r = win32.SendMessageW(state.hwnd_tree, win32.TVM_GETNEXTITEM, flag, @bitCast(@intFromPtr(item)));
	return @ptrFromInt(@as(usize, @bitCast(r)));
}

// Depth first, which is the order the tree reads top to bottom. Collapsed
// branches are included: TVM_ENSUREVISIBLE expands whatever it needs to reveal
// a hit, so a match cannot hide inside a folded-up parent.
fn collectTree(item_in: win32.HTREEITEM) void {
	var item = item_in;
	while (item != null and tree_count < MAX_TREE_ITEMS) {
		tree_items[tree_count] = item;
		tree_count += 1;
		collectTree(treeNext(item, win32.TVGN_CHILD));
		item = treeNext(item, win32.TVGN_NEXT);
	}
}

fn searchTree(forward: bool) bool {
	tree_count = 0;
	collectTree(treeNext(null, win32.TVGN_ROOT));
	if (tree_count == 0) return false;
	const total: i32 = @intCast(tree_count);
	const selected = treeNext(null, win32.TVGN_CARET);
	var from: i32 = if (forward) total - 1 else 0;
	for (0..tree_count) |i| {
		if (tree_items[i] == selected) {
			from = @intCast(i);
			break;
		}
	}
	var step: i32 = 1;
	while (step <= total) : (step += 1) {
		const offset = if (forward) step else -step;
		const idx = @mod(from + offset + total * total, total);
		var buf: [TEXT_LEN:0]u16 = std.mem.zeroes([TEXT_LEN:0]u16);
		var tvi: win32.TVITEMW = std.mem.zeroes(win32.TVITEMW);
		tvi.mask = win32.TVIF_TEXT;
		tvi.hItem = tree_items[@intCast(idx)];
		tvi.pszText = &buf;
		tvi.cchTextMax = TEXT_LEN;
		if (win32.SendMessageW(state.hwnd_tree, win32.TVM_GETITEMW, 0, @bitCast(@intFromPtr(&tvi))) != 0 and matches(&buf)) {
			_ = win32.SendMessageW(state.hwnd_tree, win32.TVM_SELECTITEM, win32.TVGN_CARET, @bitCast(@intFromPtr(tree_items[@intCast(idx)])));
			_ = win32.SendMessageW(state.hwnd_tree, win32.TVM_ENSUREVISIBLE, 0, @bitCast(@intFromPtr(tree_items[@intCast(idx)])));
			_ = win32.SetFocus(state.hwnd_tree);
			return true;
		}
	}
	return false;
}

fn notFound(parent: win32.HWND) void {
	var text: [QUERY_LEN + 64:0]u16 = std.mem.zeroes([QUERY_LEN + 64:0]u16);
	wfmt.format(&text, QUERY_LEN + 64, "Cannot find \"%s\".", .{@as(win32.LPCWSTR, &query)});
	_ = win32.MessageBoxW(parent, &text, L("Find"), win32.MB_ICONINFORMATION);
}

/// Searches the tab that is showing. Silent when no search text has been
/// entered yet, so a stray F3 does nothing rather than complaining.
pub fn findNext(parent: win32.HWND, forward: bool) void {
	if (!hasQuery()) return;
	const found = if (state.active_tab == 1)
		searchListview(state.hwnd_svc_list, 2, forward)
	else if (state.prefs.tree_mode)
		searchTree(forward)
	else
		searchListview(state.hwnd_list, 1, forward);
	if (!found) notFound(parent);
}

fn findDlgProc(hdlg: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM) callconv(.c) win32.INT_PTR {
	_ = lp;
	switch (msg) {
		win32.WM_INITDIALOG => {
			theme.applyTitlebar(hdlg);
			_ = win32.SendDlgItemMessageW(hdlg, resource.IDC_FIND_EDIT, win32.EM_SETLIMITTEXT, QUERY_LEN - 1, 0);
			_ = win32.SetDlgItemTextW(hdlg, resource.IDC_FIND_EDIT, &query);
			_ = win32.SendDlgItemMessageW(hdlg, resource.IDC_FIND_EDIT, win32.EM_SETSEL, 0, -1);
			_ = win32.EnableWindow(win32.GetDlgItem(hdlg, win32.IDOK), if (hasQuery()) 1 else 0);
			return 1;
		},
		win32.WM_COMMAND => {
			const low: u16 = @truncate(wp);
			const high: u16 = @truncate(wp >> 16);
			if (low == resource.IDC_FIND_EDIT and high == @as(u16, win32.EN_CHANGE)) {
				const has_text = win32.GetWindowTextLengthW(win32.GetDlgItem(hdlg, resource.IDC_FIND_EDIT)) > 0;
				_ = win32.EnableWindow(win32.GetDlgItem(hdlg, win32.IDOK), if (has_text) 1 else 0);
				return 1;
			}
			if (low == win32.IDOK) {
				_ = win32.GetDlgItemTextW(hdlg, resource.IDC_FIND_EDIT, &query, QUERY_LEN);
				_ = win32.EndDialog(hdlg, 1);
				return 1;
			}
			if (low == win32.IDCANCEL) {
				_ = win32.EndDialog(hdlg, 0);
				return 1;
			}
		},
		win32.WM_CTLCOLORDLG => {
			const br = theme.bgBrush();
			if (br != null) return @bitCast(@intFromPtr(br));
		},
		win32.WM_CTLCOLORSTATIC, win32.WM_CTLCOLORBTN, win32.WM_CTLCOLOREDIT => {
			const br = theme.ctlColor(@ptrFromInt(@as(usize, @bitCast(wp))));
			if (br != null) return @bitCast(@intFromPtr(br));
		},
		else => {},
	}
	return 0;
}

pub fn openDialog(parent: win32.HWND) void {
	if (win32.DialogBoxParamW(win32.GetModuleHandleW(null), @ptrFromInt(resource.IDD_FIND), parent, findDlgProc, 0) != 0)
		findNext(parent, true);
}
