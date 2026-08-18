// Hand rolled, non zigwin32 Win32 bindings, grown incrementally as more of
// taskmon is ported from C to Zig. Mirrors the approach used in ../sysinfo.
const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

pub const HANDLE = ?*anyopaque;
pub const HWND = ?*anyopaque;
pub const HINSTANCE = ?*anyopaque;
pub const HMODULE = ?*anyopaque;
pub const HMENU = ?*anyopaque;
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
pub const INT_PTR = isize;
pub const LONG_PTR = isize;
pub const UINT_PTR = usize;
pub const DWORD_PTR = usize;
pub const LSTATUS = i32;
pub const COLORREF = u32;
pub const LPWSTR = ?[*:0]align(1) u16;
// align(1): lets MAKEINTRESOURCE-style small-integer "pointers" (e.g. a
// dialog resource ID cast to LPCWSTR) round-trip through @ptrFromInt even
// when the id is odd; Windows never actually dereferences those, so the
// weaker alignment costs nothing for real string data either.
pub const LPCWSTR = [*:0]align(1) const u16;
pub const MAX_PATH: usize = 260;

pub const DLGPROC = *const fn (hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM) callconv(.c) INT_PTR;
pub const SUBCLASSPROC = *const fn (hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM, id: UINT_PTR, data: DWORD_PTR) callconv(.c) LRESULT;

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
pub const SW_HIDE: i32 = 0;

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

pub extern "kernel32" fn lstrcpyW(lpString1: [*:0]u16, lpString2: LPCWSTR) callconv(.c) ?[*:0]u16;
pub extern "kernel32" fn GlobalMemoryStatusEx(lpBuffer: *MEMORYSTATUSEX) callconv(.c) BOOL;
pub extern "user32" fn LoadImageW(hInst: HINSTANCE, name: LPCWSTR, imgType: UINT, cx: i32, cy: i32, fuLoad: UINT) callconv(.c) HANDLE;
pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.c) BOOL;
pub extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.c) BOOL;
pub extern "shell32" fn Shell_NotifyIconW(dwMessage: DWORD, lpData: *NOTIFYICONDATAW) callconv(.c) BOOL;
pub extern "shlwapi" fn wnsprintfW(pszDest: [*:0]u16, cchDest: i32, pszFmt: LPCWSTR, ...) callconv(.c) i32;

pub const WM_CHAR: UINT = 0x0102;
pub const WM_INITDIALOG: UINT = 0x0110;
pub const WM_COMMAND: UINT = 0x0111;
pub const WM_SETFONT: UINT = 0x0030;
pub const WM_GETFONT: UINT = 0x0031;
pub const WM_CTLCOLOREDIT: UINT = 0x0133;
pub const WM_CTLCOLORLISTBOX: UINT = 0x0134;
pub const WM_CTLCOLORBTN: UINT = 0x0135;
pub const WM_CTLCOLORDLG: UINT = 0x0136;
pub const WM_CTLCOLORSTATIC: UINT = 0x0138;

pub const WS_CHILD: DWORD = 0x40000000;
pub const WS_VISIBLE: DWORD = 0x10000000;
pub const WS_TABSTOP: DWORD = 0x00010000;
pub const BS_AUTOCHECKBOX: DWORD = 0x00000003;
pub const SWP_NOSIZE: UINT = 0x0001;
pub const SWP_NOMOVE: UINT = 0x0002;
pub const SWP_NOZORDER: UINT = 0x0004;
pub const SWP_NOACTIVATE: UINT = 0x0010;

pub const BM_GETCHECK: UINT = 0x00F0;
pub const BM_SETCHECK: UINT = 0x00F1;
pub const BST_UNCHECKED = 0x0000;
pub const BST_CHECKED = 0x0001;

pub const CB_ADDSTRING: UINT = 0x0143;
pub const CB_GETCURSEL: UINT = 0x0147;
pub const CB_SETCURSEL: UINT = 0x014E;

pub const CSIDL_LOCAL_APPDATA: c_int = 0x001c;
pub const CSIDL_PROGRAM_FILES: c_int = 0x0026;

pub const DWLP_USER: c_int = 16;
pub const IDOK = 1;
pub const IDCANCEL = 2;

pub const LVIF_TEXT: UINT = 0x1;
pub const LVIF_PARAM: UINT = 0x4;
pub const LVCF_WIDTH: UINT = 0x2;
pub const LVIS_FOCUSED: UINT = 0x1;
pub const LVIS_SELECTED: UINT = 0x2;
pub const LVIS_STATEIMAGEMASK: UINT = 0xF000;
pub const LVS_EX_CHECKBOXES: DWORD = 0x4;

const LVM_FIRST: UINT = 0x1000;
pub const LVM_GETITEMCOUNT: UINT = LVM_FIRST + 4;
pub const LVM_INSERTITEMW: UINT = LVM_FIRST + 77;
pub const LVM_GETITEMW: UINT = LVM_FIRST + 75;
pub const LVM_SETITEMSTATE: UINT = LVM_FIRST + 43;
pub const LVM_GETITEMSTATE: UINT = LVM_FIRST + 44;
pub const LVM_SETEXTENDEDLISTVIEWSTYLE: UINT = LVM_FIRST + 54;
pub const LVM_INSERTCOLUMNW: UINT = LVM_FIRST + 97;

fn indexToStateImageMask(i: u32) UINT {
	return i << 12;
}
pub const STATEIMAGE_UNCHECKED: UINT = indexToStateImageMask(1);
pub const STATEIMAGE_CHECKED: UINT = indexToStateImageMask(2);

