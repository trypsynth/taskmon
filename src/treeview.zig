const std = @import("std");
const win32 = @import("win32.zig");
const pt = @import("process_types.zig");
const tray = @import("tray.zig");
const process = @import("process.zig");
const state = @import("state.zig");

const WM_HIDE_TO_TRAY: win32.UINT = win32.WM_APP + 2;
const MAX_EXPANDED = 512;

fn tvGetItem(tvi: *win32.TVITEMW) void {
	_ = win32.SendMessageW(state.hwnd_tree, win32.TVM_GETITEMW, 0, @bitCast(@intFromPtr(tvi)));
}

fn tvInsertItem(tvis: *win32.TVINSERTSTRUCTW) win32.HTREEITEM {
	const r = win32.SendMessageW(state.hwnd_tree, win32.TVM_INSERTITEMW, 0, @bitCast(@intFromPtr(tvis)));
	return @ptrFromInt(@as(usize, @bitCast(r)));
}

fn tvGetChild(item: win32.HTREEITEM) win32.HTREEITEM {
	const r = win32.SendMessageW(state.hwnd_tree, win32.TVM_GETNEXTITEM, win32.TVGN_CHILD, @bitCast(@intFromPtr(item)));
	return @ptrFromInt(@as(usize, @bitCast(r)));
}

fn tvGetSibling(item: win32.HTREEITEM) win32.HTREEITEM {
	const r = win32.SendMessageW(state.hwnd_tree, win32.TVM_GETNEXTITEM, win32.TVGN_NEXT, @bitCast(@intFromPtr(item)));
	return @ptrFromInt(@as(usize, @bitCast(r)));
}

fn tvGetRoot() win32.HTREEITEM {
	const r = win32.SendMessageW(state.hwnd_tree, win32.TVM_GETNEXTITEM, win32.TVGN_ROOT, 0);
	return @ptrFromInt(@as(usize, @bitCast(r)));
}

fn tvGetSel() win32.HTREEITEM {
	const r = win32.SendMessageW(state.hwnd_tree, win32.TVM_GETNEXTITEM, win32.TVGN_CARET, 0);
	return @ptrFromInt(@as(usize, @bitCast(r)));
}

fn tvSelect(item: win32.HTREEITEM) void {
	_ = win32.SendMessageW(state.hwnd_tree, win32.TVM_SELECTITEM, win32.TVGN_CARET, @bitCast(@intFromPtr(item)));
}

fn tvEnsureVisible(item: win32.HTREEITEM) void {
	_ = win32.SendMessageW(state.hwnd_tree, win32.TVM_ENSUREVISIBLE, 0, @bitCast(@intFromPtr(item)));
}

fn tvExpand(item: win32.HTREEITEM, flag: win32.WPARAM) void {
	_ = win32.SendMessageW(state.hwnd_tree, win32.TVM_EXPAND, flag, @bitCast(@intFromPtr(item)));
}

fn tvDeleteAll() void {
	_ = win32.SendMessageW(state.hwnd_tree, win32.TVM_DELETEITEM, 0, @bitCast(@intFromPtr(win32.TVI_ROOT)));
}

var s_expanded_pids: [MAX_EXPANDED]win32.DWORD = std.mem.zeroes([MAX_EXPANDED]win32.DWORD);
var s_expanded_count: i32 = 0;
var s_selected_pid: win32.DWORD = 0;

fn collectState(item_in: win32.HTREEITEM) void {
	var item = item_in;
	while (item != null) {
		var tvi: win32.TVITEMW = std.mem.zeroes(win32.TVITEMW);
		tvi.mask = win32.TVIF_PARAM | win32.TVIF_STATE;
		tvi.hItem = item;
		tvi.stateMask = win32.TVIS_EXPANDED;
		tvGetItem(&tvi);
		if ((tvi.state & win32.TVIS_EXPANDED) != 0 and s_expanded_count < MAX_EXPANDED) {
			s_expanded_pids[@intCast(s_expanded_count)] = @intCast(tvi.lParam);
			s_expanded_count += 1;
		}
		collectState(tvGetChild(item));
		item = tvGetSibling(item);
	}
}

