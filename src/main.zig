const std = @import("std");
const win32 = @import("win32.zig");
const wndproc = @import("wndproc.zig");
const resource = @import("resource.zig");
const state = @import("state.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

// _fltused is required by the linker whenever floating point is used in a
// CRT-less build; it has no runtime meaning.
export var _fltused: c_int = 0x9875;

// The byte loops below use volatile pointers so LLVM's loop-idiom-recognize
// pass can't rewrite them into calls back to themselves (these symbols ARE
// memcpy/memset/memmove; a non-volatile loop gets "optimized" into infinite
// recursion under -O/-ReleaseSmall).
export fn memset(dest: ?*anyopaque, c: c_int, count: usize) callconv(.c) ?*anyopaque {
	const d: [*]volatile u8 = @ptrCast(dest.?);
	const byte: u8 = @truncate(@as(c_uint, @bitCast(c)));
	for (0..count) |i| d[i] = byte;
	return dest;
}

export fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, count: usize) callconv(.c) ?*anyopaque {
	const d: [*]volatile u8 = @ptrCast(dest.?);
	const s: [*]const volatile u8 = @ptrCast(src.?);
	for (0..count) |i| d[i] = s[i];
	return dest;
}

export fn memmove(dest: ?*anyopaque, src: ?*const anyopaque, count: usize) callconv(.c) ?*anyopaque {
	const d: [*]volatile u8 = @ptrCast(dest.?);
	const s: [*]const volatile u8 = @ptrCast(src.?);
	if (@intFromPtr(d) < @intFromPtr(s)) {
		for (0..count) |i| d[i] = s[i];
	} else {
		var i: usize = count;
		while (i > 0) {
			i -= 1;
			d[i] = s[i];
		}
	}
	return dest;
}

// Zig supplies its own minimal, CRT-less bootstrap before calling main() when
// targeting windows with link_libc = false, so no hand written _start/entry
// symbol is needed here.
pub fn main() void {
	const instance = win32.GetModuleHandleW(null);
	var show: c_int = win32.SW_SHOWDEFAULT;
	var si: win32.STARTUPINFOW = undefined;
	win32.GetStartupInfoW(&si);
	if (si.dwFlags & win32.STARTF_USESHOWWINDOW != 0) show = si.wShowWindow;
	const exit_code = winMain(instance, show);
	win32.ExitProcess(@bitCast(exit_code));
}

fn winMain(instance: win32.HINSTANCE, show: c_int) c_int {
	const com_init = win32.CoInitializeEx(null, win32.COINIT_APARTMENTTHREADED | win32.COINIT_DISABLE_OLE1DDE);
	state.mutex = win32.CreateMutexW(null, 1, L("Local\\TaskmonSingleInstance"));
	const mutex = state.mutex;
	if (win32.GetLastError() == win32.ERROR_ALREADY_EXISTS) {
		const existing = win32.FindWindowW(&wndproc.CLASS_NAME, null);
		if (existing != null) {
			_ = win32.ShowWindow(existing, win32.SW_SHOW);
			_ = win32.SetForegroundWindow(existing);
		}
		if (mutex != null) _ = win32.CloseHandle(mutex);
		if (com_init >= 0) win32.CoUninitialize();
		return 0;
	}
	var wc: win32.WNDCLASSEXW = std.mem.zeroes(win32.WNDCLASSEXW);
	wc.cbSize = @sizeOf(win32.WNDCLASSEXW);
	wc.style = win32.CS_HREDRAW | win32.CS_VREDRAW;
	wc.lpfnWndProc = wndproc.wndProc;
	wc.hInstance = instance;
	wc.hIcon = win32.LoadIconW(null, @ptrFromInt(win32.IDI_APPLICATION));
	wc.hCursor = win32.LoadCursorW(null, @ptrFromInt(win32.IDC_ARROW));
	wc.hbrBackground = @ptrFromInt(win32.COLOR_WINDOW + 1);
	wc.lpszClassName = &wndproc.CLASS_NAME;
	wc.hIconSm = win32.LoadIconW(null, @ptrFromInt(win32.IDI_APPLICATION));
	if (win32.RegisterClassExW(&wc) == 0) {
		_ = win32.MessageBoxW(null, L("Failed to register window class."), L("Error"), win32.MB_ICONERROR);
		return 1;
	}
	var rc = win32.RECT{ .left = 0, .top = 0, .right = 760, .bottom = 560 };
	_ = win32.AdjustWindowRect(&rc, win32.WS_OVERLAPPED | win32.WS_CAPTION | win32.WS_SYSMENU | win32.WS_MINIMIZEBOX, 0);
	const hwnd = win32.CreateWindowExW(0, &wndproc.CLASS_NAME, &wndproc.WINDOW_TITLE, win32.WS_OVERLAPPED | win32.WS_CAPTION | win32.WS_SYSMENU | win32.WS_MINIMIZEBOX, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, rc.right - rc.left, rc.bottom - rc.top, null, null, instance, null);
	if (hwnd == null) {
		_ = win32.MessageBoxW(null, L("Failed to create window."), L("Error"), win32.MB_ICONERROR);
		return 1;
	}
	// WM_CREATE (fired synchronously above) loads state.prefs, so it already reflects
	// the user's "start minimized to tray" choice by the time we get here.
	if (!state.prefs.start_minimized_to_tray) {
		_ = win32.ShowWindow(hwnd, show);
		_ = win32.UpdateWindow(hwnd);
	}
	const haccel = win32.LoadAcceleratorsW(instance, @ptrFromInt(resource.IDR_ACCEL));
	var msg: win32.MSG = std.mem.zeroes(win32.MSG);
	while (win32.GetMessageW(&msg, null, 0, 0) != 0) {
		if (win32.TranslateAcceleratorW(hwnd, haccel, &msg) == 0 and win32.IsDialogMessageW(hwnd, &msg) == 0) {
			_ = win32.TranslateMessage(&msg);
			_ = win32.DispatchMessageW(&msg);
		}
	}
	_ = win32.CloseHandle(mutex);
	if (com_init >= 0) win32.CoUninitialize();
	return @intCast(msg.wParam);
}