pub const LVCOLUMNW = extern struct {
	mask: UINT,
	fmt: i32,
	cx: i32,
	pszText: LPWSTR,
	cchTextMax: i32,
	iSubItem: i32,
	iImage: i32,
	iOrder: i32,
	cxMin: i32,
	cxDefault: i32,
	cxIdeal: i32,
};

pub const LVITEMW = extern struct {
	mask: UINT,
	iItem: i32,
	iSubItem: i32,
	state: UINT,
	stateMask: UINT,
	pszText: LPWSTR,
	cchTextMax: i32,
	iImage: i32,
	lParam: LPARAM,
	iIndent: i32,
	iGroupId: i32,
	cColumns: UINT,
	puColumns: ?*UINT,
	piColFmt: ?*i32,
	iGroup: i32,
};

pub extern "comctl32" fn DefSubclassProc(hWnd: HWND, uMsg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.c) LRESULT;
pub extern "comctl32" fn SetWindowSubclass(hWnd: HWND, pfnSubclass: SUBCLASSPROC, uIdSubclass: UINT_PTR, dwRefData: DWORD_PTR) callconv(.c) BOOL;

pub extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: c_int, dwNewLong: LONG_PTR) callconv(.c) LONG_PTR;
pub extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: c_int) callconv(.c) LONG_PTR;
pub extern "user32" fn GetDlgItem(hDlg: HWND, nIDDlgItem: c_int) callconv(.c) HWND;
pub extern "user32" fn SetMenu(hWnd: HWND, hMenu: HMENU) callconv(.c) BOOL;
pub extern "user32" fn CreateWindowExW(dwExStyle: DWORD, lpClassName: LPCWSTR, lpWindowName: ?LPCWSTR, dwStyle: DWORD, X: i32, Y: i32, nWidth: i32, nHeight: i32, hWndParent: HWND, hMenu: HMENU, hInstance: HINSTANCE, lpParam: ?*anyopaque) callconv(.c) HWND;
pub extern "user32" fn DialogBoxParamW(hInstance: HINSTANCE, lpTemplateName: LPCWSTR, hWndParent: HWND, lpDialogFunc: DLGPROC, dwInitParam: LPARAM) callconv(.c) INT_PTR;
pub extern "user32" fn EndDialog(hDlg: HWND, nResult: INT_PTR) callconv(.c) BOOL;
pub extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: HWND, X: i32, Y: i32, cx: i32, cy: i32, uFlags: UINT) callconv(.c) BOOL;

pub extern "kernel32" fn GetModuleFileNameW(hModule: HMODULE, lpFilename: [*:0]u16, nSize: DWORD) callconv(.c) DWORD;
pub extern "kernel32" fn CreateDirectoryW(lpPathName: LPCWSTR, lpSecurityAttributes: ?*anyopaque) callconv(.c) BOOL;
pub extern "kernel32" fn lstrcpynW(lpString1: [*:0]u16, lpString2: LPCWSTR, iMaxLength: i32) callconv(.c) ?[*:0]u16;
pub extern "kernel32" fn GetPrivateProfileStringW(lpAppName: LPCWSTR, lpKeyName: LPCWSTR, lpDefault: LPCWSTR, lpReturnedString: [*:0]u16, nSize: DWORD, lpFileName: LPCWSTR) callconv(.c) DWORD;
pub extern "kernel32" fn WritePrivateProfileStringW(lpAppName: LPCWSTR, lpKeyName: LPCWSTR, lpString: LPCWSTR, lpFileName: LPCWSTR) callconv(.c) BOOL;

pub extern "shell32" fn SHGetFolderPathW(hwnd: HWND, csidl: c_int, hToken: HANDLE, dwFlags: DWORD, pszPath: [*:0]u16) callconv(.c) c_long;
pub extern "shlwapi" fn PathRemoveFileSpecW(pszPath: [*:0]u16) callconv(.c) BOOL;
pub extern "shlwapi" fn PathIsPrefixW(pszPrefix: LPCWSTR, pszPath: LPCWSTR) callconv(.c) BOOL;
pub extern "shlwapi" fn PathAppendW(pszPath: [*:0]u16, pszMore: LPCWSTR) callconv(.c) BOOL;
pub extern "shlwapi" fn StrCmpIW(pszStr1: LPCWSTR, pszStr2: LPCWSTR) callconv(.c) c_int;
pub extern "shlwapi" fn StrToIntW(pszString: LPCWSTR) callconv(.c) c_int;
pub extern "shlwapi" fn PathRemoveBlanksW(pszPath: [*:0]u16) callconv(.c) void;

pub const SW_SHOWNORMAL: i32 = 1;
pub const EN_CHANGE: UINT = 0x0300;
pub const EM_SETSEL: UINT = 0x00B1;
pub const EM_SETLIMITTEXT: UINT = 0x00C5;
pub const SEE_MASK_DOENVSUBST: c_ulong = 0x200;
pub const OFN_FILEMUSTEXIST: DWORD = 0x1000;
pub const OFN_HIDEREADONLY: DWORD = 0x4;

