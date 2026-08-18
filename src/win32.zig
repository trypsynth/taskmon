// Hand rolled, non zigwin32 Win32 bindings, grown incrementally as more of
// taskmon is ported from C to Zig. Mirrors the approach used in ../sysinfo.

pub const HANDLE = ?*anyopaque;
pub const HWND = ?*anyopaque;
pub const HINSTANCE = ?*anyopaque;
pub const WORD = u16;
pub const DWORD = u32;
pub const BOOL = i32;
pub const LPWSTR = ?[*:0]u16;
pub const LPCWSTR = [*:0]const u16;

pub const STARTUPINFOW = extern struct {
	cb: DWORD,
	lpReserved: LPWSTR,
	lpDesktop: LPWSTR,
	lpTitle: LPWSTR,
	dwX: DWORD,
	dwY: DWORD,
	dwXSize: DWORD,
	dwYSize: DWORD,
	dwXCountChars: DWORD,
	dwYCountChars: DWORD,
	dwFillAttribute: DWORD,
	dwFlags: DWORD,
	wShowWindow: WORD,
	cbReserved2: WORD,
	lpReserved2: ?[*]u8,
	hStdInput: HANDLE,
	hStdOutput: HANDLE,
	hStdError: HANDLE,
};

pub const STARTF_USESHOWWINDOW: DWORD = 0x00000001;
pub const SW_SHOWDEFAULT: i32 = 10;

pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) HINSTANCE;
pub extern "kernel32" fn GetStartupInfoW(lpStartupInfo: *STARTUPINFOW) callconv(.c) void;
pub extern "kernel32" fn ExitProcess(uExitCode: c_uint) callconv(.c) noreturn;
