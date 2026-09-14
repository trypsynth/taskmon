const std = @import("std");
const win32 = @import("win32.zig");
const resource = @import("resource.zig");
const state = @import("state.zig");
const theme = @import("theme.zig");
const wfmt = @import("wfmt.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

pub const NAME_LEN = 64;
pub const DISPLAY_LEN = 128;
const ACCOUNT_LEN = 128;
const PATH_LEN = 260;
const GROUP_LEN = 64;

// Fixed-size and extern so the whole table can be sorted with raw byte swaps,
// the same way process.zig sorts its entries without a heap-allocated scratch
// per comparison.
pub const ServiceEntry = extern struct {
	name: [NAME_LEN:0]u16,
	display: [DISPLAY_LEN:0]u16,
	log_on_as: [ACCOUNT_LEN:0]u16,
	binary_path: [PATH_LEN:0]u16,
	group: [GROUP_LEN:0]u16,
	pid: win32.DWORD,
	current_state: win32.DWORD,
	start_type: win32.DWORD,
	service_type: win32.DWORD,
};

pub const SortField = enum(i32) {
	name,
	display,
	status,
	start_type,
	pid,
	log_on_as,
	binary_path,
	service_type,
	group,
};

pub const ColumnDef = struct {
	label: win32.LPCWSTR,
	width: i32,
	field: SortField,
	always_visible: bool,
	default_visible: bool,
};

pub const COL_COUNT: usize = 9;
pub const COLUMNS: [COL_COUNT]ColumnDef = .{
	.{ .label = L("Name"), .width = 200, .field = .name, .always_visible = true, .default_visible = true },
	.{ .label = L("Display Name"), .width = 300, .field = .display, .always_visible = false, .default_visible = true },
	.{ .label = L("Status"), .width = 110, .field = .status, .always_visible = false, .default_visible = true },
	.{ .label = L("Startup Type"), .width = 110, .field = .start_type, .always_visible = false, .default_visible = true },
	.{ .label = L("PID"), .width = 80, .field = .pid, .always_visible = false, .default_visible = true },
	.{ .label = L("Log On As"), .width = 180, .field = .log_on_as, .always_visible = false, .default_visible = false },
	.{ .label = L("Binary Path"), .width = 400, .field = .binary_path, .always_visible = false, .default_visible = false },
	.{ .label = L("Service Type"), .width = 130, .field = .service_type, .always_visible = false, .default_visible = false },
	.{ .label = L("Group"), .width = 130, .field = .group, .always_visible = false, .default_visible = false },
};

// populate() renders COLUMNS[0] from the item label rather than a subitem, and
// order[0] is pinned to it, so it has to be the one and only always-visible
// column - the same contract settings.COLUMNS carries for the process list.
comptime {
	if (COLUMNS[0].field != .name or !COLUMNS[0].always_visible)
		@compileError("COLUMNS[0] must be the always-visible Name column");
	for (COLUMNS[1..]) |col| {
		if (col.always_visible)
			@compileError("only COLUMNS[0] may be always_visible");
	}
}

var entries: ?[*]ServiceEntry = null;
var count: i32 = 0;

fn heapAlloc(bytes: usize) ?*anyopaque {
	if (bytes == 0) return null;
	return win32.HeapAlloc(win32.GetProcessHeap(), 0, bytes);
}

fn heapFree(p: ?*anyopaque) void {
	if (p != null) _ = win32.HeapFree(win32.GetProcessHeap(), 0, p);
}

fn stateLabel(s: win32.DWORD) win32.LPCWSTR {
	return switch (s) {
		win32.SERVICE_STOPPED => L("Stopped"),
		win32.SERVICE_START_PENDING => L("Starting"),
		win32.SERVICE_STOP_PENDING => L("Stopping"),
		win32.SERVICE_RUNNING => L("Running"),
		win32.SERVICE_CONTINUE_PENDING => L("Resuming"),
		win32.SERVICE_PAUSE_PENDING => L("Pausing"),
		win32.SERVICE_PAUSED => L("Paused"),
		else => L(""),
	};
}

// The base type comes with flags layered on top: SERVICE_INTERACTIVE_PROCESS,
// SERVICE_USERSERVICE_INSTANCE for the per-user copies Windows spawns under a
// suffixed name like AarSvc_16b23, and SERVICE_PKG_SERVICE for the packaged ones
// sc reports as WIN32_PACKAGED_PROCESS. Mask all three off so those report the
// same type as any other service instead of falling through to blank. Driver
// types cannot appear while the enumeration asks for SERVICE_WIN32 only, but
// they cost nothing to name if that filter is ever widened.
const TYPE_FLAGS: win32.DWORD = win32.SERVICE_INTERACTIVE_PROCESS | win32.SERVICE_USERSERVICE_INSTANCE | win32.SERVICE_PKG_SERVICE;

fn serviceTypeLabel(t: win32.DWORD) win32.LPCWSTR {
	return switch (t & ~TYPE_FLAGS) {
		win32.SERVICE_KERNEL_DRIVER => L("Kernel Driver"),
		win32.SERVICE_FILE_SYSTEM_DRIVER => L("File System Driver"),
		win32.SERVICE_WIN32_OWN_PROCESS => L("Own Process"),
		win32.SERVICE_WIN32_SHARE_PROCESS => L("Shared Process"),
		win32.SERVICE_USER_OWN_PROCESS => L("User Own Process"),
		win32.SERVICE_USER_SHARE_PROCESS => L("User Shared Process"),
		else => L(""),
	};
}

fn startTypeLabel(t: win32.DWORD) win32.LPCWSTR {
	return switch (t) {
		win32.SERVICE_BOOT_START => L("Boot"),
		win32.SERVICE_SYSTEM_START => L("System"),
		win32.SERVICE_AUTO_START => L("Automatic"),
		win32.SERVICE_DEMAND_START => L("Manual"),
		win32.SERVICE_DISABLED => L("Disabled"),
		else => L(""),
	};
}

// Everything EnumServicesStatusExW does not return comes from one config query,
// so the open-and-query is paid once per service and fills five fields rather
// than just the startup type. SERVICE_QUERY_CONFIG is granted to ordinary users,
// so this still works unelevated; a service that refuses the open keeps the
// zeroed defaults and renders as blanks rather than failing the whole refresh.
fn readConfig(scm: win32.HANDLE, name: win32.LPCWSTR, dst: *ServiceEntry) void {
	dst.start_type = 0xFFFFFFFF;
	const svc = win32.OpenServiceW(scm, name, win32.SERVICE_QUERY_CONFIG);
	if (svc == null) return;
	defer _ = win32.CloseServiceHandle(svc);
	var needed: win32.DWORD = 0;
	_ = win32.QueryServiceConfigW(svc, null, 0, &needed);
	if (needed == 0) return;
	const buf = heapAlloc(needed) orelse return;
	defer heapFree(buf);
	const cfg: *win32.QUERY_SERVICE_CONFIGW = @ptrCast(@alignCast(buf));
	if (win32.QueryServiceConfigW(svc, cfg, needed, &needed) == 0) return;
	dst.start_type = cfg.dwStartType;
	dst.service_type = cfg.dwServiceType;
	if (cfg.lpServiceStartName) |v| _ = win32.lstrcpynW(@ptrCast(&dst.log_on_as), v, ACCOUNT_LEN);
	if (cfg.lpBinaryPathName) |v| _ = win32.lstrcpynW(@ptrCast(&dst.binary_path), v, PATH_LEN);
	if (cfg.lpLoadOrderGroup) |v| _ = win32.lstrcpynW(@ptrCast(&dst.group), v, GROUP_LEN);
}

pub fn refresh() void {
	const scm = win32.OpenSCManagerW(null, null, win32.SC_MANAGER_ENUMERATE_SERVICE | win32.SC_MANAGER_CONNECT);
	if (scm == null) return;
	defer _ = win32.CloseServiceHandle(scm);
	var needed: win32.DWORD = 0;
	var returned: win32.DWORD = 0;
	var resume_handle: win32.DWORD = 0;
	_ = win32.EnumServicesStatusExW(scm, win32.SC_ENUM_PROCESS_INFO, win32.SERVICE_WIN32, win32.SERVICE_STATE_ALL, null, 0, &needed, &returned, &resume_handle, null);
	if (needed == 0) return;
	const raw = heapAlloc(needed) orelse return;
	defer heapFree(raw);
	const buf: [*]u8 = @ptrCast(raw);
	resume_handle = 0;
	if (win32.EnumServicesStatusExW(scm, win32.SC_ENUM_PROCESS_INFO, win32.SERVICE_WIN32, win32.SERVICE_STATE_ALL, buf, needed, &needed, &returned, &resume_handle, null) == 0) return;
	const table = heapAlloc(@as(usize, returned) * @sizeOf(ServiceEntry)) orelse return;
	heapFree(@ptrCast(entries));
	entries = @ptrCast(@alignCast(table));
	count = 0;
	const sv: [*]win32.ENUM_SERVICE_STATUS_PROCESSW = @ptrCast(@alignCast(buf));
	for (0..returned) |i| {
		const name = sv[i].lpServiceName orelse continue;
		const dst = &entries.?[@intCast(count)];
		dst.* = std.mem.zeroes(ServiceEntry);
		_ = win32.lstrcpynW(@ptrCast(&dst.name), name, NAME_LEN);
		if (sv[i].lpDisplayName) |disp| _ = win32.lstrcpynW(@ptrCast(&dst.display), disp, DISPLAY_LEN);
		dst.pid = sv[i].ServiceStatusProcess.dwProcessId;
		dst.current_state = sv[i].ServiceStatusProcess.dwCurrentState;
		readConfig(scm, name, dst);
		count += 1;
	}
	sortEntries();
}

fn compare(a: *const ServiceEntry, b: *const ServiceEntry) bool {
	const order: i32 = switch (state.svc_field) {
		.name => win32.StrCmpIW(@ptrCast(&a.name), @ptrCast(&b.name)),
		.display => win32.StrCmpIW(@ptrCast(&a.display), @ptrCast(&b.display)),
		.status => @as(i32, @intCast(a.current_state)) - @as(i32, @intCast(b.current_state)),
		.start_type => @as(i32, @intCast(a.start_type & 0xFF)) - @as(i32, @intCast(b.start_type & 0xFF)),
		.pid => @as(i32, @bitCast(a.pid)) - @as(i32, @bitCast(b.pid)),
		.log_on_as => win32.StrCmpIW(@ptrCast(&a.log_on_as), @ptrCast(&b.log_on_as)),
		.binary_path => win32.StrCmpIW(@ptrCast(&a.binary_path), @ptrCast(&b.binary_path)),
		.group => win32.StrCmpIW(@ptrCast(&a.group), @ptrCast(&b.group)),
		.service_type => @as(i32, @intCast(a.service_type & 0xFFF)) - @as(i32, @intCast(b.service_type & 0xFFF)),
	};
	return if (state.svc_desc) order > 0 else order < 0;
}

// Insertion sort: a few hundred services at most, and it keeps equal rows in
// enumeration order so the list doesn't shuffle between refreshes.
fn sortEntries() void {
	const es = entries orelse return;
	var scratch: ServiceEntry = undefined;
	var i: usize = 1;
	while (i < @as(usize, @intCast(count))) : (i += 1) {
		@memcpy(std.mem.asBytes(&scratch), std.mem.asBytes(&es[i]));
		var j = i;
		while (j > 0 and compare(&scratch, &es[j - 1])) : (j -= 1)
			@memcpy(std.mem.asBytes(&es[j]), std.mem.asBytes(&es[j - 1]));
		@memcpy(std.mem.asBytes(&es[j]), std.mem.asBytes(&scratch));
	}
}

// Rebuilds both the list columns and the hidden sort buttons from the saved
// order and visibility, the same shape as sortbar.applyColumns does for
// processes. Both are torn down and recreated because a column can appear,
// disappear, or change place in one go.
pub fn applyColumns() void {
	for (0..@intCast(state.svc_sort_count)) |i| {
		_ = win32.DestroyWindow(state.svc_sort_btns[i]);
		state.svc_sort_btns[i] = null;
	}
	state.svc_sort_count = 0;
	const header = win32.SendMessageW(state.hwnd_svc_list, win32.LVM_GETHEADER, 0, 0);
	const header_hwnd: win32.HWND = @ptrFromInt(@as(usize, @bitCast(header)));
	var old: i32 = @as(i32, @intCast(win32.SendMessageW(header_hwnd, win32.HDM_GETITEMCOUNT, 0, 0))) - 1;
	while (old >= 0) : (old -= 1) _ = win32.SendMessageW(state.hwnd_svc_list, win32.LVM_DELETECOLUMN, @intCast(old), 0);
	// Sorting by a column that has just been hidden would leave no way back to
	// it, so fall back to Name.
	var field_shown = false;
	for (0..COL_COUNT) |i| {
		if (COLUMNS[i].field == state.svc_field and state.prefs.svc_visible[i]) field_shown = true;
	}
	if (!field_shown) state.svc_field = .name;
	var btn_x: i32 = 0;
	var lv_col: i32 = 0;
	for (0..COL_COUNT) |pos| {
		const ci: usize = state.prefs.svc_order[pos];
		if (!state.prefs.svc_visible[ci]) continue;
		const bi: usize = @intCast(state.svc_sort_count);
		state.svc_sort_btns[bi] = win32.CreateWindowExW(0, L("BUTTON"), COLUMNS[ci].label, win32.WS_CHILD | win32.WS_VISIBLE | win32.BS_RADIOBUTTON, btn_x, 0, COLUMNS[ci].width, 1, state.hwnd_svc_sort_group, @ptrFromInt(@as(usize, @intCast(resource.ID_SVC_SORT_BASE)) + ci), win32.GetModuleHandleW(null), null);
		_ = win32.SetWindowSubclass(state.svc_sort_btns[bi], sortBtnProc, @intCast(bi), 0);
		state.svc_sort_cols[bi] = @intCast(ci);
		btn_x += COLUMNS[ci].width;
		state.svc_sort_count += 1;
		var lvc: win32.LVCOLUMNW = std.mem.zeroes(win32.LVCOLUMNW);
		lvc.mask = win32.LVCF_TEXT | win32.LVCF_WIDTH | win32.LVCF_SUBITEM;
		lvc.pszText = @constCast(COLUMNS[ci].label);
		lvc.cx = COLUMNS[ci].width;
		lvc.iSubItem = lv_col;
		_ = win32.SendMessageW(state.hwnd_svc_list, win32.LVM_INSERTCOLUMNW, @intCast(lv_col), @bitCast(@intFromPtr(&lvc)));
		lv_col += 1;
	}
	_ = win32.SetWindowPos(state.hwnd_svc_sort_group, null, 0, 0, btn_x, 1, win32.SWP_NOMOVE | win32.SWP_NOZORDER | win32.SWP_NOACTIVATE);
	updateSortUi();
	updateTabStop();
	applyTheme();
}

fn formatColumn(e: *const ServiceEntry, field: SortField, buf: [*:0]u16, len: i32) void {
	switch (field) {
		.name => buf[0] = 0,
		.display => _ = win32.lstrcpynW(buf, @ptrCast(&e.display), len),
		.status => _ = win32.lstrcpynW(buf, stateLabel(e.current_state), len),
		.start_type => _ = win32.lstrcpynW(buf, startTypeLabel(e.start_type), len),
		.pid => {
			if (e.pid != 0) wfmt.format(buf, len, "%u", .{e.pid}) else buf[0] = 0;
		},
		.log_on_as => _ = win32.lstrcpynW(buf, @ptrCast(&e.log_on_as), len),
		.binary_path => _ = win32.lstrcpynW(buf, @ptrCast(&e.binary_path), len),
		.group => _ = win32.lstrcpynW(buf, @ptrCast(&e.group), len),
		.service_type => _ = win32.lstrcpynW(buf, serviceTypeLabel(e.service_type), len),
	}
}

pub fn getSelectedIndex() i32 {
	return @intCast(win32.SendMessageW(state.hwnd_svc_list, win32.LVM_GETNEXTITEM, @bitCast(@as(isize, -1)), win32.LVNI_SELECTED));
}

/// Name of the selected service, or an empty string when nothing is selected.
pub fn getSelectedName(buf: [*:0]u16) void {
	buf[0] = 0;
	const idx = getSelectedIndex();
	const es = entries orelse return;
	if (idx < 0 or idx >= count) return;
	_ = win32.lstrcpynW(buf, @ptrCast(&es[@intCast(idx)].name), NAME_LEN);
}

pub fn getSelectedPid() win32.DWORD {
	const idx = getSelectedIndex();
	const es = entries orelse return 0;
	if (idx < 0 or idx >= count) return 0;
	return es[@intCast(idx)].pid;
}

pub fn getSelectedState() win32.DWORD {
	const idx = getSelectedIndex();
	const es = entries orelse return 0;
	if (idx < 0 or idx >= count) return 0;
	return es[@intCast(idx)].current_state;
}

pub fn populate() void {
	const es = entries orelse return;
	// The list is rebuilt from scratch, so remember the selection by service name
	// (indices shift when a service starts or stops) and put it back afterwards.
	var selected: [NAME_LEN:0]u16 = std.mem.zeroes([NAME_LEN:0]u16);
	getSelectedName(&selected);
	var new_selected: i32 = -1;
	_ = win32.SendMessageW(state.hwnd_svc_list, win32.WM_SETREDRAW, 0, 0);
	_ = win32.SendMessageW(state.hwnd_svc_list, win32.LVM_DELETEALLITEMS, 0, 0);
	for (0..@intCast(count)) |i| {
		const e = &es[i];
		var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
		lvi.mask = win32.LVIF_TEXT;
		lvi.iItem = @intCast(i);
		lvi.pszText = @ptrCast(&e.name);
		_ = win32.SendMessageW(state.hwnd_svc_list, win32.LVM_INSERTITEMW, 0, @bitCast(@intFromPtr(&lvi)));
		if (selected[0] != 0 and win32.StrCmpIW(&selected, @ptrCast(&e.name)) == 0) new_selected = @intCast(i);
		var buf: [300:0]u16 = std.mem.zeroes([300:0]u16);
		for (1..@intCast(state.svc_sort_count)) |c| {
			formatColumn(e, COLUMNS[@intCast(state.svc_sort_cols[c])].field, &buf, 300);
			var set_lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
			set_lvi.iSubItem = @intCast(c);
			set_lvi.pszText = &buf;
			_ = win32.SendMessageW(state.hwnd_svc_list, win32.LVM_SETITEMTEXTW, @intCast(i), @bitCast(@intFromPtr(&set_lvi)));
		}
	}
	if (count > 0) {
		var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
		lvi.stateMask = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
		lvi.state = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
		_ = win32.SendMessageW(state.hwnd_svc_list, win32.LVM_SETITEMSTATE, @intCast(if (new_selected >= 0) new_selected else 0), @bitCast(@intFromPtr(&lvi)));
	}
	_ = win32.SendMessageW(state.hwnd_svc_list, win32.WM_SETREDRAW, 1, 0);
	_ = win32.InvalidateRect(state.hwnd_svc_list, null, 0);
}

pub fn doRefresh() void {
	refresh();
	populate();
	updateStatusBar();
}

// The status bar is shared with the process tab, so whichever tab refreshed last
// owns the text. Services report their own totals rather than leaving a stale
// process count sitting there.
fn updateStatusBar() void {
	if (state.hwnd_status == null) return;
	var running: i32 = 0;
	if (entries) |es| {
		for (0..@intCast(count)) |i| {
			if (es[i].current_state == win32.SERVICE_RUNNING) running += 1;
		}
	}
	var text: [128:0]u16 = std.mem.zeroes([128:0]u16);
	wfmt.format(&text, 128, "  %d services  |  %d running  |  %d stopped", .{ count, running, count - running });
	_ = win32.SendMessageW(state.hwnd_status, win32.SB_SETTEXTW, 0, @bitCast(@intFromPtr(&text)));
}

/// Re-sorts and redisplays the services already fetched, without asking the SCM again.
pub fn resort() void {
	sortEntries();
	populate();
	updateStatusBar();
}

pub const Action = enum { start, stop, restart };

// Returns the Win32 error the SCM reported, or 0 on success. Stopping is
// deliberately not waited on past the status handshake: a service that takes
// its time shows up as Stopping and settles on the next refresh.
pub fn control(name: win32.LPCWSTR, action: Action) win32.DWORD {
	const access: win32.DWORD = switch (action) {
		.start => win32.SERVICE_START | win32.SERVICE_QUERY_STATUS,
		.stop => win32.SERVICE_STOP | win32.SERVICE_QUERY_STATUS,
		.restart => win32.SERVICE_START | win32.SERVICE_STOP | win32.SERVICE_QUERY_STATUS,
	};
	const scm = win32.OpenSCManagerW(null, null, win32.SC_MANAGER_CONNECT);
	if (scm == null) return win32.GetLastError();
	defer _ = win32.CloseServiceHandle(scm);
	const svc = win32.OpenServiceW(scm, name, access);
	if (svc == null) return win32.GetLastError();
	defer _ = win32.CloseServiceHandle(svc);
	if (action == .stop or action == .restart) {
		var status: win32.SERVICE_STATUS = std.mem.zeroes(win32.SERVICE_STATUS);
		if (win32.ControlService(svc, win32.SERVICE_CONTROL_STOP, &status) == 0) {
			const err = win32.GetLastError();
			// Restarting something already stopped is the caller's intent, not an error.
			if (!(action == .restart and err == win32.ERROR_SERVICE_NOT_ACTIVE)) return err;
		}
		if (action == .stop) return 0;
		waitForStop(svc);
	}
	if (win32.StartServiceW(svc, 0, null) == 0) {
		const err = win32.GetLastError();
		if (err != win32.ERROR_SERVICE_ALREADY_RUNNING) return err;
	}
	return 0;
}

// A restart has to see the service actually stop before starting it again.
// Capped so a wedged service can't hang the UI thread; if it outlasts the cap
// the StartServiceW below simply fails and the caller reports that.
fn waitForStop(svc: win32.HANDLE) void {
	var waited: u32 = 0;
	while (waited < 10000) : (waited += 100) {
		var needed: win32.DWORD = 0;
		var ssp: win32.SERVICE_STATUS_PROCESS = std.mem.zeroes(win32.SERVICE_STATUS_PROCESS);
		if (win32.QueryServiceStatusEx(svc, win32.SC_STATUS_PROCESS_INFO, @ptrCast(&ssp), @sizeOf(win32.SERVICE_STATUS_PROCESS), &needed) == 0) return;
		if (ssp.dwCurrentState == win32.SERVICE_STOPPED) return;
		win32.Sleep(100);
	}
}

pub fn create(parent: win32.HWND, list_id: usize) void {
	state.hwnd_svc_sort_group = win32.CreateWindowExW(win32.WS_EX_CONTROLPARENT, L("BUTTON"), L("Sort by"), win32.WS_CHILD | win32.BS_GROUPBOX, 0, 0, 0, 1, parent, null, win32.GetModuleHandleW(null), null);
	_ = win32.SetWindowSubclass(state.hwnd_svc_sort_group, sortGroupProc, 0, 0);
	// Hidden label ahead of the list so MSAA/UIA name it "Services" rather than
	// reaching back to the sort group box, matching the process list.
	_ = win32.CreateWindowExW(0, L("STATIC"), L("Services"), win32.WS_CHILD | win32.SS_LEFT, 0, 0, 0, 0, parent, null, win32.GetModuleHandleW(null), null);
	state.hwnd_svc_list = win32.CreateWindowExW(0, win32.WC_LISTVIEWW, L("Services"), win32.WS_CHILD | win32.WS_TABSTOP | win32.LVS_REPORT | win32.LVS_SHOWSELALWAYS | win32.LVS_SINGLESEL, 0, 1, 760, 537, parent, @ptrFromInt(list_id), win32.GetModuleHandleW(null), null);
	_ = win32.SetWindowSubclass(state.hwnd_svc_list, listKeyProc, 0, 0);
	_ = win32.SendMessageW(state.hwnd_svc_list, win32.LVM_SETEXTENDEDLISTVIEWSTYLE, 0, win32.LVS_EX_FULLROWSELECT | win32.LVS_EX_GRIDLINES);
	// No applyColumns() here: it reads state.prefs, which WM_CREATE has not
	// loaded yet at this point. wndproc calls it after settings.load(), the same
	// way it does for the process list.
}

fn listKeyProc(hwnd: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM, id: win32.UINT_PTR, data: win32.DWORD_PTR) callconv(.c) win32.LRESULT {
	_ = id;
	_ = data;
	if (msg == win32.WM_KEYDOWN and wp == win32.VK_ESCAPE) {
		_ = win32.PostMessageW(win32.GetParent(hwnd), state.WM_HIDE_TO_TRAY, 0, 0);
		return 0;
	}
	return win32.DefSubclassProc(hwnd, msg, wp, lp);
}

// The services list gets the same hidden radio-button sort bar as the process
// list, because clicking a column header is not reachable from the keyboard.
// It is deliberately a separate copy of sortbar.zig rather than a shared
// abstraction: that one also juggles hidden columns, per-column sort directions
// and tree mode, none of which apply here. Worth extracting if a third tab
// ever needs one.
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
			_ = win32.PostMessageW(state.hwnd, state.WM_HIDE_TO_TRAY, 0, 0);
			return 0;
		}
		if (wp == win32.VK_RETURN) {
			const ctrl_id: win32.WPARAM = @intCast(win32.GetDlgCtrlID(hwnd));
			_ = win32.PostMessageW(state.hwnd, win32.WM_COMMAND, ctrl_id, @bitCast(@intFromPtr(hwnd)));
			return 0;
		}
		if (wp == win32.VK_LEFT or wp == win32.VK_RIGHT) {
			var idx: i32 = -1;
			for (0..@intCast(state.svc_sort_count)) |i| {
				if (state.svc_sort_btns[i] == hwnd) {
					idx = @intCast(i);
					break;
				}
			}
			if (idx < 0) return 0;
			const next: i32 = if (wp == win32.VK_RIGHT) idx + 1 else idx - 1;
			if (next < 0 or next >= state.svc_sort_count) return 0;
			const next_ci: usize = @intCast(state.svc_sort_cols[@intCast(next)]);
			state.svc_field = COLUMNS[next_ci].field;
			// Give the destination its final label before focus lands, and only
			// relabel the rest afterwards: renaming a button that still holds
			// focus makes a screen reader read the field being left behind.
			var buf: [64:0]u16 = std.mem.zeroes([64:0]u16);
			wfmt.format(&buf, 64, "%s (%s)", .{ COLUMNS[next_ci].label, if (state.svc_desc) @as(win32.LPCWSTR, L("descending")) else @as(win32.LPCWSTR, L("ascending")) });
			_ = win32.SetWindowTextW(state.svc_sort_btns[@intCast(next)], &buf);
			_ = win32.SendMessageW(state.svc_sort_btns[@intCast(next)], win32.BM_SETCHECK, win32.BST_CHECKED, 0);
			updateTabStop();
			_ = win32.SetFocus(state.svc_sort_btns[@intCast(next)]);
			updateSortUi();
			resort();
			return 0;
		}
		if (wp == win32.VK_UP or wp == win32.VK_DOWN) return 0;
	}
	return win32.DefSubclassProc(hwnd, msg, wp, lp);
}

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

