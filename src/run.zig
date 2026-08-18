const std = @import("std");
const win32 = @import("win32.zig");
const resource = @import("resource.zig");
const theme = @import("theme.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

fn editSubclassProc(hwnd: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM, id: win32.UINT_PTR, data: win32.DWORD_PTR) callconv(.c) win32.LRESULT {
	_ = id;
	_ = data;
	if (msg == win32.WM_CHAR and wp == 1) { // Ctrl+A: select all
		_ = win32.SendMessageW(hwnd, win32.EM_SETSEL, 0, -1);
		return 0;
	}
	return win32.DefSubclassProc(hwnd, msg, wp, lp);
}

fn browseForFile(hdlg: win32.HWND) void {
	var path: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
	var ofn: win32.OPENFILENAMEW = std.mem.zeroes(win32.OPENFILENAMEW);
	ofn.lStructSize = @sizeOf(win32.OPENFILENAMEW);
	ofn.hwndOwner = hdlg;
	ofn.lpstrFilter = L("Programs (*.exe;*.bat;*.cmd)\x00*.exe;*.bat;*.cmd\x00All Files (*.*)\x00*.*\x00");
	ofn.lpstrFile = &path;
	ofn.nMaxFile = @intCast(win32.MAX_PATH);
	ofn.Flags = win32.OFN_FILEMUSTEXIST | win32.OFN_HIDEREADONLY;
	if (win32.GetOpenFileNameW(&ofn) != 0)
		_ = win32.SetDlgItemTextW(hdlg, resource.IDC_RUN_EDIT, &path);
}

fn runCommand(hdlg: win32.HWND) void {
	var cmd: [win32.MAX_PATH:0]u16 = std.mem.zeroes([win32.MAX_PATH:0]u16);
	_ = win32.GetDlgItemTextW(hdlg, resource.IDC_RUN_EDIT, &cmd, @intCast(win32.MAX_PATH));
	win32.PathRemoveBlanksW(&cmd);
	if (cmd[0] == 0) return;
	var sei: win32.SHELLEXECUTEINFOW = std.mem.zeroes(win32.SHELLEXECUTEINFOW);
	sei.cbSize = @sizeOf(win32.SHELLEXECUTEINFOW);
	sei.fMask = win32.SEE_MASK_DOENVSUBST;
	sei.hwnd = hdlg;
	sei.lpVerb = L("open");
	sei.lpFile = &cmd;
	sei.nShow = win32.SW_SHOWNORMAL;
	// ShellExecuteEx shows its own error dialog on failure, just keep ours open
	if (win32.ShellExecuteExW(&sei) != 0)
		_ = win32.EndDialog(hdlg, 1);
}

fn runDlgProc(hdlg: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM) callconv(.c) win32.INT_PTR {
	_ = lp;
	switch (msg) {
		win32.WM_INITDIALOG => {
			theme.applyTitlebar(hdlg);
			_ = win32.SendDlgItemMessageW(hdlg, resource.IDC_RUN_EDIT, win32.EM_SETLIMITTEXT, @intCast(win32.MAX_PATH - 1), 0);
			_ = win32.EnableWindow(win32.GetDlgItem(hdlg, win32.IDOK), 0);
			_ = win32.SetWindowSubclass(win32.GetDlgItem(hdlg, resource.IDC_RUN_EDIT), editSubclassProc, 0, 0);
			return 1;
		},
		win32.WM_COMMAND => {
			const low: u16 = @truncate(wp);
			const high: u16 = @truncate(wp >> 16);
			if (low == resource.IDC_RUN_EDIT and high == @as(u16, win32.EN_CHANGE)) {
				const has_text = win32.GetWindowTextLengthW(win32.GetDlgItem(hdlg, resource.IDC_RUN_EDIT)) > 0;
				_ = win32.EnableWindow(win32.GetDlgItem(hdlg, win32.IDOK), if (has_text) 1 else 0);
				return 1;
			}
			if (low == resource.IDC_RUN_BROWSE) {
				browseForFile(hdlg);
				return 1;
			}
			if (low == win32.IDOK) {
				runCommand(hdlg);
				return 1;
			}
			if (low == win32.IDCANCEL) {
				_ = win32.EndDialog(hdlg, 0);
				return 1;
			}
		},
		win32.WM_CTLCOLORDLG => {
			const br = theme.bgBrush();
			if (br != null) return @bitCast(@intFromPtr(br));
		},
		win32.WM_CTLCOLORSTATIC, win32.WM_CTLCOLORBTN, win32.WM_CTLCOLOREDIT => {
			const br = theme.ctlColor(@ptrFromInt(@as(usize, @bitCast(wp))));
			if (br != null) return @bitCast(@intFromPtr(br));
		},
		else => {},
	}
	return 0;
}

pub export fn openDialog(parent: win32.HWND) callconv(.c) void {
	_ = win32.DialogBoxParamW(win32.GetModuleHandleW(null), @ptrFromInt(resource.IDD_RUN), parent, runDlgProc, 0);
}
