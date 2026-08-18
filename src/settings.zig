const std = @import("std");
const win32 = @import("win32.zig");
const resource = @import("resource.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

extern fn theme_apply_titlebar(hwnd: win32.HWND) callconv(.c) void;
extern fn theme_is_dark() callconv(.c) win32.BOOL;
extern fn theme_apply_listview(hwnd_list: win32.HWND) callconv(.c) void;
extern fn theme_bg_brush() callconv(.c) win32.HBRUSH;
extern fn theme_ctl_color(hdc: win32.HDC) callconv(.c) win32.HBRUSH;

pub const SortField = enum(i32) {
	SORT_FIELD_NAME,
	SORT_FIELD_PID,
	SORT_FIELD_CPU,
	SORT_FIELD_MEMORY,
	SORT_FIELD_THREADS,
	SORT_FIELD_HANDLES,
	SORT_FIELD_STARTTIME,
	SORT_FIELD_PRIORITY,
	SORT_FIELD_DISK_IO,
	SORT_FIELD_PRIVATE_BYTES,
	SORT_FIELD_PAGE_FAULTS,
	SORT_FIELD_USER,
	SORT_FIELD_CMDLINE,
	SORT_FIELD_ARCH,
	SORT_FIELD_SESSION,
	SORT_FIELD_PEAK_WORKING_SET,
	SORT_FIELD_VIRTUAL_MEM,
	SORT_FIELD_GDI_OBJECTS,
	SORT_FIELD_USER_OBJECTS,
	SORT_FIELD_INTEGRITY,
	SORT_FIELD_PPID,
	SORT_FIELD_PRIVATE_WS,
	SORT_FIELD_PAGED_POOL,
	SORT_FIELD_NONPAGED_POOL,
	SORT_FIELD_IO_READ,
	SORT_FIELD_IO_WRITE,
	SORT_FIELD_IO_OTHER,
	SORT_FIELD_DESCRIPTION,
	SORT_FIELD_COMPANY,
	SORT_FIELD_DPI,
	SORT_FIELD_SERVICE,
	SORT_FIELD_GPU,
	SORT_FIELD_GPU_MEMORY,
	SORT_FIELD_CPU_TIME,
	SORT_FIELD_ELEVATED,
	SORT_FIELD_PATH,
	SORT_FIELD_WINDOW_TITLE,
	SORT_FIELD_FILE_VERSION,
	SORT_FIELD_PRODUCT_VERSION,
	SORT_FIELD_SESSION_NAME,
	SORT_FIELD_PACKAGE_NAME,
	SORT_FIELD_PEAK_VIRTUAL_MEM,
	SORT_FIELD_PEAK_PRIVATE_BYTES,
	SORT_FIELD_PEAK_PAGED_POOL,
	SORT_FIELD_PEAK_NONPAGED_POOL,
	SORT_FIELD_PEAK_THREADS,
	SORT_FIELD_HARD_FAULTS,
	SORT_FIELD_CYCLES,
	SORT_FIELD_KERNEL_TIME,
	SORT_FIELD_USER_TIME,
	SORT_FIELD_TOTAL_PAGE_FAULTS,
	SORT_FIELD_IO_READ_OPS,
	SORT_FIELD_IO_WRITE_OPS,
	SORT_FIELD_IO_OTHER_OPS,
	SORT_FIELD_TOTAL_IO,
	SORT_FIELD_ELAPSED,
	SORT_FIELD_SHARED_WS,
	SORT_FIELD_PARENT_NAME,
	SORT_FIELD_PRIVATE_BYTES_DELTA,
	SORT_FIELD_WORKING_SET_DELTA,
	SORT_FIELD_HANDLE_DELTA,
	SORT_FIELD_THREAD_DELTA,
	SORT_FIELD_VIRTUALIZATION,
	SORT_FIELD_APP_CONTAINER,
	SORT_FIELD_DOMAIN,
	SORT_FIELD_USER_SID,
	SORT_FIELD_EFFICIENCY,
	SORT_FIELD_IO_PRIORITY,
	SORT_FIELD_PAGE_PRIORITY,
	SORT_FIELD_PROTECTION,
};

pub const ColumnDef = extern struct {
	label: win32.LPCWSTR,
	header: win32.LPCWSTR,
	width: i32,
	field: SortField,
	always_visible: win32.BOOL,
	default_visible: win32.BOOL,
};

pub const COL_COUNT: usize = 70;
const REFRESH_OPTION_COUNT = 5;

pub export const COLUMNS: [COL_COUNT]ColumnDef = columns: {
	@setEvalBranchQuota(100_000);
	break :columns .{
	.{ .label = L("Name"), .header = L("Name"), .width = 260, .field = .SORT_FIELD_NAME, .always_visible = 1, .default_visible = 1 },
	.{ .label = L("PID"), .header = L("PID"), .width = 80, .field = .SORT_FIELD_PID, .always_visible = 0, .default_visible = 1 },
	.{ .label = L("CPU"), .header = L("CPU %"), .width = 90, .field = .SORT_FIELD_CPU, .always_visible = 0, .default_visible = 1 },
	.{ .label = L("Memory"), .header = L("Memory"), .width = 120, .field = .SORT_FIELD_MEMORY, .always_visible = 0, .default_visible = 1 },
	.{ .label = L("Threads"), .header = L("Threads"), .width = 70, .field = .SORT_FIELD_THREADS, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Handles"), .header = L("Handles"), .width = 70, .field = .SORT_FIELD_HANDLES, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Started"), .header = L("Started"), .width = 100, .field = .SORT_FIELD_STARTTIME, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Priority"), .header = L("Priority"), .width = 100, .field = .SORT_FIELD_PRIORITY, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Disk I/O"), .header = L("Disk I/O"), .width = 100, .field = .SORT_FIELD_DISK_IO, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Private Bytes"), .header = L("Private Bytes"), .width = 120, .field = .SORT_FIELD_PRIVATE_BYTES, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Page Faults"), .header = L("Page Faults"), .width = 100, .field = .SORT_FIELD_PAGE_FAULTS, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("User"), .header = L("User"), .width = 120, .field = .SORT_FIELD_USER, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Command Line"), .header = L("Command Line"), .width = 500, .field = .SORT_FIELD_CMDLINE, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Architecture"), .header = L("Architecture"), .width = 70, .field = .SORT_FIELD_ARCH, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Session"), .header = L("Session"), .width = 60, .field = .SORT_FIELD_SESSION, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Peak Memory"), .header = L("Peak Memory"), .width = 120, .field = .SORT_FIELD_PEAK_WORKING_SET, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Virtual Memory"), .header = L("Virtual Memory"), .width = 120, .field = .SORT_FIELD_VIRTUAL_MEM, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("GDI Objects"), .header = L("GDI Objects"), .width = 70, .field = .SORT_FIELD_GDI_OBJECTS, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("USER Objects"), .header = L("USER Objects"), .width = 70, .field = .SORT_FIELD_USER_OBJECTS, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Integrity"), .header = L("Integrity"), .width = 80, .field = .SORT_FIELD_INTEGRITY, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Parent PID"), .header = L("Parent PID"), .width = 80, .field = .SORT_FIELD_PPID, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Private Working Set"), .header = L("Private Working Set"), .width = 100, .field = .SORT_FIELD_PRIVATE_WS, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Paged Pool"), .header = L("Paged Pool"), .width = 100, .field = .SORT_FIELD_PAGED_POOL, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Non-paged Pool"), .header = L("Non-paged Pool"), .width = 100, .field = .SORT_FIELD_NONPAGED_POOL, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("I/O Read"), .header = L("I/O Read"), .width = 100, .field = .SORT_FIELD_IO_READ, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("I/O Write"), .header = L("I/O Write"), .width = 100, .field = .SORT_FIELD_IO_WRITE, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("I/O Other"), .header = L("I/O Other"), .width = 100, .field = .SORT_FIELD_IO_OTHER, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Description"), .header = L("Description"), .width = 200, .field = .SORT_FIELD_DESCRIPTION, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Company"), .header = L("Company"), .width = 150, .field = .SORT_FIELD_COMPANY, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("DPI Awareness"), .header = L("DPI Awareness"), .width = 90, .field = .SORT_FIELD_DPI, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Service"), .header = L("Service"), .width = 200, .field = .SORT_FIELD_SERVICE, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("GPU"), .header = L("GPU"), .width = 70, .field = .SORT_FIELD_GPU, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("GPU Memory"), .header = L("GPU Memory"), .width = 100, .field = .SORT_FIELD_GPU_MEMORY, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("CPU Time"), .header = L("CPU Time"), .width = 90, .field = .SORT_FIELD_CPU_TIME, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Elevated"), .header = L("Elevated"), .width = 70, .field = .SORT_FIELD_ELEVATED, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Path"), .header = L("Path"), .width = 300, .field = .SORT_FIELD_PATH, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Window Title"), .header = L("Window Title"), .width = 200, .field = .SORT_FIELD_WINDOW_TITLE, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("File Version"), .header = L("File Version"), .width = 100, .field = .SORT_FIELD_FILE_VERSION, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Product Version"), .header = L("Product Version"), .width = 100, .field = .SORT_FIELD_PRODUCT_VERSION, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Session Name"), .header = L("Session Name"), .width = 120, .field = .SORT_FIELD_SESSION_NAME, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Package Name"), .header = L("Package Name"), .width = 300, .field = .SORT_FIELD_PACKAGE_NAME, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Peak Virtual Memory"), .header = L("Peak Virtual Memory"), .width = 120, .field = .SORT_FIELD_PEAK_VIRTUAL_MEM, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Peak Private Bytes"), .header = L("Peak Private Bytes"), .width = 120, .field = .SORT_FIELD_PEAK_PRIVATE_BYTES, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Peak Paged Pool"), .header = L("Peak Paged Pool"), .width = 100, .field = .SORT_FIELD_PEAK_PAGED_POOL, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Peak Non-paged Pool"), .header = L("Peak Non-paged Pool"), .width = 100, .field = .SORT_FIELD_PEAK_NONPAGED_POOL, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Peak Threads"), .header = L("Peak Threads"), .width = 70, .field = .SORT_FIELD_PEAK_THREADS, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Hard Faults"), .header = L("Hard Faults"), .width = 100, .field = .SORT_FIELD_HARD_FAULTS, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("CPU Cycles"), .header = L("CPU Cycles"), .width = 110, .field = .SORT_FIELD_CYCLES, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Kernel Time"), .header = L("Kernel Time"), .width = 90, .field = .SORT_FIELD_KERNEL_TIME, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("User Time"), .header = L("User Time"), .width = 90, .field = .SORT_FIELD_USER_TIME, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Total Page Faults"), .header = L("Total Page Faults"), .width = 110, .field = .SORT_FIELD_TOTAL_PAGE_FAULTS, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("I/O Read Ops"), .header = L("I/O Read Ops"), .width = 100, .field = .SORT_FIELD_IO_READ_OPS, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("I/O Write Ops"), .header = L("I/O Write Ops"), .width = 100, .field = .SORT_FIELD_IO_WRITE_OPS, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("I/O Other Ops"), .header = L("I/O Other Ops"), .width = 100, .field = .SORT_FIELD_IO_OTHER_OPS, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Total I/O"), .header = L("Total I/O"), .width = 110, .field = .SORT_FIELD_TOTAL_IO, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Elapsed Time"), .header = L("Elapsed Time"), .width = 110, .field = .SORT_FIELD_ELAPSED, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Shared Working Set"), .header = L("Shared Working Set"), .width = 120, .field = .SORT_FIELD_SHARED_WS, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Parent Name"), .header = L("Parent Name"), .width = 150, .field = .SORT_FIELD_PARENT_NAME, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Private Bytes Delta"), .header = L("Private Bytes Delta"), .width = 120, .field = .SORT_FIELD_PRIVATE_BYTES_DELTA, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Working Set Delta"), .header = L("Working Set Delta"), .width = 120, .field = .SORT_FIELD_WORKING_SET_DELTA, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Handle Delta"), .header = L("Handle Delta"), .width = 90, .field = .SORT_FIELD_HANDLE_DELTA, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Thread Delta"), .header = L("Thread Delta"), .width = 90, .field = .SORT_FIELD_THREAD_DELTA, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Virtualization"), .header = L("Virtualization"), .width = 100, .field = .SORT_FIELD_VIRTUALIZATION, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("AppContainer"), .header = L("AppContainer"), .width = 90, .field = .SORT_FIELD_APP_CONTAINER, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Domain"), .header = L("Domain"), .width = 120, .field = .SORT_FIELD_DOMAIN, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("User SID"), .header = L("User SID"), .width = 220, .field = .SORT_FIELD_USER_SID, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Efficiency Mode"), .header = L("Efficiency Mode"), .width = 100, .field = .SORT_FIELD_EFFICIENCY, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("I/O Priority"), .header = L("I/O Priority"), .width = 90, .field = .SORT_FIELD_IO_PRIORITY, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Memory Priority"), .header = L("Memory Priority"), .width = 100, .field = .SORT_FIELD_PAGE_PRIORITY, .always_visible = 0, .default_visible = 0 },
	.{ .label = L("Protection"), .header = L("Protection"), .width = 130, .field = .SORT_FIELD_PROTECTION, .always_visible = 0, .default_visible = 0 },
	};
};