pub const OPENFILENAMEW = extern struct {
	lStructSize: DWORD,
	hwndOwner: HWND,
	hInstance: HINSTANCE,
	lpstrFilter: LPCWSTR,
	lpstrCustomFilter: LPWSTR,
	nMaxCustFilter: DWORD,
	nFilterIndex: DWORD,
	lpstrFile: [*:0]u16,
	nMaxFile: DWORD,
	lpstrFileTitle: LPWSTR,
	nMaxFileTitle: DWORD,
	lpstrInitialDir: ?LPCWSTR,
	lpstrTitle: ?LPCWSTR,
	Flags: DWORD,
	nFileOffset: WORD,
	nFileExtension: WORD,
	lpstrDefExt: ?LPCWSTR,
	lCustData: LPARAM,
	lpfnHook: ?*anyopaque,
	lpTemplateName: ?LPCWSTR,
	pvReserved: ?*anyopaque,
	dwReserved: DWORD,
	FlagsEx: DWORD,
};

pub const SHELLEXECUTEINFOW = extern struct {
	cbSize: DWORD,
	fMask: c_ulong,
	hwnd: HWND,
	lpVerb: ?LPCWSTR,
	lpFile: ?LPCWSTR,
	lpParameters: ?LPCWSTR,
	lpDirectory: ?LPCWSTR,
	nShow: i32,
	hInstApp: HINSTANCE,
	lpIDList: ?*anyopaque,
	lpClass: ?LPCWSTR,
	hkeyClass: HKEY,
	dwHotKey: DWORD,
	anon: extern union {
		hIcon: HANDLE,
		hMonitor: HANDLE,
	},
	hProcess: HANDLE,
};

pub extern "comdlg32" fn GetOpenFileNameW(lpofn: *OPENFILENAMEW) callconv(.c) BOOL;
pub extern "shell32" fn ShellExecuteExW(pExecInfo: *SHELLEXECUTEINFOW) callconv(.c) BOOL;

pub extern "user32" fn SetDlgItemTextW(hDlg: HWND, nIDDlgItem: c_int, lpString: LPCWSTR) callconv(.c) BOOL;
pub extern "user32" fn GetDlgItemTextW(hDlg: HWND, nIDDlgItem: c_int, lpString: [*:0]u16, cchMax: c_int) callconv(.c) UINT;
pub extern "user32" fn SendDlgItemMessageW(hDlg: HWND, nIDDlgItem: c_int, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.c) LRESULT;
pub extern "user32" fn EnableWindow(hWnd: HWND, bEnable: BOOL) callconv(.c) BOOL;
pub extern "user32" fn GetWindowTextLengthW(hWnd: HWND) callconv(.c) c_int;
pub extern "user32" fn SetWindowTextW(hWnd: HWND, lpString: LPCWSTR) callconv(.c) BOOL;
pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.c) BOOL;
pub extern "user32" fn PostMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.c) BOOL;
pub extern "user32" fn GetDlgCtrlID(hWnd: HWND) callconv(.c) c_int;
pub extern "user32" fn SetFocus(hWnd: HWND) callconv(.c) HWND;
pub extern "user32" fn GetParent(hWnd: HWND) callconv(.c) HWND;

pub extern "kernel32" fn GetProcessHeap() callconv(.c) HANDLE;
pub extern "kernel32" fn HeapAlloc(hHeap: HANDLE, dwFlags: DWORD, dwBytes: usize) callconv(.c) ?*anyopaque;
pub extern "kernel32" fn HeapFree(hHeap: HANDLE, dwFlags: DWORD, lpMem: ?*anyopaque) callconv(.c) BOOL;
pub const HEAP_ZERO_MEMORY: DWORD = 0x00000008;

pub const WM_SETREDRAW: UINT = 0x000B;

pub const HTREEITEM = ?*anyopaque;

pub const TVITEMW = extern struct {
	mask: UINT,
	hItem: HTREEITEM,
	state: UINT,
	stateMask: UINT,
	pszText: LPWSTR,
	cchTextMax: i32,
	iImage: i32,
	iSelectedImage: i32,
	cChildren: i32,
	lParam: LPARAM,
};

pub const TVITEMEXW = extern struct {
	mask: UINT,
	hItem: HTREEITEM,
	state: UINT,
	stateMask: UINT,
	pszText: LPWSTR,
	cchTextMax: i32,
	iImage: i32,
	iSelectedImage: i32,
	cChildren: i32,
	lParam: LPARAM,
	iIntegral: i32,
	uStateEx: UINT,
	hwnd: HWND,
	iExpandedImage: i32,
	iReserved: i32,
};

pub const TVINSERTSTRUCTW = extern struct {
	hParent: HTREEITEM,
	hInsertAfter: HTREEITEM,
	anon: extern union {
		itemex: TVITEMEXW,
		item: TVITEMW,
	},
};

pub const TVHITTESTINFO = extern struct {
	pt: POINT,
	flags: UINT,
	hItem: HTREEITEM,
};

pub const TVI_ROOT: HTREEITEM = @ptrFromInt(@as(usize, @bitCast(@as(isize, -0x10000))));
pub const TVI_SORT: HTREEITEM = @ptrFromInt(@as(usize, @bitCast(@as(isize, -0xfffd))));

pub const TVIF_TEXT: UINT = 0x1;
pub const TVIF_PARAM: UINT = 0x4;
pub const TVIF_STATE: UINT = 0x8;
pub const TVIS_EXPANDED: UINT = 0x20;
pub const TVE_EXPAND: WPARAM = 0x2;
pub const TVGN_ROOT: WPARAM = 0x0;
pub const TVGN_NEXT: WPARAM = 0x1;
pub const TVGN_CHILD: WPARAM = 0x4;
pub const TVGN_CARET: WPARAM = 0x9;

