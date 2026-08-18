// Hand rolled, non zigwin32 Win32 bindings, grown incrementally as more of
// taskmon is ported from C to Zig. Mirrors the approach used in ../sysinfo.

pub const HANDLE = ?*anyopaque;
pub const HWND = ?*anyopaque;
pub const HINSTANCE = ?*anyopaque;
pub const HDC = ?*anyopaque;
pub const HBRUSH = ?*anyopaque;
pub const HKEY = ?*anyopaque;
pub const WORD = u16;
pub const DWORD = u32;
pub const BOOL = i32;
pub const UINT = u32;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const LSTATUS = i32;
pub const COLORREF = u32;
pub const LPWSTR = ?[*:0]u16;
pub const LPCWSTR = [*:0]const u16;

pub const RECT = extern struct {
	left: i32,
	top: i32,
	right: i32,
	bottom: i32,
};

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

pub const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);
pub const RRF_RT_REG_DWORD: DWORD = 0x00000010;

pub extern "advapi32" fn RegGetValueW(hkey: HKEY, lpSubKey: LPCWSTR, lpValue: LPCWSTR, dwFlags: DWORD, pdwType: ?*DWORD, pvData: ?*anyopaque, pcbData: ?*DWORD) callconv(.c) LSTATUS;

pub extern "dwmapi" fn DwmSetWindowAttribute(hwnd: HWND, dwAttribute: DWORD, pvAttribute: *const anyopaque, cbAttribute: DWORD) callconv(.c) c_long;

pub extern "uxtheme" fn SetWindowTheme(hwnd: HWND, pszSubAppName: ?LPCWSTR, pszSubIdList: ?LPCWSTR) callconv(.c) c_long;

pub extern "user32" fn SendMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.c) LRESULT;
pub extern "user32" fn InvalidateRect(hWnd: HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(.c) BOOL;

pub extern "gdi32" fn CreateSolidBrush(color: COLORREF) callconv(.c) HBRUSH;
pub extern "gdi32" fn SetTextColor(hdc: HDC, color: COLORREF) callconv(.c) COLORREF;
pub extern "gdi32" fn SetBkColor(hdc: HDC, color: COLORREF) callconv(.c) COLORREF;

pub const GUID = extern struct {
	Data1: u32,
	Data2: u16,
	Data3: u16,
	Data4: [8]u8,
};

pub const NOTIFYICONDATAW = extern struct {
	cbSize: DWORD,
	hWnd: HWND,
	uID: UINT,
	uFlags: UINT,
	uCallbackMessage: UINT,
	hIcon: HANDLE,
	szTip: [128]u16,
	dwState: DWORD,
	dwStateMask: DWORD,
	szInfo: [256]u16,
	anon: extern union {
		uTimeout: UINT,
		uVersion: UINT,
	},
	szInfoTitle: [64]u16,
	dwInfoFlags: DWORD,
	guidItem: GUID,
	hBalloonIcon: HANDLE,
};

pub const NIM_ADD: DWORD = 0x00000000;
pub const NIM_MODIFY: DWORD = 0x00000001;
pub const NIM_DELETE: DWORD = 0x00000002;
pub const NIF_MESSAGE: UINT = 0x00000001;
pub const NIF_ICON: UINT = 0x00000002;
pub const NIF_TIP: UINT = 0x00000004;
pub const IMAGE_ICON: UINT = 1;
pub const LR_DEFAULTSIZE: UINT = 0x0040;
pub const LR_SHARED: UINT = 0x8000;
pub const IDI_APPLICATION: usize = 32512;
pub const SW_SHOW: i32 = 5;

pub const MEMORYSTATUSEX = extern struct {
	dwLength: DWORD,
	dwMemoryLoad: DWORD,
	ullTotalPhys: u64,
	ullAvailPhys: u64,
	ullTotalPageFile: u64,
	ullAvailPageFile: u64,
	ullTotalVirtual: u64,
	ullAvailVirtual: u64,
	ullAvailExtendedVirtual: u64,
};

pub extern "kernel32" fn lstrcpyW(lpString1: [*:0]u16, lpString2: [*:0]const u16) callconv(.c) ?[*:0]u16;
pub extern "kernel32" fn GlobalMemoryStatusEx(lpBuffer: *MEMORYSTATUSEX) callconv(.c) BOOL;
pub extern "user32" fn LoadImageW(hInst: HINSTANCE, name: LPCWSTR, imgType: UINT, cx: i32, cy: i32, fuLoad: UINT) callconv(.c) HANDLE;
pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.c) BOOL;
pub extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.c) BOOL;
pub extern "shell32" fn Shell_NotifyIconW(dwMessage: DWORD, lpData: *NOTIFYICONDATAW) callconv(.c) BOOL;
pub extern "shlwapi" fn wnsprintfW(pszDest: [*:0]u16, cchDest: i32, pszFmt: LPCWSTR, ...) callconv(.c) i32;