pub export const REFRESH_MS: [REFRESH_OPTION_COUNT]win32.UINT = .{ 0, 5000, 10000, 30000, 60000 };
pub export const REFRESH_LABELS: [REFRESH_OPTION_COUNT]win32.LPCWSTR = .{ L("Off"), L("5 seconds"), L("10 seconds"), L("30 seconds"), L("1 minute") };

pub const SortPrefs = extern struct {
	field: SortField,
	desc: [COL_COUNT]win32.BOOL,
	refresh_ms: win32.UINT,
	visible: [COL_COUNT]win32.BOOL,
	skip_kill_confirm: win32.BOOL,
	always_on_top: win32.BOOL,
	tree_mode: win32.BOOL,
	start_minimized_to_tray: win32.BOOL,
	window_left: i32,
	window_top: i32,
	window_width: i32,
	window_height: i32,
};

const SettingsDlgData = struct {
	refresh_ms: win32.UINT,
	visible: [COL_COUNT]win32.BOOL,
	skip_kill_confirm: win32.BOOL,
	start_minimized_to_tray: win32.BOOL,
};

fn setCheckState(lv: win32.HWND, item: i32, check: bool) void {
	var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
	lvi.stateMask = win32.LVIS_STATEIMAGEMASK;
	lvi.state = if (check) win32.STATEIMAGE_CHECKED else win32.STATEIMAGE_UNCHECKED;
	_ = win32.SendMessageW(lv, win32.LVM_SETITEMSTATE, @intCast(item), @bitCast(@intFromPtr(&lvi)));
}

