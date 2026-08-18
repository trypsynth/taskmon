// Hand rolled, non zigwin32 Win32 bindings, grown incrementally as more of
// taskmon is ported from C to Zig. Mirrors the approach used in ../sysinfo.

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
pub extern "user32" fn CreateWindowExW(dwExStyle: DWORD, lpClassName: LPCWSTR, lpWindowName: LPCWSTR, dwStyle: DWORD, X: i32, Y: i32, nWidth: i32, nHeight: i32, hWndParent: HWND, hMenu: HMENU, hInstance: HINSTANCE, lpParam: ?*anyopaque) callconv(.c) HWND;
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

pub extern "shlwapi" fn StrFormatByteSizeW(qwSize: i64, pszBuf: [*:0]u16, cchBuf: UINT) callconv(.c) ?[*:0]u16;
pub extern "kernel32" fn FileTimeToLocalFileTime(lpFileTime: *const FILETIME, lpLocalFileTime: *FILETIME) callconv(.c) BOOL;
pub extern "kernel32" fn FileTimeToSystemTime(lpFileTime: *const FILETIME, lpSystemTime: *SYSTEMTIME) callconv(.c) BOOL;
pub extern "kernel32" fn GetLocalTime(lpSystemTime: *SYSTEMTIME) callconv(.c) void;
pub extern "kernel32" fn lstrcatW(lpString1: [*:0]u16, lpString2: LPCWSTR) callconv(.c) ?[*:0]u16;

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