/// Only the button for the active sort field is a tab stop, so Tab lands on the
/// current choice and Left/Right move between the rest.
pub fn updateTabStop() void {
	for (0..@intCast(state.svc_sort_count)) |i| {
		var style = win32.GetWindowLongPtrW(state.svc_sort_btns[i], win32.GWL_STYLE);
		style = if (COLUMNS[@intCast(state.svc_sort_cols[i])].field == state.svc_field)
			style | @as(win32.LONG_PTR, win32.WS_TABSTOP)
		else
			style & ~@as(win32.LONG_PTR, win32.WS_TABSTOP);
		_ = win32.SetWindowLongPtrW(state.svc_sort_btns[i], win32.GWL_STYLE, style);
	}
}

pub fn updateSortUi() void {
	const header = win32.SendMessageW(state.hwnd_svc_list, win32.LVM_GETHEADER, 0, 0);
	const header_hwnd: win32.HWND = @ptrFromInt(@as(usize, @bitCast(header)));
	for (0..@intCast(state.svc_sort_count)) |i| {
		const ci: usize = @intCast(state.svc_sort_cols[i]);
		const active = COLUMNS[ci].field == state.svc_field;
		var buf: [64:0]u16 = std.mem.zeroes([64:0]u16);
		if (active) {
			wfmt.format(&buf, 64, "%s (%s)", .{ COLUMNS[ci].label, if (state.svc_desc) @as(win32.LPCWSTR, L("descending")) else @as(win32.LPCWSTR, L("ascending")) });
		} else {
			_ = win32.lstrcpyW(&buf, COLUMNS[ci].label);
		}
		_ = win32.SetWindowTextW(state.svc_sort_btns[i], &buf);
		_ = win32.SendMessageW(state.svc_sort_btns[i], win32.BM_SETCHECK, if (active) win32.BST_CHECKED else win32.BST_UNCHECKED, 0);
		var hdi: win32.HDITEMW = std.mem.zeroes(win32.HDITEMW);
		hdi.mask = win32.HDI_FORMAT;
		_ = win32.SendMessageW(header_hwnd, win32.HDM_GETITEMW, @intCast(i), @bitCast(@intFromPtr(&hdi)));
		hdi.fmt &= ~(win32.HDF_SORTUP | win32.HDF_SORTDOWN);
		if (active) hdi.fmt |= if (state.svc_desc) win32.HDF_SORTDOWN else win32.HDF_SORTUP;
		_ = win32.SendMessageW(header_hwnd, win32.HDM_SETITEMW, @intCast(i), @bitCast(@intFromPtr(&hdi)));
	}
}

/// Handles a click or Enter on one of the sort buttons. Re-picking the active
/// field flips the direction, matching the process list.
pub fn onSortCommand(index: usize) void {
	if (index >= COL_COUNT) return;
	if (COLUMNS[index].field == state.svc_field) {
		state.svc_desc = !state.svc_desc;
	} else {
		state.svc_field = COLUMNS[index].field;
		state.svc_desc = false;
	}
	updateSortUi();
	updateTabStop();
	resort();
}

pub fn applyTheme() void {
	theme.applyButton(state.hwnd_svc_sort_group);
	for (0..@intCast(state.svc_sort_count)) |i| theme.applyButton(state.svc_sort_btns[i]);
}