const TV_FIRST: UINT = 0x1100;
pub const TVM_INSERTITEMW: UINT = TV_FIRST + 50;
pub const TVM_DELETEITEM: UINT = TV_FIRST + 1;
pub const TVM_EXPAND: UINT = TV_FIRST + 2;
pub const TVM_GETITEMRECT: UINT = TV_FIRST + 4;
pub const TVM_GETNEXTITEM: UINT = TV_FIRST + 10;
pub const TVM_SELECTITEM: UINT = TV_FIRST + 11;
pub const TVM_GETITEMW: UINT = TV_FIRST + 62;
pub const TVM_HITTEST: UINT = TV_FIRST + 17;
pub const TVM_ENSUREVISIBLE: UINT = TV_FIRST + 20;

pub const FILETIME = extern struct {
	dwLowDateTime: DWORD,
	dwHighDateTime: DWORD,
};

pub const SYSTEMTIME = extern struct {
	wYear: WORD,
	wMonth: WORD,
	wDayOfWeek: WORD,
	wDay: WORD,
	wHour: WORD,
	wMinute: WORD,
	wSecond: WORD,
	wMilliseconds: WORD,
};

pub const WM_USER: UINT = 0x0400;
pub const SB_SETTEXTW: UINT = WM_USER + 11;

pub const LVNI_SELECTED: LPARAM = 0x2;
pub const LVIR_BOUNDS: i32 = 0;
pub const LVM_GETNEXTITEM: UINT = LVM_FIRST + 12;
pub const LVM_GETTOPINDEX: UINT = LVM_FIRST + 39;
pub const LVM_DELETEALLITEMS: UINT = LVM_FIRST + 9;
pub const LVM_SETITEMTEXTW: UINT = LVM_FIRST + 116;
pub const LVM_SCROLL: UINT = LVM_FIRST + 20;
pub const LVM_GETITEMRECT: UINT = LVM_FIRST + 14;
pub const LVM_ENSUREVISIBLE: UINT = LVM_FIRST + 19;
pub const LVM_GETITEMTEXTW: UINT = LVM_FIRST + 115;

pub extern "shlwapi" fn StrFormatByteSizeW(qwSize: i64, pszBuf: [*:0]u16, cchBuf: UINT) callconv(.c) ?[*:0]u16;
pub extern "kernel32" fn FileTimeToLocalFileTime(lpFileTime: *const FILETIME, lpLocalFileTime: *FILETIME) callconv(.c) BOOL;
pub extern "kernel32" fn FileTimeToSystemTime(lpFileTime: *const FILETIME, lpSystemTime: *SYSTEMTIME) callconv(.c) BOOL;
pub extern "kernel32" fn GetLocalTime(lpSystemTime: *SYSTEMTIME) callconv(.c) void;
pub extern "kernel32" fn lstrcatW(lpString1: [*:0]u16, lpString2: LPCWSTR) callconv(.c) ?[*:0]u16;
pub extern "kernel32" fn lstrlenW(lpString: LPCWSTR) callconv(.c) c_int;
pub extern "kernel32" fn HeapReAlloc(hHeap: HANDLE, dwFlags: DWORD, lpMem: ?*anyopaque, dwBytes: usize) callconv(.c) ?*anyopaque;
pub extern "kernel32" fn GetCurrentProcess() callconv(.c) HANDLE;
pub extern "kernel32" fn GetProcAddress(hModule: HMODULE, lpProcName: [*:0]const u8) callconv(.c) ?*anyopaque;
pub extern "kernel32" fn LoadLibraryW(lpLibFileName: LPCWSTR) callconv(.c) HMODULE;
pub extern "kernel32" fn OpenProcess(dwDesiredAccess: DWORD, bInheritHandle: BOOL, dwProcessId: DWORD) callconv(.c) HANDLE;
pub extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.c) BOOL;
pub extern "kernel32" fn TerminateProcess(hProcess: HANDLE, uExitCode: UINT) callconv(.c) BOOL;
pub extern "kernel32" fn SetPriorityClass(hProcess: HANDLE, dwPriorityClass: DWORD) callconv(.c) BOOL;
pub extern "kernel32" fn QueryFullProcessImageNameW(hProcess: HANDLE, dwFlags: DWORD, lpExeName: [*:0]u16, lpdwSize: *DWORD) callconv(.c) BOOL;
pub extern "kernel32" fn GetSystemTimes(lpIdleTime: ?*FILETIME, lpKernelTime: ?*FILETIME, lpUserTime: ?*FILETIME) callconv(.c) BOOL;
pub extern "kernel32" fn GetSystemTimeAsFileTime(lpSystemTimeAsFileTime: *FILETIME) callconv(.c) void;
pub extern "kernel32" fn GetTickCount64() callconv(.c) u64;
pub extern "kernel32" fn GetNativeSystemInfo(lpSystemInfo: *SYSTEM_INFO) callconv(.c) void;
pub extern "kernel32" fn IsWow64Process(hProcess: HANDLE, Wow64Process: *BOOL) callconv(.c) BOOL;
pub extern "kernel32" fn GetPackageFullName(hProcess: HANDLE, packageFullNameLength: *u32, packageFullName: ?[*:0]u16) callconv(.c) c_long;