fn findByPid(item_in: win32.HTREEITEM, pid: win32.DWORD) win32.HTREEITEM {
	var item = item_in;
	while (item != null) {
		var tvi: win32.TVITEMW = std.mem.zeroes(win32.TVITEMW);
		tvi.mask = win32.TVIF_PARAM;
		tvi.hItem = item;
		tvGetItem(&tvi);
		if (@as(win32.DWORD, @intCast(tvi.lParam)) == pid) return item;
		const found = findByPid(tvGetChild(item), pid);
		if (found != null) return found;
		item = tvGetSibling(item);
	}
	return null;
}

fn restoreExpanded(item_in: win32.HTREEITEM) void {
	var item = item_in;
	while (item != null) {
		var tvi: win32.TVITEMW = std.mem.zeroes(win32.TVITEMW);
		tvi.mask = win32.TVIF_PARAM;
		tvi.hItem = item;
		tvGetItem(&tvi);
		for (0..@intCast(s_expanded_count)) |i| {
			if (s_expanded_pids[i] == @as(win32.DWORD, @intCast(tvi.lParam))) {
				tvExpand(item, win32.TVE_EXPAND);
				break;
			}
		}
		restoreExpanded(tvGetChild(item));
		item = tvGetSibling(item);
	}
}

// Windows recycles PIDs, so a matching parent PID is only really the parent if
// it also started no later than the child. Otherwise the true parent has exited
// and some unrelated process now holds its PID; nesting under it would be wrong.
fn isParentOf(parent: *const pt.ProcessEntry, child: *const pt.ProcessEntry) bool {
	return parent.pid == child.parent_pid and parent.start_time <= child.start_time;
}

fn hasLiveParent(child: *const pt.ProcessEntry, entries: [*]const pt.ProcessEntry, count: i32) bool {
	for (0..@intCast(count)) |i| {
		if (isParentOf(&entries[i], child)) return true;
	}
	return false;
}

fn insertChildren(parent: win32.HTREEITEM, parent_entry: *const pt.ProcessEntry, entries: [*]pt.ProcessEntry, count: i32, done: [*]win32.BOOL) void {
	for (0..@intCast(count)) |idx| {
		if (done[idx] != 0 or !isParentOf(parent_entry, &entries[idx])) continue;
		done[idx] = 1;
		var tvis: win32.TVINSERTSTRUCTW = std.mem.zeroes(win32.TVINSERTSTRUCTW);
		tvis.hParent = parent;
		tvis.hInsertAfter = win32.TVI_SORT;
		tvis.anon.item.mask = win32.TVIF_TEXT | win32.TVIF_PARAM;
		tvis.anon.item.pszText = @ptrCast(&entries[idx].name);
		tvis.anon.item.lParam = @intCast(entries[idx].pid);
		const hc = tvInsertItem(&tvis);
		if (hc != null) insertChildren(hc, &entries[idx], entries, count, done);
	}
}

fn insertRoot(e: *pt.ProcessEntry, entries: [*]pt.ProcessEntry, count: i32, done: [*]win32.BOOL) void {
	var tvis: win32.TVINSERTSTRUCTW = std.mem.zeroes(win32.TVINSERTSTRUCTW);
	tvis.hParent = win32.TVI_ROOT;
	tvis.hInsertAfter = win32.TVI_SORT;
	tvis.anon.item.mask = win32.TVIF_TEXT | win32.TVIF_PARAM;
	tvis.anon.item.pszText = @ptrCast(&e.name);
	tvis.anon.item.lParam = @intCast(e.pid);
	const hr = tvInsertItem(&tvis);
	if (hr != null) insertChildren(hr, e, entries, count, done);
}

