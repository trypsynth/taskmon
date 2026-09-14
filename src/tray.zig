const std = @import("std");
const win32 = @import("win32.zig");
const wfmt = @import("wfmt.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

var s_uid: win32.UINT = 1;
var s_hwnd: win32.HWND = null;
var s_msg: win32.UINT = 0;
var s_name: [64]u16 = std.mem.zeroes([64]u16);

pub fn add(hwnd: win32.HWND, callback_msg: win32.UINT, app_name: [*:0]const u16) void {
	s_hwnd = hwnd;
	s_msg = callback_msg;
	_ = win32.lstrcpyW(@ptrCast(&s_name), app_name);
	var nid: win32.NOTIFYICONDATAW = std.mem.zeroes(win32.NOTIFYICONDATAW);
	nid.cbSize = @sizeOf(win32.NOTIFYICONDATAW);
	nid.hWnd = s_hwnd;
	nid.uID = s_uid;
	nid.uFlags = win32.NIF_ICON | win32.NIF_TIP | win32.NIF_MESSAGE;
	nid.uCallbackMessage = s_msg;
	nid.hIcon = win32.LoadImageW(null, @ptrFromInt(win32.IDI_APPLICATION), win32.IMAGE_ICON, 0, 0, win32.LR_SHARED | win32.LR_DEFAULTSIZE);
	_ = win32.lstrcpyW(@ptrCast(&nid.szTip), @ptrCast(&s_name));
	_ = win32.Shell_NotifyIconW(win32.NIM_ADD, &nid);
}

pub fn remove() void {
	var nid: win32.NOTIFYICONDATAW = std.mem.zeroes(win32.NOTIFYICONDATAW);
	nid.cbSize = @sizeOf(win32.NOTIFYICONDATAW);
	nid.hWnd = s_hwnd;
	nid.uID = s_uid;
	_ = win32.Shell_NotifyIconW(win32.NIM_DELETE, &nid);
}

/// Longest tooltip template the user can enter. NOTIFYICONDATAW.szTip holds 128
/// characters, so the template is capped well below that to leave room for the
/// values it expands into.
pub const TEMPLATE_LEN = 96;

pub const DEFAULT_TEMPLATE = L("CPU {cpu}%, {mem} memory used");

// Tokens are deliberately system-wide and cheap to read, so the tooltip shows
// the same thing no matter which tab happens to be open, and costs nothing to
// keep current while the window is hidden.
pub const TOKENS = L("{cpu} {mem} {mem_total} {mem_percent} {processes} {threads} {handles}");

var prev_idle: u64 = 0;
var prev_kernel: u64 = 0;
var prev_user: u64 = 0;

fn fileTimeTo64(ft: win32.FILETIME) u64 {
	return (@as(u64, ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
}

// Whole-system CPU from the kernel's own totals rather than the sum of the
// process list, so it stays correct on the Services tab and while hidden.
// Returns -1 until a second sample exists to difference against.
fn systemCpuPercent() f64 {
	var idle_ft: win32.FILETIME = undefined;
	var kernel_ft: win32.FILETIME = undefined;
	var user_ft: win32.FILETIME = undefined;
	if (win32.GetSystemTimes(&idle_ft, &kernel_ft, &user_ft) == 0) return -1;
	const idle = fileTimeTo64(idle_ft);
	const kernel = fileTimeTo64(kernel_ft);
	const user = fileTimeTo64(user_ft);
	defer {
		prev_idle = idle;
		prev_kernel = kernel;
		prev_user = user;
	}
	if (prev_kernel == 0 and prev_user == 0) return -1;
	// Kernel time already includes idle, so the two deltas are the whole budget.
	const total = (kernel -% prev_kernel) +% (user -% prev_user);
	if (total == 0) return -1;
	const busy = total -% (idle -% prev_idle);
	return @as(f64, @floatFromInt(busy)) * 100.0 / @as(f64, @floatFromInt(total));
}

fn appendText(out: [*:0]u16, cap: usize, pos: *usize, text: [*:0]const u16) void {
	var i: usize = 0;
	while (text[i] != 0 and pos.* < cap - 1) : (i += 1) {
		out[pos.*] = text[i];
		pos.* += 1;
	}
}

fn appendPercent(out: [*:0]u16, cap: usize, pos: *usize, value: f64) void {
	var buf: [32:0]u16 = std.mem.zeroes([32:0]u16);
	if (value < 0) {
		wfmt.format(&buf, 32, "--", .{});
	} else {
		var whole: i32 = @intFromFloat(value);
		var frac: i32 = @intFromFloat((value - @as(f64, @floatFromInt(whole))) * 100.0 + 0.5);
		if (frac >= 100) {
			whole += 1;
			frac = 0;
		}
		wfmt.format(&buf, 32, "%d.%02d", .{ whole, frac });
	}
	appendText(out, cap, pos, &buf);
}

fn appendBytes(out: [*:0]u16, cap: usize, pos: *usize, bytes: u64) void {
	var buf: [64:0]u16 = std.mem.zeroes([64:0]u16);
	_ = win32.StrFormatByteSizeW(@intCast(bytes), &buf, 64);
	appendText(out, cap, pos, &buf);
}

fn appendUint(out: [*:0]u16, cap: usize, pos: *usize, value: win32.DWORD) void {
	var buf: [32:0]u16 = std.mem.zeroes([32:0]u16);
	wfmt.format(&buf, 32, "%u", .{value});
	appendText(out, cap, pos, &buf);
}

fn tokenMatches(template: [*:0]const u16, at: usize, name: []const u8) bool {
	for (name, 0..) |c, i| {
		if (template[at + i] != c) return false;
	}
	return template[at + name.len] == '}';
}

/// Expands the user's template into `out`. An unrecognised token is copied
/// through unchanged so a typo shows up in the tooltip instead of vanishing.
fn expand(template: [*:0]const u16, out: [*:0]u16, cap: usize) void {
	var mem: win32.MEMORYSTATUSEX = std.mem.zeroes(win32.MEMORYSTATUSEX);
	mem.dwLength = @sizeOf(win32.MEMORYSTATUSEX);
	_ = win32.GlobalMemoryStatusEx(&mem);
	var perf: win32.PERFORMANCE_INFORMATION = std.mem.zeroes(win32.PERFORMANCE_INFORMATION);
	perf.cb = @sizeOf(win32.PERFORMANCE_INFORMATION);
	const have_perf = win32.K32GetPerformanceInfo(&perf, perf.cb) != 0;
	const used = mem.ullTotalPhys - mem.ullAvailPhys;
	const cpu = systemCpuPercent();
	var pos: usize = 0;
	var i: usize = 0;
	while (template[i] != 0 and pos < cap - 1) {
		if (template[i] != '{') {
			out[pos] = template[i];
			pos += 1;
			i += 1;
			continue;
		}
		const start = i + 1;
		if (tokenMatches(template, start, "cpu")) {
			appendPercent(out, cap, &pos, cpu);
			i = start + 4;
		} else if (tokenMatches(template, start, "mem")) {
			appendBytes(out, cap, &pos, used);
			i = start + 4;
		} else if (tokenMatches(template, start, "mem_total")) {
			appendBytes(out, cap, &pos, mem.ullTotalPhys);
			i = start + 10;
		} else if (tokenMatches(template, start, "mem_percent")) {
			appendPercent(out, cap, &pos, if (mem.ullTotalPhys == 0) -1 else @as(f64, @floatFromInt(used)) * 100.0 / @as(f64, @floatFromInt(mem.ullTotalPhys)));
			i = start + 12;
		} else if (tokenMatches(template, start, "processes")) {
			appendUint(out, cap, &pos, if (have_perf) perf.ProcessCount else 0);
			i = start + 10;
		} else if (tokenMatches(template, start, "threads")) {
			appendUint(out, cap, &pos, if (have_perf) perf.ThreadCount else 0);
			i = start + 8;
		} else if (tokenMatches(template, start, "handles")) {
			appendUint(out, cap, &pos, if (have_perf) perf.HandleCount else 0);
			i = start + 8;
		} else {
			out[pos] = template[i];
			pos += 1;
			i += 1;
		}
	}
	out[pos] = 0;
}

pub fn updateTip(template: [*:0]const u16) void {
	var nid: win32.NOTIFYICONDATAW = std.mem.zeroes(win32.NOTIFYICONDATAW);
	nid.cbSize = @sizeOf(win32.NOTIFYICONDATAW);
	nid.hWnd = s_hwnd;
	nid.uID = s_uid;
	nid.uFlags = win32.NIF_TIP;
	// An empty template would leave the icon with no tooltip at all, so fall back
	// to the application name the way it reads before the first update.
	if (template[0] == 0) {
		_ = win32.lstrcpyW(@ptrCast(&nid.szTip), @ptrCast(&s_name));
	} else {
		expand(template, @ptrCast(&nid.szTip), 128);
	}
	_ = win32.Shell_NotifyIconW(win32.NIM_MODIFY, &nid);
}

pub fn restore() void {
	_ = win32.ShowWindow(s_hwnd, win32.SW_SHOW);
	_ = win32.SetForegroundWindow(s_hwnd);
}
