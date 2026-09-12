const std = @import("std");
const win32 = @import("win32.zig");
const resource = @import("resource.zig");
const theme = @import("theme.zig");
const wfmt = @import("wfmt.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

pub const SortField = enum(i32) {
	name,
	pid,
	cpu,
	memory,
	threads,
	handles,
	starttime,
	priority,
	disk_io,
	private_bytes,
	page_faults,
	user,
	cmdline,
	arch,
	session,
	peak_working_set,
	virtual_mem,
	gdi_objects,
	user_objects,
	integrity,
	ppid,
	private_ws,
	paged_pool,
	nonpaged_pool,
	io_read,
	io_write,
	io_other,
	description,
	company,
	dpi,
	service,
	gpu,
	gpu_memory,
	cpu_time,
	elevated,
	path,
	window_title,
	file_version,
	product_version,
	session_name,
	package_name,
	peak_virtual_mem,
	peak_private_bytes,
	peak_paged_pool,
	peak_nonpaged_pool,
	peak_threads,
	hard_faults,
	cycles,
	kernel_time,
	user_time,
	total_page_faults,
	io_read_ops,
	io_write_ops,
	io_other_ops,
	total_io,
	elapsed,
	shared_ws,
	parent_name,
	private_bytes_delta,
	working_set_delta,
	handle_delta,
	thread_delta,
	virtualization,
	app_container,
	domain,
	user_sid,
	efficiency,
	io_priority,
	page_priority,
	protection,
};

pub const ColumnDef = struct {
	label: win32.LPCWSTR,
	header: win32.LPCWSTR,
	width: i32,
	field: SortField,
	always_visible: bool,
	default_visible: bool,
};

pub const COL_COUNT: usize = 70;
const REFRESH_OPTION_COUNT = 5;

pub const COLUMNS: [COL_COUNT]ColumnDef = columns: {
	@setEvalBranchQuota(100_000);
	break :columns .{
		.{ .label = L("Name"), .header = L("Name"), .width = 260, .field = .name, .always_visible = true, .default_visible = true },
		.{ .label = L("PID"), .header = L("PID"), .width = 80, .field = .pid, .always_visible = false, .default_visible = true },
		.{ .label = L("CPU"), .header = L("CPU %"), .width = 90, .field = .cpu, .always_visible = false, .default_visible = true },
		.{ .label = L("Memory"), .header = L("Memory"), .width = 120, .field = .memory, .always_visible = false, .default_visible = true },
		.{ .label = L("Threads"), .header = L("Threads"), .width = 70, .field = .threads, .always_visible = false, .default_visible = false },
		.{ .label = L("Handles"), .header = L("Handles"), .width = 70, .field = .handles, .always_visible = false, .default_visible = false },
		.{ .label = L("Started"), .header = L("Started"), .width = 100, .field = .starttime, .always_visible = false, .default_visible = false },
		.{ .label = L("Priority"), .header = L("Priority"), .width = 100, .field = .priority, .always_visible = false, .default_visible = false },
		.{ .label = L("Disk I/O"), .header = L("Disk I/O"), .width = 100, .field = .disk_io, .always_visible = false, .default_visible = false },
		.{ .label = L("Private Bytes"), .header = L("Private Bytes"), .width = 120, .field = .private_bytes, .always_visible = false, .default_visible = false },
		.{ .label = L("Page Faults"), .header = L("Page Faults"), .width = 100, .field = .page_faults, .always_visible = false, .default_visible = false },
		.{ .label = L("User"), .header = L("User"), .width = 120, .field = .user, .always_visible = false, .default_visible = false },
		.{ .label = L("Command Line"), .header = L("Command Line"), .width = 500, .field = .cmdline, .always_visible = false, .default_visible = false },
		.{ .label = L("Architecture"), .header = L("Architecture"), .width = 70, .field = .arch, .always_visible = false, .default_visible = false },
		.{ .label = L("Session"), .header = L("Session"), .width = 60, .field = .session, .always_visible = false, .default_visible = false },
		.{ .label = L("Peak Memory"), .header = L("Peak Memory"), .width = 120, .field = .peak_working_set, .always_visible = false, .default_visible = false },
		.{ .label = L("Virtual Memory"), .header = L("Virtual Memory"), .width = 120, .field = .virtual_mem, .always_visible = false, .default_visible = false },
		.{ .label = L("GDI Objects"), .header = L("GDI Objects"), .width = 70, .field = .gdi_objects, .always_visible = false, .default_visible = false },
		.{ .label = L("USER Objects"), .header = L("USER Objects"), .width = 70, .field = .user_objects, .always_visible = false, .default_visible = false },
		.{ .label = L("Integrity"), .header = L("Integrity"), .width = 80, .field = .integrity, .always_visible = false, .default_visible = false },
		.{ .label = L("Parent PID"), .header = L("Parent PID"), .width = 80, .field = .ppid, .always_visible = false, .default_visible = false },
		.{ .label = L("Private Working Set"), .header = L("Private Working Set"), .width = 100, .field = .private_ws, .always_visible = false, .default_visible = false },
		.{ .label = L("Paged Pool"), .header = L("Paged Pool"), .width = 100, .field = .paged_pool, .always_visible = false, .default_visible = false },
		.{ .label = L("Non-paged Pool"), .header = L("Non-paged Pool"), .width = 100, .field = .nonpaged_pool, .always_visible = false, .default_visible = false },
		.{ .label = L("I/O Read"), .header = L("I/O Read"), .width = 100, .field = .io_read, .always_visible = false, .default_visible = false },
		.{ .label = L("I/O Write"), .header = L("I/O Write"), .width = 100, .field = .io_write, .always_visible = false, .default_visible = false },
		.{ .label = L("I/O Other"), .header = L("I/O Other"), .width = 100, .field = .io_other, .always_visible = false, .default_visible = false },
		.{ .label = L("Description"), .header = L("Description"), .width = 200, .field = .description, .always_visible = false, .default_visible = false },
		.{ .label = L("Company"), .header = L("Company"), .width = 150, .field = .company, .always_visible = false, .default_visible = false },
		.{ .label = L("DPI Awareness"), .header = L("DPI Awareness"), .width = 90, .field = .dpi, .always_visible = false, .default_visible = false },
		.{ .label = L("Service"), .header = L("Service"), .width = 200, .field = .service, .always_visible = false, .default_visible = false },
		.{ .label = L("GPU"), .header = L("GPU"), .width = 70, .field = .gpu, .always_visible = false, .default_visible = false },
		.{ .label = L("GPU Memory"), .header = L("GPU Memory"), .width = 100, .field = .gpu_memory, .always_visible = false, .default_visible = false },
		.{ .label = L("CPU Time"), .header = L("CPU Time"), .width = 90, .field = .cpu_time, .always_visible = false, .default_visible = false },
		.{ .label = L("Elevated"), .header = L("Elevated"), .width = 70, .field = .elevated, .always_visible = false, .default_visible = false },
		.{ .label = L("Path"), .header = L("Path"), .width = 300, .field = .path, .always_visible = false, .default_visible = false },
		.{ .label = L("Window Title"), .header = L("Window Title"), .width = 200, .field = .window_title, .always_visible = false, .default_visible = false },
		.{ .label = L("File Version"), .header = L("File Version"), .width = 100, .field = .file_version, .always_visible = false, .default_visible = false },
		.{ .label = L("Product Version"), .header = L("Product Version"), .width = 100, .field = .product_version, .always_visible = false, .default_visible = false },
		.{ .label = L("Session Name"), .header = L("Session Name"), .width = 120, .field = .session_name, .always_visible = false, .default_visible = false },
		.{ .label = L("Package Name"), .header = L("Package Name"), .width = 300, .field = .package_name, .always_visible = false, .default_visible = false },
		.{ .label = L("Peak Virtual Memory"), .header = L("Peak Virtual Memory"), .width = 120, .field = .peak_virtual_mem, .always_visible = false, .default_visible = false },
		.{ .label = L("Peak Private Bytes"), .header = L("Peak Private Bytes"), .width = 120, .field = .peak_private_bytes, .always_visible = false, .default_visible = false },
		.{ .label = L("Peak Paged Pool"), .header = L("Peak Paged Pool"), .width = 100, .field = .peak_paged_pool, .always_visible = false, .default_visible = false },
		.{ .label = L("Peak Non-paged Pool"), .header = L("Peak Non-paged Pool"), .width = 100, .field = .peak_nonpaged_pool, .always_visible = false, .default_visible = false },
		.{ .label = L("Peak Threads"), .header = L("Peak Threads"), .width = 70, .field = .peak_threads, .always_visible = false, .default_visible = false },
		.{ .label = L("Hard Faults"), .header = L("Hard Faults"), .width = 100, .field = .hard_faults, .always_visible = false, .default_visible = false },
		.{ .label = L("CPU Cycles"), .header = L("CPU Cycles"), .width = 110, .field = .cycles, .always_visible = false, .default_visible = false },
		.{ .label = L("Kernel Time"), .header = L("Kernel Time"), .width = 90, .field = .kernel_time, .always_visible = false, .default_visible = false },
		.{ .label = L("User Time"), .header = L("User Time"), .width = 90, .field = .user_time, .always_visible = false, .default_visible = false },
		.{ .label = L("Total Page Faults"), .header = L("Total Page Faults"), .width = 110, .field = .total_page_faults, .always_visible = false, .default_visible = false },
		.{ .label = L("I/O Read Ops"), .header = L("I/O Read Ops"), .width = 100, .field = .io_read_ops, .always_visible = false, .default_visible = false },
		.{ .label = L("I/O Write Ops"), .header = L("I/O Write Ops"), .width = 100, .field = .io_write_ops, .always_visible = false, .default_visible = false },
		.{ .label = L("I/O Other Ops"), .header = L("I/O Other Ops"), .width = 100, .field = .io_other_ops, .always_visible = false, .default_visible = false },
		.{ .label = L("Total I/O"), .header = L("Total I/O"), .width = 110, .field = .total_io, .always_visible = false, .default_visible = false },
		.{ .label = L("Elapsed Time"), .header = L("Elapsed Time"), .width = 110, .field = .elapsed, .always_visible = false, .default_visible = false },
		.{ .label = L("Shared Working Set"), .header = L("Shared Working Set"), .width = 120, .field = .shared_ws, .always_visible = false, .default_visible = false },
		.{ .label = L("Parent Name"), .header = L("Parent Name"), .width = 150, .field = .parent_name, .always_visible = false, .default_visible = false },
		.{ .label = L("Private Bytes Delta"), .header = L("Private Bytes Delta"), .width = 120, .field = .private_bytes_delta, .always_visible = false, .default_visible = false },
		.{ .label = L("Working Set Delta"), .header = L("Working Set Delta"), .width = 120, .field = .working_set_delta, .always_visible = false, .default_visible = false },
		.{ .label = L("Handle Delta"), .header = L("Handle Delta"), .width = 90, .field = .handle_delta, .always_visible = false, .default_visible = false },
		.{ .label = L("Thread Delta"), .header = L("Thread Delta"), .width = 90, .field = .thread_delta, .always_visible = false, .default_visible = false },
		.{ .label = L("Virtualization"), .header = L("Virtualization"), .width = 100, .field = .virtualization, .always_visible = false, .default_visible = false },
		.{ .label = L("AppContainer"), .header = L("AppContainer"), .width = 90, .field = .app_container, .always_visible = false, .default_visible = false },
		.{ .label = L("Domain"), .header = L("Domain"), .width = 120, .field = .domain, .always_visible = false, .default_visible = false },
		.{ .label = L("User SID"), .header = L("User SID"), .width = 220, .field = .user_sid, .always_visible = false, .default_visible = false },
		.{ .label = L("Efficiency Mode"), .header = L("Efficiency Mode"), .width = 100, .field = .efficiency, .always_visible = false, .default_visible = false },
		.{ .label = L("I/O Priority"), .header = L("I/O Priority"), .width = 90, .field = .io_priority, .always_visible = false, .default_visible = false },
		.{ .label = L("Memory Priority"), .header = L("Memory Priority"), .width = 100, .field = .page_priority, .always_visible = false, .default_visible = false },
		.{ .label = L("Protection"), .header = L("Protection"), .width = 130, .field = .protection, .always_visible = false, .default_visible = false },
	};
};

// listview.zig's populateList() skips index 0 when filling sub-item text
// (it's rendered via LVIF_TEXT/entry.name instead), and formatColumn() has
// no .name case of its own for the same reason - both silently rely on
// COLUMNS[0] being the one and only always-visible Name column. Enforce
// that here so reordering COLUMNS is a compile error instead of a silently
// blank/misrendered first column.
comptime {
	if (COLUMNS[0].field != .name or !COLUMNS[0].always_visible)
		@compileError("COLUMNS[0] must be the always-visible .name column");
	for (COLUMNS[1..]) |col| {
		if (col.always_visible)
			@compileError("only COLUMNS[0] may be always_visible");
	}
}

pub const REFRESH_MS: [REFRESH_OPTION_COUNT]win32.UINT = .{ 0, 5000, 10000, 30000, 60000 };
pub const REFRESH_LABELS: [REFRESH_OPTION_COUNT]win32.LPCWSTR = .{ L("Off"), L("5 seconds"), L("10 seconds"), L("30 seconds"), L("1 minute") };

pub const SortPrefs = struct {
	field: SortField,
	desc: [COL_COUNT]bool,
	refresh_ms: win32.UINT,
	visible: [COL_COUNT]bool,
	// Display order as a permutation of COLUMNS indices: order[pos] is the
	// column shown at position pos. order[0] is always the Name column (see
	// the comptime check above).
	order: [COL_COUNT]u8,
	skip_kill_confirm: bool,
	always_on_top: bool,
	tree_mode: bool,
	start_minimized_to_tray: bool,
	window_left: i32,
	window_top: i32,
	window_width: i32,
	window_height: i32,
};

const SettingsDlgData = struct {
	refresh_ms: win32.UINT,
	visible: [COL_COUNT]bool,
	order: [COL_COUNT]u8,
	skip_kill_confirm: bool,
	start_minimized_to_tray: bool,
};

pub const Changes = struct {
	refresh_ms: bool,
	columns: bool,
};

const TAB_COUNT = 2;
const TAB_LABELS: [TAB_COUNT]win32.LPCWSTR = .{ L("General"), L("Columns") };
const TAB_TEMPLATES: [TAB_COUNT]usize = .{ resource.IDD_TAB_GENERAL, resource.IDD_TAB_COLUMNS };

// The settings dialog is modal, so only one set of pages is ever live; keeping
// them here saves threading the handles through every message handler.
var tab_pages: [TAB_COUNT]win32.HWND = .{ null, null };

fn dlgData(hdlg: win32.HWND) *SettingsDlgData {
	return @ptrFromInt(@as(usize, @bitCast(win32.GetWindowLongPtrW(hdlg, win32.DWLP_USER))));
}

fn setCheckState(lv: win32.HWND, item: i32, check: bool) void {
	var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
	lvi.stateMask = win32.LVIS_STATEIMAGEMASK;
	lvi.state = if (check) win32.STATEIMAGE_CHECKED else win32.STATEIMAGE_UNCHECKED;
	_ = win32.SendMessageW(lv, win32.LVM_SETITEMSTATE, @intCast(item), @bitCast(@intFromPtr(&lvi)));
}

// Only unchecked(1)/checked(2) state images are ever set by setCheckState
// above, so comparing the extracted image index against 2 (checked) is
// sufficient - no need to handle any other state image index.
fn getCheckState(lv: win32.HWND, item: i32) bool {
	const state = win32.SendMessageW(lv, win32.LVM_GETITEMSTATE, @intCast(item), win32.LVIS_STATEIMAGEMASK);
	const image_index: u32 = @as(u32, @intCast(state)) >> 12;
	return image_index == 2;
}

fn colRow(lv: win32.HWND, row: i32) usize {
	var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
	lvi.mask = win32.LVIF_PARAM;
	lvi.iItem = row;
	_ = win32.SendMessageW(lv, win32.LVM_GETITEMW, 0, @bitCast(@intFromPtr(&lvi)));
	return @intCast(lvi.lParam);
}

fn setColRow(lv: win32.HWND, row: i32, ci: usize, checked: bool) void {
	var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
	lvi.mask = win32.LVIF_TEXT | win32.LVIF_PARAM;
	lvi.iItem = row;
	lvi.pszText = @constCast(COLUMNS[ci].label);
	lvi.lParam = @intCast(ci);
	_ = win32.SendMessageW(lv, win32.LVM_SETITEMW, 0, @bitCast(@intFromPtr(&lvi)));
	setCheckState(lv, row, checked);
}

fn selectedColRow(lv: win32.HWND) i32 {
	return @intCast(win32.SendMessageW(lv, win32.LVM_GETNEXTITEM, @bitCast(@as(isize, -1)), win32.LVNI_SELECTED));
}

// Swaps the selected row with its neighbour rather than rebuilding the list, so
// the scroll position survives and the moved row stays selected under the
// user's cursor or reading position.
fn moveColumn(page: win32.HWND, delta: i32) void {
	const lv = win32.GetDlgItem(page, resource.IDC_COL_LIST);
	const sel = selectedColRow(lv);
	const dest = sel + delta;
	const count: i32 = @intCast(win32.SendMessageW(lv, win32.LVM_GETITEMCOUNT, 0, 0));
	if (sel < 0 or dest < 0 or dest >= count) return;
	const sel_ci = colRow(lv, sel);
	const sel_checked = getCheckState(lv, sel);
	setColRow(lv, sel, colRow(lv, dest), getCheckState(lv, dest));
	setColRow(lv, dest, sel_ci, sel_checked);
	var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
	lvi.stateMask = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
	lvi.state = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
	_ = win32.SendMessageW(lv, win32.LVM_SETITEMSTATE, @intCast(dest), @bitCast(@intFromPtr(&lvi)));
	_ = win32.SendMessageW(lv, win32.LVM_ENSUREVISIBLE, @intCast(dest), 0);
}

// A move button that silently does nothing at the end of the list gives a
// screen reader nothing to announce, so grey them out instead.
fn updateMoveButtons(page: win32.HWND) void {
	const lv = win32.GetDlgItem(page, resource.IDC_COL_LIST);
	const sel = selectedColRow(lv);
	const count: i32 = @intCast(win32.SendMessageW(lv, win32.LVM_GETITEMCOUNT, 0, 0));
	_ = win32.EnableWindow(win32.GetDlgItem(page, resource.IDC_COL_UP), if (sel > 0) 1 else 0);
	_ = win32.EnableWindow(win32.GetDlgItem(page, resource.IDC_COL_DOWN), if (sel >= 0 and sel < count - 1) 1 else 0);
}

fn settingsLvProc(hwnd: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM, id: win32.UINT_PTR, data: win32.DWORD_PTR) callconv(.c) win32.LRESULT {
	_ = id;
	_ = data;
	if (msg == win32.WM_CHAR and wp == ' ') return 0;
	if (msg == win32.WM_KEYDOWN and (wp == win32.VK_UP or wp == win32.VK_DOWN) and win32.GetKeyState(win32.VK_CONTROL) < 0) {
		moveColumn(win32.GetParent(hwnd), if (wp == win32.VK_UP) -1 else 1);
		return 0;
	}
	return win32.DefSubclassProc(hwnd, msg, wp, lp);
}

fn pageColors(msg: win32.UINT, wp: win32.WPARAM) win32.INT_PTR {
	switch (msg) {
		win32.WM_CTLCOLORDLG => {
			const br = theme.bgBrush();
			if (br != null) return @bitCast(@intFromPtr(br));
		},
		win32.WM_CTLCOLORSTATIC, win32.WM_CTLCOLORBTN, win32.WM_CTLCOLORLISTBOX, win32.WM_CTLCOLOREDIT => {
			const br = theme.ctlColor(@ptrFromInt(@as(usize, @bitCast(wp))));
			if (br != null) return @bitCast(@intFromPtr(br));
		},
		else => {},
	}
	return 0;
}

fn generalPageProc(hdlg: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM) callconv(.c) win32.INT_PTR {
	if (msg == win32.WM_INITDIALOG) {
		const data: *SettingsDlgData = @ptrFromInt(@as(usize, @bitCast(lp)));
		const combo = win32.GetDlgItem(hdlg, resource.IDC_REFRESH_COMBO);
		_ = win32.SetWindowTheme(combo, if (theme.isDark() != 0) L("DarkMode_Explorer") else L("Explorer"), null);
		var sel: i32 = 0;
		for (0..REFRESH_OPTION_COUNT) |i| {
			_ = win32.SendMessageW(combo, win32.CB_ADDSTRING, 0, @bitCast(@intFromPtr(REFRESH_LABELS[i])));
			if (REFRESH_MS[i] == data.refresh_ms) sel = @intCast(i);
		}
		_ = win32.SendMessageW(combo, win32.CB_SETCURSEL, @intCast(sel), 0);
		_ = win32.SendMessageW(win32.GetDlgItem(hdlg, resource.IDC_SKIP_CONFIRM), win32.BM_SETCHECK, if (data.skip_kill_confirm) win32.BST_CHECKED else win32.BST_UNCHECKED, 0);
		_ = win32.SendMessageW(win32.GetDlgItem(hdlg, resource.IDC_START_MINIMIZED), win32.BM_SETCHECK, if (data.start_minimized_to_tray) win32.BST_CHECKED else win32.BST_UNCHECKED, 0);
		return 1;
	}
	return pageColors(msg, wp);
}

fn columnsPageProc(hdlg: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM) callconv(.c) win32.INT_PTR {
	switch (msg) {
		win32.WM_INITDIALOG => {
			const data: *SettingsDlgData = @ptrFromInt(@as(usize, @bitCast(lp)));
			const lv = win32.GetDlgItem(hdlg, resource.IDC_COL_LIST);
			_ = win32.SendMessageW(lv, win32.LVM_SETEXTENDEDLISTVIEWSTYLE, 0, win32.LVS_EX_CHECKBOXES);
			var lvc: win32.LVCOLUMNW = std.mem.zeroes(win32.LVCOLUMNW);
			lvc.mask = win32.LVCF_WIDTH;
			lvc.cx = 1000;
			_ = win32.SendMessageW(lv, win32.LVM_INSERTCOLUMNW, 0, @bitCast(@intFromPtr(&lvc)));
			// Row j is order position j + 1: position 0 is the always-visible Name
			// column, which is neither listed nor movable.
			for (1..COL_COUNT) |pos| {
				const ci: usize = data.order[pos];
				var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
				lvi.mask = win32.LVIF_TEXT | win32.LVIF_PARAM;
				lvi.iItem = @intCast(pos - 1);
				lvi.pszText = @constCast(COLUMNS[ci].label);
				lvi.lParam = @intCast(ci);
				_ = win32.SendMessageW(lv, win32.LVM_INSERTITEMW, 0, @bitCast(@intFromPtr(&lvi)));
				setCheckState(lv, lvi.iItem, data.visible[ci]);
			}
			var first: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
			first.stateMask = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
			first.state = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
			_ = win32.SendMessageW(lv, win32.LVM_SETITEMSTATE, 0, @bitCast(@intFromPtr(&first)));
			theme.applyListview(lv);
			_ = win32.SetWindowSubclass(lv, settingsLvProc, 0, 0);
			updateMoveButtons(hdlg);
			return 1;
		},
		win32.WM_COMMAND => {
			const low: u16 = @truncate(wp);
			if (low == resource.IDC_COL_UP or low == resource.IDC_COL_DOWN) {
				moveColumn(hdlg, if (low == resource.IDC_COL_UP) -1 else 1);
				_ = win32.SetFocus(win32.GetDlgItem(hdlg, resource.IDC_COL_LIST));
				return 1;
			}
		},
		win32.WM_NOTIFY => {
			const hdr: *const win32.NMHDR = @ptrFromInt(@as(usize, @bitCast(lp)));
			if (hdr.idFrom == resource.IDC_COL_LIST and hdr.code == @as(win32.UINT, @bitCast(win32.LVN_ITEMCHANGED))) updateMoveButtons(hdlg);
		},
		else => {},
	}
	return pageColors(msg, wp);
}

fn settingsDlgProc(hdlg: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM) callconv(.c) win32.INT_PTR {
	switch (msg) {
		win32.WM_INITDIALOG => {
			_ = win32.SetWindowLongPtrW(hdlg, win32.DWLP_USER, lp);
			theme.applyTitlebar(hdlg);
			const tab = win32.GetDlgItem(hdlg, resource.IDC_SETTINGS_TAB);
			_ = win32.SendMessageW(tab, win32.WM_SETFONT, @bitCast(win32.SendMessageW(hdlg, win32.WM_GETFONT, 0, 0)), 0);
			theme.applyButton(tab);
			for (0..TAB_COUNT) |i| {
				var tci: win32.TCITEMW = std.mem.zeroes(win32.TCITEMW);
				tci.mask = win32.TCIF_TEXT;
				tci.pszText = @constCast(TAB_LABELS[i]);
				_ = win32.SendMessageW(tab, win32.TCM_INSERTITEMW, @intCast(i), @bitCast(@intFromPtr(&tci)));
			}
			// A tab control marked WS_EX_CONTROLPARENT never keeps focus - the
			// dialog manager treats it as a container and hands focus straight to
			// the first control inside, so Left/Right can't reach the tab strip.
			// Instead the control is trimmed to the strip itself and the pages sit
			// below it as plain siblings: no overlap to fight over, and the sibling
			// order below is also the tab order.
			var client: win32.RECT = std.mem.zeroes(win32.RECT);
			_ = win32.GetClientRect(tab, &client);
			var display = client;
			_ = win32.SendMessageW(tab, win32.TCM_ADJUSTRECT, 0, @bitCast(@intFromPtr(&display)));
			const strip = display.top;
			var placed: win32.RECT = std.mem.zeroes(win32.RECT);
			_ = win32.GetWindowRect(tab, &placed);
			_ = win32.MapWindowPoints(null, hdlg, @ptrCast(&placed), 2);
			const width = placed.right - placed.left;
			_ = win32.SetWindowPos(tab, null, placed.left, placed.top, width, strip, win32.SWP_NOZORDER | win32.SWP_NOACTIVATE);
			const instance = win32.GetModuleHandleW(null);
			var behind = tab;
			for (0..TAB_COUNT) |i| {
				tab_pages[i] = win32.CreateDialogParamW(instance, @ptrFromInt(TAB_TEMPLATES[i]), hdlg, if (i == 0) generalPageProc else columnsPageProc, lp);
				_ = win32.SetWindowPos(tab_pages[i], behind, placed.left, placed.top + strip, width, placed.bottom - placed.top - strip, win32.SWP_NOACTIVATE);
				_ = win32.ShowWindow(tab_pages[i], if (i == 0) win32.SW_SHOW else win32.SW_HIDE);
				behind = tab_pages[i];
			}
			// Tab order: strip -> pages -> OK -> Cancel.
			const ok = win32.GetDlgItem(hdlg, win32.IDOK);
			_ = win32.SetWindowPos(ok, behind, 0, 0, 0, 0, win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOACTIVATE);
			_ = win32.SetWindowPos(win32.GetDlgItem(hdlg, win32.IDCANCEL), ok, 0, 0, 0, 0, win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOACTIVATE);
			return 1;
		},
		win32.WM_NOTIFY => {
			const hdr: *const win32.NMHDR = @ptrFromInt(@as(usize, @bitCast(lp)));
			if (hdr.idFrom == resource.IDC_SETTINGS_TAB and hdr.code == @as(win32.UINT, @bitCast(win32.TCN_SELCHANGE))) {
				const cur = win32.SendMessageW(hdr.hwndFrom, win32.TCM_GETCURSEL, 0, 0);
				for (0..TAB_COUNT) |i| _ = win32.ShowWindow(tab_pages[i], if (i == @as(usize, @intCast(cur))) win32.SW_SHOW else win32.SW_HIDE);
				return 1;
			}
		},
		win32.WM_COMMAND => {
			const low: u16 = @truncate(wp);
			if (low == win32.IDOK) {
				const data = dlgData(hdlg);
				const general = tab_pages[0];
				const combo = win32.GetDlgItem(general, resource.IDC_REFRESH_COMBO);
				const sel: i32 = @intCast(win32.SendMessageW(combo, win32.CB_GETCURSEL, 0, 0));
				data.refresh_ms = if (sel >= 0 and sel < REFRESH_OPTION_COUNT) REFRESH_MS[@intCast(sel)] else 0;
				data.skip_kill_confirm = win32.SendMessageW(win32.GetDlgItem(general, resource.IDC_SKIP_CONFIRM), win32.BM_GETCHECK, 0, 0) == win32.BST_CHECKED;
				data.start_minimized_to_tray = win32.SendMessageW(win32.GetDlgItem(general, resource.IDC_START_MINIMIZED), win32.BM_GETCHECK, 0, 0) == win32.BST_CHECKED;
				const lv = win32.GetDlgItem(tab_pages[1], resource.IDC_COL_LIST);
				const rows: i32 = @intCast(win32.SendMessageW(lv, win32.LVM_GETITEMCOUNT, 0, 0));
				data.order[0] = 0;
				for (0..@intCast(rows)) |j| {
					const ci = colRow(lv, @intCast(j));
					data.order[j + 1] = @intCast(ci);
					data.visible[ci] = getCheckState(lv, @intCast(j));
				}
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
		win32.WM_CTLCOLORSTATIC, win32.WM_CTLCOLORBTN, win32.WM_CTLCOLORLISTBOX, win32.WM_CTLCOLOREDIT => {
			const br = theme.ctlColor(@ptrFromInt(@as(usize, @bitCast(wp))));
			if (br != null) return @bitCast(@intFromPtr(br));
		},
		else => {},
	}
	return 0;
}

pub fn open(parent: win32.HWND, prefs: *SortPrefs) ?Changes {
	var data: SettingsDlgData = .{
		.refresh_ms = prefs.refresh_ms,
		.visible = prefs.visible,
		.order = prefs.order,
		.skip_kill_confirm = prefs.skip_kill_confirm,
		.start_minimized_to_tray = prefs.start_minimized_to_tray,
	};
	if (win32.DialogBoxParamW(win32.GetModuleHandleW(null), @ptrFromInt(resource.IDD_SETTINGS), parent, settingsDlgProc, @bitCast(@intFromPtr(&data))) == 0) return null;
	const changes = Changes{
		.refresh_ms = data.refresh_ms != prefs.refresh_ms,
		.columns = !std.mem.eql(bool, &data.visible, &prefs.visible) or !std.mem.eql(u8, &data.order, &prefs.order),
	};
	prefs.refresh_ms = data.refresh_ms;
	prefs.visible = data.visible;
	prefs.order = data.order;
	prefs.skip_kill_confirm = data.skip_kill_confirm;
	prefs.start_minimized_to_tray = data.start_minimized_to_tray;
	return changes;
}

// Installed copies (under Program Files) can't write next to the exe, so they
// use per-user AppData instead; portable copies keep everything self-contained
// next to the exe. Checking install location rather than probing writability
// keeps this consistent even if the installed copy is ever run elevated.
fn getIniPath(buf: [*:0]u16) void {
	var exe_dir: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
	_ = win32.GetModuleFileNameW(null, &exe_dir, @intCast(win32.MAX_PATH));
	_ = win32.PathRemoveFileSpecW(&exe_dir);
	var program_files: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
	const installed = win32.SHGetFolderPathW(null, win32.CSIDL_PROGRAM_FILES, null, 0, &program_files) >= 0 and win32.PathIsPrefixW(&program_files, &exe_dir) != 0;
	if (installed and win32.SHGetFolderPathW(null, win32.CSIDL_LOCAL_APPDATA, null, 0, buf) >= 0) {
		_ = win32.PathAppendW(buf, L("Taskmon"));
		_ = win32.CreateDirectoryW(buf, null);
		_ = win32.PathAppendW(buf, L("taskmon.ini"));
	} else {
		_ = win32.lstrcpynW(buf, &exe_dir, @intCast(win32.MAX_PATH));
		_ = win32.PathAppendW(buf, L("taskmon.ini"));
	}
}

// Thin wrappers around Get/WritePrivateProfileStringW: every setting is a
// single bool or int under some section/key, so the read/write/parse/format
// boilerplate lives here once instead of once per setting.
fn getIniBool(path: win32.LPCWSTR, section: win32.LPCWSTR, key: win32.LPCWSTR, default: bool) bool {
	var buf: [4:0]u16 = std.mem.zeroes([4:0]u16);
	_ = win32.GetPrivateProfileStringW(section, key, if (default) L("1") else L("0"), &buf, 4, path);
	return buf[0] == '1';
}

fn setIniBool(path: win32.LPCWSTR, section: win32.LPCWSTR, key: win32.LPCWSTR, value: bool) void {
	_ = win32.WritePrivateProfileStringW(section, key, if (value) L("1") else L("0"), path);
}

fn getIniInt(path: win32.LPCWSTR, section: win32.LPCWSTR, key: win32.LPCWSTR, default: i32) i32 {
	var def: [16:0]u16 = std.mem.zeroes([16:0]u16);
	wfmt.format(&def, 16, "%d", .{default});
	var buf: [16:0]u16 = std.mem.zeroes([16:0]u16);
	_ = win32.GetPrivateProfileStringW(section, key, &def, &buf, 16, path);
	return win32.StrToIntW(&buf);
}

fn setIniInt(path: win32.LPCWSTR, section: win32.LPCWSTR, key: win32.LPCWSTR, value: i32) void {
	var buf: [16:0]u16 = std.mem.zeroes([16:0]u16);
	wfmt.format(&buf, 16, "%d", .{value});
	_ = win32.WritePrivateProfileStringW(section, key, &buf, path);
}

// Per-column keys are "<label>_desc" / "<label>_visible"; suffix is comptime
// so it folds into a single wfmt spec instead of taking a runtime parameter.
fn columnKey(comptime suffix: []const u8, buf: *[64:0]u16, label: win32.LPCWSTR) win32.LPCWSTR {
	wfmt.format(buf, 64, "%s" ++ suffix, .{label});
	return buf;
}

pub fn load(prefs: *SortPrefs) void {
	var path: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
	getIniPath(&path);
	prefs.field = .name;

	var field_buf: [64:0]u16 = std.mem.zeroes([64:0]u16);
	_ = win32.GetPrivateProfileStringW(L("sort"), L("field"), COLUMNS[0].label, &field_buf, 64, &path);
	for (0..COL_COUNT) |i| {
		if (win32.StrCmpIW(&field_buf, COLUMNS[i].label) == 0) {
			prefs.field = COLUMNS[i].field;
			break;
		}
	}
	for (0..COL_COUNT) |i| {
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		prefs.desc[i] = getIniBool(&path, L("sort"), columnKey("_desc", &key, COLUMNS[i].label), false);
	}
	prefs.refresh_ms = @intCast(getIniInt(&path, L("refresh"), L("interval_ms"), 0));
	prefs.skip_kill_confirm = getIniBool(&path, L("confirm"), L("skip_kill"), false);
	prefs.always_on_top = getIniBool(&path, L("window"), L("always_on_top"), false);
	prefs.tree_mode = getIniBool(&path, L("view"), L("tree_mode"), false);
	prefs.start_minimized_to_tray = getIniBool(&path, L("window"), L("start_minimized_to_tray"), false);
	prefs.window_width = getIniInt(&path, L("window"), L("width"), 0);
	if (prefs.window_width > 0) {
		prefs.window_height = getIniInt(&path, L("window"), L("height"), 0);
		prefs.window_left = getIniInt(&path, L("window"), L("left"), 0);
		prefs.window_top = getIniInt(&path, L("window"), L("top"), 0);
	}
	for (0..COL_COUNT) |i| {
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		const visible = getIniBool(&path, L("columns"), columnKey("_visible", &key, COLUMNS[i].label), COLUMNS[i].default_visible);
		prefs.visible[i] = COLUMNS[i].always_visible or visible;
	}
	// Saved ranks are insertion-sorted (stable, natural index breaking ties)
	// rather than trusted as positions, so a hand-edited ini, a duplicate rank,
	// or a column added by a later version still yields a full permutation.
	var rank: [COL_COUNT]i32 = undefined;
	for (0..COL_COUNT) |i| {
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		rank[i] = getIniInt(&path, L("columns"), columnKey("_order", &key, COLUMNS[i].label), @intCast(i));
	}
	prefs.order[0] = 0;
	var n: usize = 1;
	for (1..COL_COUNT) |i| {
		var pos = n;
		while (pos > 1 and rank[prefs.order[pos - 1]] > rank[i]) : (pos -= 1) prefs.order[pos] = prefs.order[pos - 1];
		prefs.order[pos] = @intCast(i);
		n += 1;
	}
}

pub fn save(prefs: *const SortPrefs) void {
	var path: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
	getIniPath(&path);
	for (0..COL_COUNT) |i| {
		if (COLUMNS[i].field == prefs.field)
			_ = win32.WritePrivateProfileStringW(L("sort"), L("field"), COLUMNS[i].label, &path);
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		setIniBool(&path, L("sort"), columnKey("_desc", &key, COLUMNS[i].label), prefs.desc[i]);
	}
	setIniInt(&path, L("refresh"), L("interval_ms"), @intCast(prefs.refresh_ms));
	setIniBool(&path, L("confirm"), L("skip_kill"), prefs.skip_kill_confirm);
	setIniBool(&path, L("window"), L("always_on_top"), prefs.always_on_top);
	setIniBool(&path, L("view"), L("tree_mode"), prefs.tree_mode);
	setIniBool(&path, L("window"), L("start_minimized_to_tray"), prefs.start_minimized_to_tray);
	if (prefs.window_width > 0) {
		setIniInt(&path, L("window"), L("left"), prefs.window_left);
		setIniInt(&path, L("window"), L("top"), prefs.window_top);
		setIniInt(&path, L("window"), L("width"), prefs.window_width);
		setIniInt(&path, L("window"), L("height"), prefs.window_height);
	}
	for (0..COL_COUNT) |i| {
		if (COLUMNS[i].always_visible) continue;
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		setIniBool(&path, L("columns"), columnKey("_visible", &key, COLUMNS[i].label), prefs.visible[i]);
	}
	for (0..COL_COUNT) |pos| {
		const ci: usize = prefs.order[pos];
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		setIniInt(&path, L("columns"), columnKey("_order", &key, COLUMNS[ci].label), @intCast(pos));
	}
}
