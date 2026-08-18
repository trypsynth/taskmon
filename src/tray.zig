const std = @import("std");
const win32 = @import("win32.zig");

var s_uid: win32.UINT = 1;
var s_hwnd: win32.HWND = null;
var s_msg: win32.UINT = 0;
var s_name: [64]u16 = std.mem.zeroes([64]u16);

pub export fn add(hwnd: win32.HWND, callback_msg: win32.UINT, app_name: [*:0]const u16) callconv(.c) void {
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

pub export fn remove() callconv(.c) void {
	var nid: win32.NOTIFYICONDATAW = std.mem.zeroes(win32.NOTIFYICONDATAW);
	nid.cbSize = @sizeOf(win32.NOTIFYICONDATAW);
	nid.hWnd = s_hwnd;
	nid.uID = s_uid;
	_ = win32.Shell_NotifyIconW(win32.NIM_DELETE, &nid);
}

pub export fn updateTip(cpu_pct: f64) callconv(.c) void {
	var nid: win32.NOTIFYICONDATAW = std.mem.zeroes(win32.NOTIFYICONDATAW);
	nid.cbSize = @sizeOf(win32.NOTIFYICONDATAW);
	nid.hWnd = s_hwnd;
	nid.uID = s_uid;
	nid.uFlags = win32.NIF_TIP;
	var ms: win32.MEMORYSTATUSEX = std.mem.zeroes(win32.MEMORYSTATUSEX);
	ms.dwLength = @sizeOf(win32.MEMORYSTATUSEX);
	_ = win32.GlobalMemoryStatusEx(&ms);
	const mem_mb: i32 = @intCast((ms.ullTotalPhys - ms.ullAvailPhys) / (1024 * 1024));
	var cpu_whole: i32 = @intFromFloat(cpu_pct);
	var cpu_frac: i32 = @intFromFloat((cpu_pct - @as(f64, @floatFromInt(cpu_whole))) * 100.0 + 0.5);
	if (cpu_frac >= 100) {
		cpu_whole += 1;
		cpu_frac = 0;
	}
	if (mem_mb > 1024) {
		const mem_gb_int: i32 = @divTrunc(mem_mb, 1024);
		const mem_gb_frac: i32 = @divTrunc(@mod(mem_mb, 1024) * 100, 1024);
		_ = win32.wnsprintfW(@ptrCast(&nid.szTip), 128, std.unicode.utf8ToUtf16LeStringLiteral("CPU %d.%02d%%, %d.%02d GB memory used"), cpu_whole, cpu_frac, mem_gb_int, mem_gb_frac);
	} else {
		_ = win32.wnsprintfW(@ptrCast(&nid.szTip), 128, std.unicode.utf8ToUtf16LeStringLiteral("CPU %d.%02d%%, %d MB memory used"), cpu_whole, cpu_frac, mem_mb);
	}
	_ = win32.Shell_NotifyIconW(win32.NIM_MODIFY, &nid);
}

pub export fn restore() callconv(.c) void {
	_ = win32.ShowWindow(s_hwnd, win32.SW_SHOW);
	_ = win32.SetForegroundWindow(s_hwnd);
}
