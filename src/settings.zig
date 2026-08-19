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

pub const REFRESH_MS: [REFRESH_OPTION_COUNT]win32.UINT = .{ 0, 5000, 10000, 30000, 60000 };
pub const REFRESH_LABELS: [REFRESH_OPTION_COUNT]win32.LPCWSTR = .{ L("Off"), L("5 seconds"), L("10 seconds"), L("30 seconds"), L("1 minute") };

pub const SortPrefs = struct {
	field: SortField,
	desc: [COL_COUNT]bool,
	refresh_ms: win32.UINT,
	visible: [COL_COUNT]bool,
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
	skip_kill_confirm: bool,
	start_minimized_to_tray: bool,
};

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

fn settingsLvProc(hwnd: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM, id: win32.UINT_PTR, data: win32.DWORD_PTR) callconv(.c) win32.LRESULT {
	_ = id;
	_ = data;
	if (msg == win32.WM_CHAR and wp == ' ') return 0;
	return win32.DefSubclassProc(hwnd, msg, wp, lp);
}

fn settingsDlgProc(hdlg: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM) callconv(.c) win32.INT_PTR {
	switch (msg) {
		win32.WM_INITDIALOG => {
			_ = win32.SetWindowLongPtrW(hdlg, win32.DWLP_USER, lp);
			theme.applyTitlebar(hdlg);
			const data: *SettingsDlgData = @ptrFromInt(@as(usize, @bitCast(lp)));
			const combo = win32.GetDlgItem(hdlg, resource.IDC_REFRESH_COMBO);
			_ = win32.SetWindowTheme(combo, if (theme.isDark() != 0) L("DarkMode_Explorer") else L("Explorer"), null);
			var sel: i32 = 0;
			for (0..REFRESH_OPTION_COUNT) |i| {
				_ = win32.SendMessageW(combo, win32.CB_ADDSTRING, 0, @bitCast(@intFromPtr(REFRESH_LABELS[i])));
				if (REFRESH_MS[i] == data.refresh_ms) sel = @intCast(i);
			}
			_ = win32.SendMessageW(combo, win32.CB_SETCURSEL, @intCast(sel), 0);
			const font = win32.SendMessageW(hdlg, win32.WM_GETFONT, 0, 0);
			const lv = win32.GetDlgItem(hdlg, resource.IDC_COL_LIST);
			_ = win32.SendMessageW(lv, win32.WM_SETFONT, @bitCast(font), 0);
			_ = win32.SendMessageW(lv, win32.LVM_SETEXTENDEDLISTVIEWSTYLE, 0, win32.LVS_EX_CHECKBOXES);
			var lvc: win32.LVCOLUMNW = std.mem.zeroes(win32.LVCOLUMNW);
			lvc.mask = win32.LVCF_WIDTH;
			lvc.cx = 1000;
			_ = win32.SendMessageW(lv, win32.LVM_INSERTCOLUMNW, 0, @bitCast(@intFromPtr(&lvc)));
			var j: i32 = 0;
			for (0..COL_COUNT) |ci| {
				if (COLUMNS[ci].always_visible) continue;
				var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
				lvi.mask = win32.LVIF_TEXT | win32.LVIF_PARAM;
				lvi.iItem = j;
				lvi.pszText = @constCast(COLUMNS[ci].label);
				lvi.lParam = @intCast(ci);
				_ = win32.SendMessageW(lv, win32.LVM_INSERTITEMW, 0, @bitCast(@intFromPtr(&lvi)));
				setCheckState(lv, lvi.iItem, data.visible[ci]);
				j += 1;
			}
			if (j > 0) {
				var lvi2: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
				lvi2.stateMask = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
				lvi2.state = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
				_ = win32.SendMessageW(lv, win32.LVM_SETITEMSTATE, 0, @bitCast(@intFromPtr(&lvi2)));
			}
			theme.applyListview(lv);
			_ = win32.SetWindowSubclass(lv, settingsLvProc, 0, 0);
			const skip_chk = win32.CreateWindowExW(0, L("BUTTON"), L("Disable end task confirmation (not recommended)"), win32.WS_CHILD | win32.WS_VISIBLE | win32.WS_TABSTOP | win32.BS_AUTOCHECKBOX, 7, 118, 176, 10, hdlg, @ptrFromInt(@as(usize, resource.IDC_SKIP_CONFIRM)), win32.GetModuleHandleW(null), null);
			_ = win32.SendMessageW(skip_chk, win32.WM_SETFONT, @bitCast(font), 0);
			_ = win32.SendMessageW(skip_chk, win32.BM_SETCHECK, if (data.skip_kill_confirm) win32.BST_CHECKED else win32.BST_UNCHECKED, 0);
			const min_chk = win32.CreateWindowExW(0, L("BUTTON"), L("Start minimized to tray"), win32.WS_CHILD | win32.WS_VISIBLE | win32.WS_TABSTOP | win32.BS_AUTOCHECKBOX, 7, 131, 176, 10, hdlg, @ptrFromInt(@as(usize, resource.IDC_START_MINIMIZED)), win32.GetModuleHandleW(null), null);
			_ = win32.SendMessageW(min_chk, win32.WM_SETFONT, @bitCast(font), 0);
			_ = win32.SendMessageW(min_chk, win32.BM_SETCHECK, if (data.start_minimized_to_tray) win32.BST_CHECKED else win32.BST_UNCHECKED, 0);
			// Tab order: combo -> listview -> skip_chk -> min_chk -> OK -> Cancel
			_ = win32.SetWindowPos(skip_chk, lv, 0, 0, 0, 0, win32.SWP_NOMOVE | win32.SWP_NOSIZE);
			_ = win32.SetWindowPos(min_chk, skip_chk, 0, 0, 0, 0, win32.SWP_NOMOVE | win32.SWP_NOSIZE);
			_ = win32.SetWindowPos(win32.GetDlgItem(hdlg, win32.IDOK), min_chk, 0, 0, 0, 0, win32.SWP_NOMOVE | win32.SWP_NOSIZE);
			_ = win32.SetWindowPos(win32.GetDlgItem(hdlg, win32.IDCANCEL), win32.GetDlgItem(hdlg, win32.IDOK), 0, 0, 0, 0, win32.SWP_NOMOVE | win32.SWP_NOSIZE);
			return 1;
		},
		win32.WM_COMMAND => {
			const low: u16 = @truncate(wp);
			if (low == win32.IDOK) {
				const data: *SettingsDlgData = @ptrFromInt(@as(usize, @bitCast(win32.GetWindowLongPtrW(hdlg, win32.DWLP_USER))));
				const combo = win32.GetDlgItem(hdlg, resource.IDC_REFRESH_COMBO);
				const sel: i32 = @intCast(win32.SendMessageW(combo, win32.CB_GETCURSEL, 0, 0));
				data.refresh_ms = if (sel >= 0 and sel < REFRESH_OPTION_COUNT) REFRESH_MS[@intCast(sel)] else 0;
				const lv = win32.GetDlgItem(hdlg, resource.IDC_COL_LIST);
				const lv_count: i32 = @intCast(win32.SendMessageW(lv, win32.LVM_GETITEMCOUNT, 0, 0));
				for (0..@intCast(lv_count)) |j| {
					var lvi2: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
					lvi2.mask = win32.LVIF_PARAM;
					lvi2.iItem = @intCast(j);
					_ = win32.SendMessageW(lv, win32.LVM_GETITEMW, 0, @bitCast(@intFromPtr(&lvi2)));
					const idx: usize = @intCast(lvi2.lParam);
					data.visible[idx] = getCheckState(lv, @intCast(j));
				}
				data.skip_kill_confirm = win32.SendMessageW(win32.GetDlgItem(hdlg, resource.IDC_SKIP_CONFIRM), win32.BM_GETCHECK, 0, 0) == win32.BST_CHECKED;
				data.start_minimized_to_tray = win32.SendMessageW(win32.GetDlgItem(hdlg, resource.IDC_START_MINIMIZED), win32.BM_GETCHECK, 0, 0) == win32.BST_CHECKED;
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

pub fn open(parent: win32.HWND, current_ms: win32.UINT, current_visible: [*]const bool, current_skip_confirm: bool, current_start_minimized: bool, out_ms: *win32.UINT, out_visible: [*]bool, out_skip_confirm: *bool, out_start_minimized: *bool) bool {
	var data: SettingsDlgData = undefined;
	data.refresh_ms = current_ms;
	for (0..COL_COUNT) |i| data.visible[i] = current_visible[i];
	data.skip_kill_confirm = current_skip_confirm;
	data.start_minimized_to_tray = current_start_minimized;
	const result = win32.DialogBoxParamW(win32.GetModuleHandleW(null), @ptrFromInt(resource.IDD_SETTINGS), parent, settingsDlgProc, @bitCast(@intFromPtr(&data)));
	if (result == 0) return false;
	out_ms.* = data.refresh_ms;
	for (0..COL_COUNT) |i| out_visible[i] = data.visible[i];
	out_skip_confirm.* = data.skip_kill_confirm;
	out_start_minimized.* = data.start_minimized_to_tray;
	return true;
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

pub fn load(prefs: *SortPrefs) void {
	var path: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
	getIniPath(&path);
	prefs.field = .name;
	prefs.refresh_ms = 0;
	for (0..COL_COUNT) |i| {
		prefs.desc[i] = false;
		prefs.visible[i] = COLUMNS[i].always_visible;
	}
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
		var val: [4:0]u16 = std.mem.zeroes([4:0]u16);
		wfmt.format(&key, 64, "%s_desc", .{COLUMNS[i].label});
		_ = win32.GetPrivateProfileStringW(L("sort"), &key, L("0"), &val, 4, &path);
		prefs.desc[i] = val[0] == '1';
	}
	var ms_buf: [16:0]u16 = std.mem.zeroes([16:0]u16);
	_ = win32.GetPrivateProfileStringW(L("refresh"), L("interval_ms"), L("2000"), &ms_buf, 16, &path);
	prefs.refresh_ms = @intCast(win32.StrToIntW(&ms_buf));
	var skip_buf: [4:0]u16 = std.mem.zeroes([4:0]u16);
	_ = win32.GetPrivateProfileStringW(L("confirm"), L("skip_kill"), L("0"), &skip_buf, 4, &path);
	prefs.skip_kill_confirm = skip_buf[0] == '1';
	var aot_buf: [4:0]u16 = std.mem.zeroes([4:0]u16);
	_ = win32.GetPrivateProfileStringW(L("window"), L("always_on_top"), L("0"), &aot_buf, 4, &path);
	prefs.always_on_top = aot_buf[0] == '1';
	var tree_buf: [4:0]u16 = std.mem.zeroes([4:0]u16);
	_ = win32.GetPrivateProfileStringW(L("view"), L("tree_mode"), L("0"), &tree_buf, 4, &path);
	prefs.tree_mode = tree_buf[0] == '1';
	var startmin_buf: [4:0]u16 = std.mem.zeroes([4:0]u16);
	_ = win32.GetPrivateProfileStringW(L("window"), L("start_minimized_to_tray"), L("0"), &startmin_buf, 4, &path);
	prefs.start_minimized_to_tray = startmin_buf[0] == '1';
	var pos_buf: [16:0]u16 = std.mem.zeroes([16:0]u16);
	_ = win32.GetPrivateProfileStringW(L("window"), L("width"), L("0"), &pos_buf, 16, &path);
	prefs.window_width = win32.StrToIntW(&pos_buf);
	if (prefs.window_width > 0) {
		_ = win32.GetPrivateProfileStringW(L("window"), L("height"), L("0"), &pos_buf, 16, &path);
		prefs.window_height = win32.StrToIntW(&pos_buf);
		_ = win32.GetPrivateProfileStringW(L("window"), L("left"), L("0"), &pos_buf, 16, &path);
		prefs.window_left = win32.StrToIntW(&pos_buf);
		_ = win32.GetPrivateProfileStringW(L("window"), L("top"), L("0"), &pos_buf, 16, &path);
		prefs.window_top = win32.StrToIntW(&pos_buf);
	}
	for (0..COL_COUNT) |i| {
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		var val: [4:0]u16 = std.mem.zeroes([4:0]u16);
		wfmt.format(&key, 64, "%s_visible", .{COLUMNS[i].label});
		var def: [2:0]u16 = .{ if (COLUMNS[i].default_visible) '1' else '0', 0 };
		_ = win32.GetPrivateProfileStringW(L("columns"), &key, &def, &val, 4, &path);
		prefs.visible[i] = COLUMNS[i].always_visible or val[0] == '1';
	}
}

pub fn save(prefs: *const SortPrefs) void {
	var path: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
	getIniPath(&path);
	for (0..COL_COUNT) |i| {
		if (COLUMNS[i].field == prefs.field)
			_ = win32.WritePrivateProfileStringW(L("sort"), L("field"), COLUMNS[i].label, &path);
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		wfmt.format(&key, 64, "%s_desc", .{COLUMNS[i].label});
		_ = win32.WritePrivateProfileStringW(L("sort"), &key, if (prefs.desc[i]) L("1") else L("0"), &path);
	}
	var ms_str: [16:0]u16 = std.mem.zeroes([16:0]u16);
	wfmt.format(&ms_str, 16, "%u", .{prefs.refresh_ms});
	_ = win32.WritePrivateProfileStringW(L("refresh"), L("interval_ms"), &ms_str, &path);
	_ = win32.WritePrivateProfileStringW(L("confirm"), L("skip_kill"), if (prefs.skip_kill_confirm) L("1") else L("0"), &path);
	_ = win32.WritePrivateProfileStringW(L("window"), L("always_on_top"), if (prefs.always_on_top) L("1") else L("0"), &path);
	_ = win32.WritePrivateProfileStringW(L("view"), L("tree_mode"), if (prefs.tree_mode) L("1") else L("0"), &path);
	_ = win32.WritePrivateProfileStringW(L("window"), L("start_minimized_to_tray"), if (prefs.start_minimized_to_tray) L("1") else L("0"), &path);
	if (prefs.window_width > 0) {
		var pos_str: [16:0]u16 = std.mem.zeroes([16:0]u16);
		wfmt.format(&pos_str, 16, "%d", .{prefs.window_left});
		_ = win32.WritePrivateProfileStringW(L("window"), L("left"), &pos_str, &path);
		wfmt.format(&pos_str, 16, "%d", .{prefs.window_top});
		_ = win32.WritePrivateProfileStringW(L("window"), L("top"), &pos_str, &path);
		wfmt.format(&pos_str, 16, "%d", .{prefs.window_width});
		_ = win32.WritePrivateProfileStringW(L("window"), L("width"), &pos_str, &path);
		wfmt.format(&pos_str, 16, "%d", .{prefs.window_height});
		_ = win32.WritePrivateProfileStringW(L("window"), L("height"), &pos_str, &path);
	}
	for (0..COL_COUNT) |i| {
		if (COLUMNS[i].always_visible) continue;
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		wfmt.format(&key, 64, "%s_visible", .{COLUMNS[i].label});
		_ = win32.WritePrivateProfileStringW(L("columns"), &key, if (prefs.visible[i]) L("1") else L("0"), &path);
	}
}