pub fn populate(entries: [*]pt.ProcessEntry, count: i32) f64 {
	const old_sel = tvGetSel();
	s_selected_pid = 0;
	if (old_sel != null) {
		var tvi: win32.TVITEMW = std.mem.zeroes(win32.TVITEMW);
		tvi.mask = win32.TVIF_PARAM;
		tvi.hItem = old_sel;
		tvGetItem(&tvi);
		s_selected_pid = @intCast(tvi.lParam);
	}
	s_expanded_count = 0;
	collectState(tvGetRoot());

	_ = win32.SendMessageW(state.hwnd_tree, win32.WM_SETREDRAW, 0, 0);
	tvDeleteAll();

	const done_ptr = win32.HeapAlloc(win32.GetProcessHeap(), win32.HEAP_ZERO_MEMORY, @as(usize, @intCast(count)) * @sizeOf(win32.BOOL));
	if (done_ptr) |raw_done| {
		const done: [*]win32.BOOL = @ptrCast(@alignCast(raw_done));
		// Roots: parent is zero, self-referential, or already gone
		for (0..@intCast(count)) |idx| {
			if (done[idx] != 0) continue;
			const ppid = entries[idx].parent_pid;
			if (ppid == 0 or ppid == entries[idx].pid or !hasLiveParent(&entries[idx], entries, count)) {
				done[idx] = 1;
				insertRoot(&entries[idx], entries, count, done);
			}
		}
		// Orphaned/cycle entries become roots too
		for (0..@intCast(count)) |idx| {
			if (done[idx] == 0) {
				done[idx] = 1;
				insertRoot(&entries[idx], entries, count, done);
			}
		}
		_ = win32.HeapFree(win32.GetProcessHeap(), 0, raw_done);
	}

	restoreExpanded(tvGetRoot());

	const sel_item: win32.HTREEITEM = if (s_selected_pid != 0) findByPid(tvGetRoot(), s_selected_pid) else null;
	if (sel_item != null) {
		tvSelect(sel_item);
		tvEnsureVisible(sel_item);
	} else {
		const root = tvGetRoot();
		if (root != null) tvSelect(root);
	}

	_ = win32.SendMessageW(state.hwnd_tree, win32.WM_SETREDRAW, 1, 0);
	_ = win32.InvalidateRect(state.hwnd_tree, null, 0);

	var total: f64 = 0;
	for (0..@intCast(count)) |i| {
		if (entries[i].pid != 0) total += entries[i].cpu_percent;
	}
	tray.updateTip(total);
	return total;
}

// Terminates children bottom-up so parents outlive their children as briefly as possible
pub fn terminateFromItem(item: win32.HTREEITEM) void {
	if (item == null) return;
	var child = tvGetChild(item);
	while (child != null) {
		const next = tvGetSibling(child);
		terminateFromItem(child);
		child = next;
	}
	var tvi: win32.TVITEMW = std.mem.zeroes(win32.TVITEMW);
	tvi.mask = win32.TVIF_PARAM;
	tvi.hItem = item;
	tvGetItem(&tvi);
	_ = process.terminateProcess(@intCast(tvi.lParam));
}

pub fn keyProc(hwnd: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM, id: win32.UINT_PTR, data: win32.DWORD_PTR) callconv(.c) win32.LRESULT {
	_ = id;
	_ = data;
	if (msg == win32.WM_KEYDOWN and wp == win32.VK_ESCAPE) {
		_ = win32.PostMessageW(win32.GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0);
		return 0;
	}
	return win32.DefSubclassProc(hwnd, msg, wp, lp);
}

pub fn getSelectedPid() win32.DWORD {
	const sel = tvGetSel();
	if (sel == null) return 0;
	var tvi: win32.TVITEMW = std.mem.zeroes(win32.TVITEMW);
	tvi.mask = win32.TVIF_PARAM;
	tvi.hItem = sel;
	tvGetItem(&tvi);
	return @intCast(tvi.lParam);
}

pub fn getSelectedName(buf: [*:0]u16, cch: i32) void {
	buf[0] = 0;
	const sel = tvGetSel();
	if (sel == null) return;
	var tvi: win32.TVITEMW = std.mem.zeroes(win32.TVITEMW);
	tvi.mask = win32.TVIF_TEXT;
	tvi.hItem = sel;
	tvi.pszText = buf;
	tvi.cchTextMax = cch;
	tvGetItem(&tvi);
}

pub fn getSelection() win32.HTREEITEM {
	return tvGetSel();
}