pub extern "advapi32" fn OpenProcessToken(ProcessHandle: HANDLE, DesiredAccess: DWORD, TokenHandle: *HANDLE) callconv(.c) BOOL;
pub extern "advapi32" fn GetTokenInformation(TokenHandle: HANDLE, TokenInformationClass: c_int, TokenInformation: ?*anyopaque, TokenInformationLength: DWORD, ReturnLength: *DWORD) callconv(.c) BOOL;
pub extern "advapi32" fn GetSidSubAuthority(pSid: ?*anyopaque, nSubAuthority: DWORD) callconv(.c) *DWORD;
pub extern "advapi32" fn GetSidSubAuthorityCount(pSid: ?*anyopaque) callconv(.c) *u8;
pub extern "advapi32" fn LookupAccountSidW(lpSystemName: ?LPCWSTR, Sid: ?*anyopaque, Name: [*:0]u16, cchName: *DWORD, ReferencedDomainName: [*:0]u16, cchReferencedDomainName: *DWORD, peUse: *c_int) callconv(.c) BOOL;
pub extern "advapi32" fn LocalFree(hMem: ?*anyopaque) callconv(.c) ?*anyopaque;
pub extern "advapi32" fn OpenSCManagerW(lpMachineName: ?LPCWSTR, lpDatabaseName: ?LPCWSTR, dwDesiredAccess: DWORD) callconv(.c) HANDLE;
pub extern "advapi32" fn CloseServiceHandle(hSCObject: HANDLE) callconv(.c) BOOL;
pub extern "advapi32" fn EnumServicesStatusExW(hSCManager: HANDLE, InfoLevel: c_int, dwServiceType: DWORD, dwServiceState: DWORD, lpServices: ?[*]u8, cbBufSize: DWORD, pcbBytesNeeded: *DWORD, lpServicesReturned: *DWORD, lpResumeHandle: *DWORD, pszGroupName: ?LPCWSTR) callconv(.c) BOOL;

pub extern "shlwapi" fn ConvertSidToStringSidW(Sid: ?*anyopaque, StringSid: *LPWSTR) callconv(.c) BOOL;

pub extern "user32" fn GetGuiResources(hProcess: HANDLE, uiFlags: DWORD) callconv(.c) DWORD;
pub extern "user32" fn IsWindowVisible(hWnd: HWND) callconv(.c) BOOL;
pub extern "user32" fn GetWindowThreadProcessId(hWnd: HWND, lpdwProcessId: *DWORD) callconv(.c) DWORD;

pub const HMONITOR = ?*anyopaque;
pub const HRGN = ?*anyopaque;

pub const WM_NULL: UINT = 0x0000;
pub const WM_CREATE: UINT = 0x0001;
pub const WM_DESTROY: UINT = 0x0002;
pub const WM_SIZE: UINT = 0x0005;
pub const WM_ACTIVATE: UINT = 0x0006;
pub const WA_INACTIVE: WORD = 0;
pub const WM_ERASEBKGND: UINT = 0x0014;
pub const WM_WININICHANGE: UINT = 0x001A;
pub const WM_SETTINGCHANGE: UINT = WM_WININICHANGE;
pub const WM_NOTIFY: UINT = 0x004E;
pub const WM_CONTEXTMENU: UINT = 0x007B;
pub const WM_TIMER: UINT = 0x0113;
pub const WM_LBUTTONUP: UINT = 0x0202;
pub const WM_RBUTTONUP: UINT = 0x0205;
pub const WM_HOTKEY: UINT = 0x0312;
pub const MOD_CONTROL: UINT = 0x0002;
pub const MOD_SHIFT: UINT = 0x0004;
pub const MOD_NOREPEAT: UINT = 0x4000;
pub const VK_OEM_3: usize = 0xC0;
pub const SS_LEFT: DWORD = 0x00000000;

pub const HWND_DESKTOP: HWND = @ptrFromInt(0);
pub const HWND_TOPMOST: HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
pub const HWND_NOTOPMOST: HWND = @ptrFromInt(@as(usize, @bitCast(@as(isize, -2))));
pub const MONITOR_DEFAULTTONULL: DWORD = 0x00000000;
pub const TPM_RIGHTBUTTON: UINT = 0x0002;
pub const RDW_INVALIDATE: UINT = 0x0001;
pub const RDW_ERASE: UINT = 0x0004;
pub const RDW_ALLCHILDREN: UINT = 0x0080;
pub const MB_YESNO: UINT = 0x00000004;
pub const MB_ICONQUESTION: UINT = 0x00000020;
pub const MB_DEFBUTTON2: UINT = 0x00000100;
pub const IDYES: c_int = 6;
pub const MF_STRING: UINT = 0x00000000;
pub const MF_UNCHECKED: UINT = 0x00000000;
pub const MF_GRAYED: UINT = 0x00000001;
pub const MF_CHECKED: UINT = 0x00000008;
pub const MF_POPUP: UINT = 0x00000010;
pub const MF_SEPARATOR: UINT = 0x00000800;

pub const TVHT_ONITEMICON: UINT = 0x2;
pub const TVHT_ONITEMLABEL: UINT = 0x4;
pub const TVHT_ONITEMSTATEICON: UINT = 0x40;
pub const TVHT_ONITEM: UINT = TVHT_ONITEMICON | TVHT_ONITEMLABEL | TVHT_ONITEMSTATEICON;
pub const TVM_SETEXTENDEDSTYLE: UINT = TV_FIRST + 44;