// Only unchecked(1)/checked(2) state images are ever set by setCheckState
// above, so comparing the extracted image index against 2 is equivalent to
// the original C macro's "(state>>12)-1" trick without its underflow case.
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
			theme_apply_titlebar(hdlg);
			const data: *SettingsDlgData = @ptrFromInt(@as(usize, @bitCast(lp)));
			const combo = win32.GetDlgItem(hdlg, resource.IDC_REFRESH_COMBO);
			_ = win32.SetWindowTheme(combo, if (theme_is_dark() != 0) L("DarkMode_Explorer") else L("Explorer"), null);
			var sel: i32 = 0;
			var i: i32 = 0;
			while (i < REFRESH_OPTION_COUNT) : (i += 1) {
				_ = win32.SendMessageW(combo, win32.CB_ADDSTRING, 0, @bitCast(@intFromPtr(REFRESH_LABELS[@intCast(i)])));
				if (REFRESH_MS[@intCast(i)] == data.refresh_ms) sel = i;
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
			i = 0;
			while (i < COL_COUNT) : (i += 1) {
				const ci: usize = @intCast(i);
				if (COLUMNS[ci].always_visible != 0) continue;
				var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
				lvi.mask = win32.LVIF_TEXT | win32.LVIF_PARAM;
				lvi.iItem = j;
				lvi.pszText = @constCast(COLUMNS[ci].label);
				lvi.lParam = i;
				_ = win32.SendMessageW(lv, win32.LVM_INSERTITEMW, 0, @bitCast(@intFromPtr(&lvi)));
				setCheckState(lv, lvi.iItem, data.visible[ci] != 0);
				j += 1;
			}
			if (j > 0) {
				var lvi2: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
				lvi2.stateMask = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
				lvi2.state = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
				_ = win32.SendMessageW(lv, win32.LVM_SETITEMSTATE, 0, @bitCast(@intFromPtr(&lvi2)));
			}
			theme_apply_listview(lv);
			_ = win32.SetWindowSubclass(lv, settingsLvProc, 0, 0);
			const skip_chk = win32.CreateWindowExW(0, L("BUTTON"), L("Disable end task confirmation (not recommended)"), win32.WS_CHILD | win32.WS_VISIBLE | win32.WS_TABSTOP | win32.BS_AUTOCHECKBOX, 7, 118, 176, 10, hdlg, @ptrFromInt(@as(usize, resource.IDC_SKIP_CONFIRM)), win32.GetModuleHandleW(null), null);
			_ = win32.SendMessageW(skip_chk, win32.WM_SETFONT, @bitCast(font), 0);
			_ = win32.SendMessageW(skip_chk, win32.BM_SETCHECK, if (data.skip_kill_confirm != 0) win32.BST_CHECKED else win32.BST_UNCHECKED, 0);
			const min_chk = win32.CreateWindowExW(0, L("BUTTON"), L("Start minimized to tray"), win32.WS_CHILD | win32.WS_VISIBLE | win32.WS_TABSTOP | win32.BS_AUTOCHECKBOX, 7, 131, 176, 10, hdlg, @ptrFromInt(@as(usize, resource.IDC_START_MINIMIZED)), win32.GetModuleHandleW(null), null);
			_ = win32.SendMessageW(min_chk, win32.WM_SETFONT, @bitCast(font), 0);
			_ = win32.SendMessageW(min_chk, win32.BM_SETCHECK, if (data.start_minimized_to_tray != 0) win32.BST_CHECKED else win32.BST_UNCHECKED, 0);
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
				var j: i32 = 0;
				while (j < lv_count) : (j += 1) {
					var lvi2: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
					lvi2.mask = win32.LVIF_PARAM;
					lvi2.iItem = j;
					_ = win32.SendMessageW(lv, win32.LVM_GETITEMW, 0, @bitCast(@intFromPtr(&lvi2)));
					const idx: usize = @intCast(lvi2.lParam);
					data.visible[idx] = if (getCheckState(lv, j)) 1 else 0;
				}
				data.skip_kill_confirm = if (win32.SendMessageW(win32.GetDlgItem(hdlg, resource.IDC_SKIP_CONFIRM), win32.BM_GETCHECK, 0, 0) == win32.BST_CHECKED) 1 else 0;
				data.start_minimized_to_tray = if (win32.SendMessageW(win32.GetDlgItem(hdlg, resource.IDC_START_MINIMIZED), win32.BM_GETCHECK, 0, 0) == win32.BST_CHECKED) 1 else 0;
				_ = win32.EndDialog(hdlg, 1);
				return 1;
			}
			if (low == win32.IDCANCEL) {
				_ = win32.EndDialog(hdlg, 0);
				return 1;
			}
		},
		win32.WM_CTLCOLORDLG => {
			const br = theme_bg_brush();
			if (br != null) return @bitCast(@intFromPtr(br));
		},
		win32.WM_CTLCOLORSTATIC, win32.WM_CTLCOLORBTN, win32.WM_CTLCOLORLISTBOX, win32.WM_CTLCOLOREDIT => {
			const br = theme_ctl_color(@ptrFromInt(@as(usize, @bitCast(wp))));
			if (br != null) return @bitCast(@intFromPtr(br));
		},
		else => {},
	}
	return 0;
}

