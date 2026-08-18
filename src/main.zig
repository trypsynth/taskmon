const win32 = @import("win32.zig");
comptime {
	_ = @import("theme.zig");
	_ = @import("tray.zig");
	_ = @import("settings.zig");
	_ = @import("run.zig");
	_ = @import("sortbar.zig");
	_ = @import("treeview.zig");
}

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
	var i: usize = 0;
	while (i < count) : (i += 1) d[i] = byte;
	return dest;
}

export fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, count: usize) callconv(.c) ?*anyopaque {
	const d: [*]volatile u8 = @ptrCast(dest.?);
	const s: [*]const volatile u8 = @ptrCast(src.?);
	var i: usize = 0;
	while (i < count) : (i += 1) d[i] = s[i];
	return dest;
}

export fn memmove(dest: ?*anyopaque, src: ?*const anyopaque, count: usize) callconv(.c) ?*anyopaque {
	const d: [*]volatile u8 = @ptrCast(dest.?);
	const s: [*]const volatile u8 = @ptrCast(src.?);
	if (@intFromPtr(d) < @intFromPtr(s)) {
		var i: usize = 0;
		while (i < count) : (i += 1) d[i] = s[i];
	} else {
		var i: usize = count;
		while (i > 0) {
			i -= 1;
			d[i] = s[i];
		}
	}
	return dest;
}

extern fn WinMain(instance: win32.HINSTANCE, prev: win32.HINSTANCE, cmd_line: ?[*:0]u8, show: c_int) callconv(.c) c_int;

// Zig supplies its own minimal, CRT-less bootstrap before calling main() when
// targeting windows with link_libc = false, so no hand written _start/entry
// symbol is needed here (unlike the old entry.c, which had to define one).
pub fn main() void {
	const instance = win32.GetModuleHandleW(null);
	var show: c_int = win32.SW_SHOWDEFAULT;
	var si: win32.STARTUPINFOW = undefined;
	win32.GetStartupInfoW(&si);
	if (si.dwFlags & win32.STARTF_USESHOWWINDOW != 0) show = si.wShowWindow;
	const exit_code = WinMain(instance, null, null, show);
	win32.ExitProcess(@bitCast(exit_code));
}