pub const ICC_LISTVIEW_CLASSES: DWORD = 0x1;
pub const ICC_TREEVIEW_CLASSES: DWORD = 0x2;
pub const ICC_BAR_CLASSES: DWORD = 0x4;
pub const WC_LISTVIEWW = L("SysListView32");
pub const WC_TREEVIEWW = L("SysTreeView32");
pub const STATUSCLASSNAMEW = L("msctls_statusbar32");
pub const LVS_REPORT: DWORD = 0x1;
pub const LVS_SHOWSELALWAYS: DWORD = 0x8;
pub const LVS_EX_GRIDLINES: DWORD = 0x1;
pub const LVS_EX_HEADERDRAGDROP: DWORD = 0x10;
pub const LVS_EX_FULLROWSELECT: DWORD = 0x20;
pub const TVS_HASBUTTONS: DWORD = 0x1;
pub const TVS_HASLINES: DWORD = 0x2;
pub const TVS_LINESATROOT: DWORD = 0x4;
pub const TVS_SHOWSELALWAYS: DWORD = 0x20;
pub const TVS_EX_DOUBLEBUFFER: DWORD = 0x4;
const LVN_FIRST: i32 = -100;
pub const LVN_COLUMNCLICK: i32 = LVN_FIRST - 8;

pub const IDLE_PRIORITY_CLASS: DWORD = 0x40;
pub const NORMAL_PRIORITY_CLASS: DWORD = 0x20;
pub const HIGH_PRIORITY_CLASS: DWORD = 0x80;
pub const REALTIME_PRIORITY_CLASS: DWORD = 0x100;
pub const BELOW_NORMAL_PRIORITY_CLASS: DWORD = 0x4000;
pub const ABOVE_NORMAL_PRIORITY_CLASS: DWORD = 0x8000;

pub const INITCOMMONCONTROLSEX = extern struct {
	dwSize: DWORD,
	dwICC: DWORD,
};

pub const NMHDR = extern struct {
	hwndFrom: HWND,
	idFrom: UINT_PTR,
	code: UINT,
};

pub const NMLISTVIEW = extern struct {
	hdr: NMHDR,
	iItem: i32,
	iSubItem: i32,
	uNewState: UINT,
	uOldState: UINT,
	uChanged: UINT,
	ptAction: POINT,
	lParam: LPARAM,
};

pub const WINDOWPLACEMENT = extern struct {
	length: UINT,
	flags: UINT,
	showCmd: UINT,
	ptMinPosition: POINT,
	ptMaxPosition: POINT,
	rcNormalPosition: RECT,
};

pub const PIDLIST_ABSOLUTE = ?*anyopaque;
pub const PIDLIST_RELATIVE = ?*anyopaque;
pub const PUITEMID_CHILD = ?*anyopaque;
pub const PCUIDLIST_RELATIVE = ?*const anyopaque;