pub export fn open_settings(parent: win32.HWND, current_ms: win32.UINT, current_visible: [*]const win32.BOOL, current_skip_confirm: win32.BOOL, current_start_minimized: win32.BOOL, out_ms: *win32.UINT, out_visible: [*]win32.BOOL, out_skip_confirm: *win32.BOOL, out_start_minimized: *win32.BOOL) callconv(.c) win32.BOOL {
	var data: SettingsDlgData = undefined;
	data.refresh_ms = current_ms;
	var i: usize = 0;
	while (i < COL_COUNT) : (i += 1) data.visible[i] = current_visible[i];
	data.skip_kill_confirm = current_skip_confirm;
	data.start_minimized_to_tray = current_start_minimized;
	const result = win32.DialogBoxParamW(win32.GetModuleHandleW(null), @ptrFromInt(resource.IDD_SETTINGS), parent, settingsDlgProc, @bitCast(@intFromPtr(&data)));
	if (result == 0) return 0;
	out_ms.* = data.refresh_ms;
	i = 0;
	while (i < COL_COUNT) : (i += 1) out_visible[i] = data.visible[i];
	out_skip_confirm.* = data.skip_kill_confirm;
	out_start_minimized.* = data.start_minimized_to_tray;
	return 1;
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

pub export fn settings_load(prefs: *SortPrefs) callconv(.c) void {
	var path: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
	getIniPath(&path);
	prefs.field = .SORT_FIELD_NAME;
	prefs.refresh_ms = 0;
	var i: usize = 0;
	while (i < COL_COUNT) : (i += 1) {
		prefs.desc[i] = 0;
		prefs.visible[i] = COLUMNS[i].always_visible;
	}
	var field_buf: [64:0]u16 = std.mem.zeroes([64:0]u16);
	_ = win32.GetPrivateProfileStringW(L("sort"), L("field"), COLUMNS[0].label, &field_buf, 64, &path);
	i = 0;
	while (i < COL_COUNT) : (i += 1) {
		if (win32.StrCmpIW(&field_buf, COLUMNS[i].label) == 0) {
			prefs.field = COLUMNS[i].field;
			break;
		}
	}
	i = 0;
	while (i < COL_COUNT) : (i += 1) {
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		var val: [4:0]u16 = std.mem.zeroes([4:0]u16);
		_ = win32.wnsprintfW(&key, 64, L("%s_desc"), COLUMNS[i].label);
		_ = win32.GetPrivateProfileStringW(L("sort"), &key, L("0"), &val, 4, &path);
		prefs.desc[i] = if (val[0] == '1') 1 else 0;
	}
	var ms_buf: [16:0]u16 = std.mem.zeroes([16:0]u16);
	_ = win32.GetPrivateProfileStringW(L("refresh"), L("interval_ms"), L("2000"), &ms_buf, 16, &path);
	prefs.refresh_ms = @intCast(win32.StrToIntW(&ms_buf));
	var skip_buf: [4:0]u16 = std.mem.zeroes([4:0]u16);
	_ = win32.GetPrivateProfileStringW(L("confirm"), L("skip_kill"), L("0"), &skip_buf, 4, &path);
	prefs.skip_kill_confirm = if (skip_buf[0] == '1') 1 else 0;
	var aot_buf: [4:0]u16 = std.mem.zeroes([4:0]u16);
	_ = win32.GetPrivateProfileStringW(L("window"), L("always_on_top"), L("0"), &aot_buf, 4, &path);
	prefs.always_on_top = if (aot_buf[0] == '1') 1 else 0;
	var tree_buf: [4:0]u16 = std.mem.zeroes([4:0]u16);
	_ = win32.GetPrivateProfileStringW(L("view"), L("tree_mode"), L("0"), &tree_buf, 4, &path);
	prefs.tree_mode = if (tree_buf[0] == '1') 1 else 0;
	var startmin_buf: [4:0]u16 = std.mem.zeroes([4:0]u16);
	_ = win32.GetPrivateProfileStringW(L("window"), L("start_minimized_to_tray"), L("0"), &startmin_buf, 4, &path);
	prefs.start_minimized_to_tray = if (startmin_buf[0] == '1') 1 else 0;
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
	i = 0;
	while (i < COL_COUNT) : (i += 1) {
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		var val: [4:0]u16 = std.mem.zeroes([4:0]u16);
		_ = win32.wnsprintfW(&key, 64, L("%s_visible"), COLUMNS[i].label);
		var def: [2:0]u16 = .{ if (COLUMNS[i].default_visible != 0) '1' else '0', 0 };
		_ = win32.GetPrivateProfileStringW(L("columns"), &key, &def, &val, 4, &path);
		prefs.visible[i] = if (COLUMNS[i].always_visible != 0 or val[0] == '1') 1 else 0;
	}
}

pub export fn settings_save(prefs: *const SortPrefs) callconv(.c) void {
	var path: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
	getIniPath(&path);
	var i: usize = 0;
	while (i < COL_COUNT) : (i += 1) {
		if (COLUMNS[i].field == prefs.field)
			_ = win32.WritePrivateProfileStringW(L("sort"), L("field"), COLUMNS[i].label, &path);
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		_ = win32.wnsprintfW(&key, 64, L("%s_desc"), COLUMNS[i].label);
		_ = win32.WritePrivateProfileStringW(L("sort"), &key, if (prefs.desc[i] != 0) L("1") else L("0"), &path);
	}
	var ms_str: [16:0]u16 = std.mem.zeroes([16:0]u16);
	_ = win32.wnsprintfW(&ms_str, 16, L("%u"), prefs.refresh_ms);
	_ = win32.WritePrivateProfileStringW(L("refresh"), L("interval_ms"), &ms_str, &path);
	_ = win32.WritePrivateProfileStringW(L("confirm"), L("skip_kill"), if (prefs.skip_kill_confirm != 0) L("1") else L("0"), &path);
	_ = win32.WritePrivateProfileStringW(L("window"), L("always_on_top"), if (prefs.always_on_top != 0) L("1") else L("0"), &path);
	_ = win32.WritePrivateProfileStringW(L("view"), L("tree_mode"), if (prefs.tree_mode != 0) L("1") else L("0"), &path);
	_ = win32.WritePrivateProfileStringW(L("window"), L("start_minimized_to_tray"), if (prefs.start_minimized_to_tray != 0) L("1") else L("0"), &path);
	if (prefs.window_width > 0) {
		var pos_str: [16:0]u16 = std.mem.zeroes([16:0]u16);
		_ = win32.wnsprintfW(&pos_str, 16, L("%d"), prefs.window_left);
		_ = win32.WritePrivateProfileStringW(L("window"), L("left"), &pos_str, &path);
		_ = win32.wnsprintfW(&pos_str, 16, L("%d"), prefs.window_top);
		_ = win32.WritePrivateProfileStringW(L("window"), L("top"), &pos_str, &path);
		_ = win32.wnsprintfW(&pos_str, 16, L("%d"), prefs.window_width);
		_ = win32.WritePrivateProfileStringW(L("window"), L("width"), &pos_str, &path);
		_ = win32.wnsprintfW(&pos_str, 16, L("%d"), prefs.window_height);
		_ = win32.WritePrivateProfileStringW(L("window"), L("height"), &pos_str, &path);
	}
	i = 0;
	while (i < COL_COUNT) : (i += 1) {
		if (COLUMNS[i].always_visible != 0) continue;
		var key: [64:0]u16 = std.mem.zeroes([64:0]u16);
		_ = win32.wnsprintfW(&key, 64, L("%s_visible"), COLUMNS[i].label);
		_ = win32.WritePrivateProfileStringW(L("columns"), &key, if (prefs.visible[i] != 0) L("1") else L("0"), &path);
	}
}