pub extern "user32" fn RegisterHotKey(hWnd: HWND, id: c_int, fsModifiers: UINT, vk: UINT) callconv(.c) BOOL;
pub extern "user32" fn UnregisterHotKey(hWnd: HWND, id: c_int) callconv(.c) BOOL;
pub extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.c) LRESULT;
pub extern "user32" fn PostQuitMessage(nExitCode: c_int) callconv(.c) void;
pub extern "user32" fn GetWindowPlacement(hWnd: HWND, lpwndpl: *WINDOWPLACEMENT) callconv(.c) BOOL;
pub extern "user32" fn GetFocus() callconv(.c) HWND;
pub extern "user32" fn SetTimer(hWnd: HWND, nIDEvent: UINT_PTR, uElapse: UINT, lpTimerFunc: ?*anyopaque) callconv(.c) UINT_PTR;
pub extern "user32" fn KillTimer(hWnd: HWND, uIDEvent: UINT_PTR) callconv(.c) BOOL;
pub extern "user32" fn GetMenu(hWnd: HWND) callconv(.c) HMENU;
pub extern "user32" fn CreateMenu() callconv(.c) HMENU;
pub extern "user32" fn CreatePopupMenu() callconv(.c) HMENU;
pub extern "user32" fn DestroyMenu(hMenu: HMENU) callconv(.c) BOOL;
pub extern "user32" fn CheckMenuItem(hMenu: HMENU, uIDCheckItem: UINT, uCheck: UINT) callconv(.c) DWORD;
pub extern "user32" fn GetSubMenu(hMenu: HMENU, nPos: c_int) callconv(.c) HMENU;
pub extern "user32" fn AppendMenuW(hMenu: HMENU, uFlags: UINT, uIDNewItem: UINT_PTR, lpNewItem: ?LPCWSTR) callconv(.c) BOOL;
pub extern "user32" fn TrackPopupMenu(hMenu: HMENU, uFlags: UINT, x: c_int, y: c_int, nReserved: c_int, hWnd: HWND, prcRect: ?*const RECT) callconv(.c) BOOL;
pub extern "user32" fn GetForegroundWindow() callconv(.c) HWND;
pub extern "user32" fn RedrawWindow(hWnd: HWND, lprcUpdate: ?*const RECT, hrgnUpdate: HRGN, flags: UINT) callconv(.c) BOOL;
pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.c) BOOL;
pub extern "user32" fn MessageBoxW(hWnd: HWND, lpText: LPCWSTR, lpCaption: LPCWSTR, uType: UINT) callconv(.c) c_int;
pub extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(.c) BOOL;
pub extern "user32" fn ScreenToClient(hWnd: HWND, lpPoint: *POINT) callconv(.c) BOOL;
pub extern "user32" fn MapWindowPoints(hWndFrom: HWND, hWndTo: HWND, lpPoints: [*]POINT, cPoints: UINT) callconv(.c) c_int;
pub extern "user32" fn FillRect(hDC: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(.c) c_int;
pub extern "user32" fn MonitorFromPoint(pt: POINT, dwFlags: DWORD) callconv(.c) HMONITOR;
pub extern "kernel32" fn lstrcmpW(lpString1: LPCWSTR, lpString2: LPCWSTR) callconv(.c) c_int;
pub extern "kernel32" fn GetPriorityClass(hProcess: HANDLE) callconv(.c) DWORD;
pub extern "comctl32" fn InitCommonControlsEx(icc: *const INITCOMMONCONTROLSEX) callconv(.c) BOOL;
pub extern "shell32" fn ILCreateFromPathW(pszPath: LPCWSTR) callconv(.c) PIDLIST_ABSOLUTE;
pub extern "shell32" fn ILFree(pidl: PIDLIST_RELATIVE) callconv(.c) void;
pub extern "shell32" fn ILFindLastID(pidl: PCUIDLIST_RELATIVE) callconv(.c) PUITEMID_CHILD;
pub extern "shell32" fn SHOpenFolderAndSelectItems(pidlFolder: PIDLIST_ABSOLUTE, cidl: UINT, apidl: [*]const PUITEMID_CHILD, dwFlags: DWORD) callconv(.c) c_long;
pub extern "shell32" fn ShellExecuteW(hwnd: HWND, lpOperation: ?LPCWSTR, lpFile: ?LPCWSTR, lpParameters: ?LPCWSTR, lpDirectory: ?LPCWSTR, nShowCmd: c_int) callconv(.c) HINSTANCE;
pub extern "kernel32" fn CreateMutexW(lpMutexAttributes: ?*anyopaque, bInitialOwner: BOOL, lpName: ?LPCWSTR) callconv(.c) HANDLE;
pub extern "user32" fn EnumWindows(lpEnumFunc: *const fn (HWND, LPARAM) callconv(.c) BOOL, lParam: LPARAM) callconv(.c) BOOL;
pub extern "user32" fn GetWindow(hWnd: HWND, uCmd: UINT) callconv(.c) HWND;
pub extern "user32" fn GetWindowTextW(hWnd: HWND, lpString: [*:0]u16, nMaxCount: c_int) callconv(.c) c_int;

pub extern "version" fn GetFileVersionInfoSizeW(lptstrFilename: LPCWSTR, lpdwHandle: *DWORD) callconv(.c) DWORD;
pub extern "version" fn GetFileVersionInfoW(lptstrFilename: LPCWSTR, dwHandle: DWORD, dwLen: DWORD, lpData: ?*anyopaque) callconv(.c) BOOL;
pub extern "version" fn VerQueryValueW(pBlock: ?*const anyopaque, lpSubBlock: LPCWSTR, lplpBuffer: *?*anyopaque, puLen: *UINT) callconv(.c) BOOL;

pub extern "wtsapi32" fn WTSQuerySessionInformationW(hServer: HANDLE, SessionId: DWORD, WTSInfoClass: c_int, ppBuffer: *LPWSTR, pBytesReturned: *DWORD) callconv(.c) BOOL;
pub extern "wtsapi32" fn WTSFreeMemory(pMemory: ?*anyopaque) callconv(.c) void;
pub const WTS_CURRENT_SERVER_HANDLE: HANDLE = null;
pub const WTSWinStationName: c_int = 6;

pub const GR_GDIOBJECTS: DWORD = 0;
pub const GR_USEROBJECTS: DWORD = 1;
pub const GW_OWNER: UINT = 4;

pub const TOKEN_QUERY: DWORD = 0x0008;
pub const PROCESS_TERMINATE: DWORD = 0x0001;
pub const PROCESS_SET_INFORMATION: DWORD = 0x0200;
pub const PROCESS_SUSPEND_RESUME: DWORD = 0x0800;
pub const PROCESS_QUERY_LIMITED_INFORMATION: DWORD = 0x1000;

pub const TokenUser: c_int = 1;
pub const TokenElevation: c_int = 20;
pub const TokenVirtualizationAllowed: c_int = 23;
pub const TokenVirtualizationEnabled: c_int = 24;
pub const TokenIntegrityLevel: c_int = 25;
pub const TokenIsAppContainer: c_int = 29;

pub const SC_MANAGER_ENUMERATE_SERVICE: DWORD = 0x0004;
pub const SC_ENUM_PROCESS_INFO: c_int = 0;
pub const SERVICE_WIN32: DWORD = 0x00000030;
pub const SERVICE_STATE_ALL: DWORD = 0x00000003;

pub const SID_AND_ATTRIBUTES = extern struct {
	Sid: ?*anyopaque,
	Attributes: DWORD,
};
pub const TOKEN_MANDATORY_LABEL = extern struct {
	Label: SID_AND_ATTRIBUTES,
};
pub const TOKEN_ELEVATION = extern struct {
	TokenIsElevated: DWORD,
};
pub const TOKEN_USER = extern struct {
	User: SID_AND_ATTRIBUTES,
};

pub const PROCESS_POWER_THROTTLING_STATE = extern struct {
	Version: ULONG,
	ControlMask: ULONG,
	StateMask: ULONG,
};
pub const ProcessPowerThrottling: c_int = 4;
pub const PROCESS_POWER_THROTTLING_CURRENT_VERSION: ULONG = 1;
pub const PROCESS_POWER_THROTTLING_EXECUTION_SPEED: ULONG = 0x1;

pub const ULONG = u32;

pub const SYSTEM_INFO = extern struct {
	wProcessorArchitecture: WORD,
	wReserved: WORD,
	dwPageSize: DWORD,
	lpMinimumApplicationAddress: ?*anyopaque,
	lpMaximumApplicationAddress: ?*anyopaque,
	dwActiveProcessorMask: usize,
	dwNumberOfProcessors: DWORD,
	dwProcessorType: DWORD,
	dwAllocationGranularity: DWORD,
	wProcessorLevel: WORD,
	wProcessorRevision: WORD,
};

pub const PROCESSOR_ARCHITECTURE_AMD64: WORD = 9;
pub const PROCESSOR_ARCHITECTURE_ARM64: WORD = 12;
pub const IMAGE_FILE_MACHINE_UNKNOWN: USHORT = 0;
pub const USHORT = u16;

pub const ENUM_SERVICE_STATUS_PROCESSW = extern struct {
	lpServiceName: LPWSTR,
	lpDisplayName: LPWSTR,
	ServiceStatusProcess: SERVICE_STATUS_PROCESS,
};
pub const SERVICE_STATUS_PROCESS = extern struct {
	dwServiceType: DWORD,
	dwCurrentState: DWORD,
	dwControlsAccepted: DWORD,
	dwWin32ExitCode: DWORD,
	dwServiceSpecificExitCode: DWORD,
	dwCheckPoint: DWORD,
	dwWaitHint: DWORD,
	dwProcessId: DWORD,
	dwServiceFlags: DWORD,
};

pub const PDH_HQUERY = HANDLE;
pub const PDH_HCOUNTER = HANDLE;
pub const PDH_STATUS = c_long;
pub const PDH_FMT_DOUBLE: DWORD = 0x00000200;
pub const PDH_FMT_LARGE: DWORD = 0x00000400;
pub const PDH_MORE_DATA: PDH_STATUS = @bitCast(@as(u32, 0x800007D2));

pub const PDH_FMT_COUNTERVALUE = extern struct {
	CStatus: DWORD,
	value: extern union {
		longValue: i32,
		doubleValue: f64,
		largeValue: i64,
	},
};
pub const PDH_FMT_COUNTERVALUE_ITEM_W = extern struct {
	szName: LPWSTR,
	FmtValue: PDH_FMT_COUNTERVALUE,
};

pub extern "pdh" fn PdhOpenQueryW(szDataSource: ?LPCWSTR, dwUserData: usize, phQuery: *PDH_HQUERY) callconv(.c) PDH_STATUS;
pub extern "pdh" fn PdhAddEnglishCounterW(hQuery: PDH_HQUERY, szFullCounterPath: LPCWSTR, dwUserData: usize, phCounter: *PDH_HCOUNTER) callconv(.c) PDH_STATUS;
pub extern "pdh" fn PdhCollectQueryData(hQuery: PDH_HQUERY) callconv(.c) PDH_STATUS;
pub extern "pdh" fn PdhCloseQuery(hQuery: PDH_HQUERY) callconv(.c) PDH_STATUS;
pub extern "pdh" fn PdhGetFormattedCounterArrayW(hCounter: PDH_HCOUNTER, dwFormat: DWORD, lpdwBufferSize: *DWORD, lpdwItemCount: *DWORD, ItemBuffer: ?[*]PDH_FMT_COUNTERVALUE_ITEM_W) callconv(.c) PDH_STATUS;

pub const HBITMAP = ?*anyopaque;

pub const POINT = extern struct {
	x: i32,
	y: i32,
};

pub const MSG = extern struct {
	hwnd: HWND,
	message: UINT,
	wParam: WPARAM,
	lParam: LPARAM,
	time: DWORD,
	pt: POINT,
};

pub const WM_APP: UINT = 0x8000;
pub const WM_GETDLGCODE: UINT = 0x0087;
pub const WM_KEYDOWN: UINT = 0x0100;
pub const DLGC_WANTARROWS: LRESULT = 0x0001;
pub const DLGC_WANTMESSAGE: LRESULT = 0x0004;
pub const VK_RETURN: usize = 0x0D;
pub const VK_ESCAPE: usize = 0x1B;
pub const VK_LEFT: usize = 0x25;
pub const VK_UP: usize = 0x26;
pub const VK_RIGHT: usize = 0x27;
pub const VK_DOWN: usize = 0x28;
pub const BN_CLICKED = 0;
pub const GWL_STYLE: c_int = -16;
pub const BS_RADIOBUTTON: DWORD = 0x00000004;
pub const BS_GROUPBOX: DWORD = 0x00000007;
pub const WS_EX_CONTROLPARENT: DWORD = 0x00010000;

pub const HDI_FORMAT: UINT = 0x4;
pub const HDF_SORTDOWN: i32 = 0x200;
pub const HDF_SORTUP: i32 = 0x400;
pub const LVCF_TEXT: UINT = 0x4;
pub const LVCF_SUBITEM: UINT = 0x8;

const HDM_FIRST: UINT = 0x1200;
pub const HDM_GETITEMW: UINT = HDM_FIRST + 11;
pub const HDM_SETITEMW: UINT = HDM_FIRST + 12;
pub const HDM_GETITEMCOUNT: UINT = HDM_FIRST + 0;
pub const LVM_GETHEADER: UINT = LVM_FIRST + 31;
pub const LVM_DELETECOLUMN: UINT = LVM_FIRST + 28;

pub const HDITEMW = extern struct {
	mask: UINT,
	cxy: i32,
	pszText: LPWSTR,
	hbm: HBITMAP,
	cchTextMax: i32,
	fmt: i32,
	lParam: LPARAM,
	iImage: i32,
	iOrder: i32,
	type: UINT,
	pvFilter: ?*anyopaque,
	state: UINT,
};
