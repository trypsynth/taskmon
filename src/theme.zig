const std = @import("std");
const win32 = @import("win32.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

fn rgb(r: u8, g: u8, b: u8) win32.COLORREF {
	return @as(u32, r) | (@as(u32, g) << 8) | (@as(u32, b) << 16);
}

const DARK_BG: win32.COLORREF = rgb(32, 32, 32);
const DARK_TEXT: win32.COLORREF = rgb(255, 255, 255);
const CLR_DEFAULT: win32.COLORREF = 0xFF000000;
const COLOR_NONE: win32.COLORREF = 0xFFFFFFFF;
const DWMWA_USE_IMMERSIVE_DARK_MODE: win32.DWORD = 20;

fn colorParam(c: win32.COLORREF) win32.LPARAM {
	return @intCast(c);
}

const LVM_SETBKCOLOR: win32.UINT = 0x1000 + 1;
const LVM_SETTEXTCOLOR: win32.UINT = 0x1000 + 36;
const LVM_SETTEXTBKCOLOR: win32.UINT = 0x1000 + 38;
const TVM_SETBKCOLOR: win32.UINT = 0x1100 + 29;
const TVM_SETTEXTCOLOR: win32.UINT = 0x1100 + 30;

var g_dark: win32.BOOL = 0;
var g_dark_brush: win32.HBRUSH = null;

pub fn update() void {
	var value: win32.DWORD = 1;
	var size: win32.DWORD = @sizeOf(win32.DWORD);
	_ = win32.RegGetValueW(win32.HKEY_CURRENT_USER, L("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"), L("AppsUseLightTheme"), win32.RRF_RT_REG_DWORD, null, &value, &size);
	g_dark = if (value == 0) 1 else 0;
}

pub fn isDark() win32.BOOL {
	return g_dark;
}

pub fn applyTitlebar(hwnd: win32.HWND) void {
	const dark = g_dark;
	_ = win32.DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, @sizeOf(win32.BOOL));
}

pub fn applyListview(hwnd_list: win32.HWND) void {
	if (g_dark != 0) {
		_ = win32.SetWindowTheme(hwnd_list, L("DarkMode_Explorer"), null);
		_ = win32.SendMessageW(hwnd_list, LVM_SETBKCOLOR, 0, colorParam(DARK_BG));
		_ = win32.SendMessageW(hwnd_list, LVM_SETTEXTBKCOLOR, 0, colorParam(DARK_BG));
		_ = win32.SendMessageW(hwnd_list, LVM_SETTEXTCOLOR, 0, colorParam(DARK_TEXT));
	} else {
		_ = win32.SetWindowTheme(hwnd_list, L("Explorer"), null);
		_ = win32.SendMessageW(hwnd_list, LVM_SETBKCOLOR, 0, colorParam(CLR_DEFAULT));
		_ = win32.SendMessageW(hwnd_list, LVM_SETTEXTBKCOLOR, 0, colorParam(CLR_DEFAULT));
		_ = win32.SendMessageW(hwnd_list, LVM_SETTEXTCOLOR, 0, colorParam(CLR_DEFAULT));
	}
	_ = win32.InvalidateRect(hwnd_list, null, 1);
}

pub fn applyButton(hwnd: win32.HWND) void {
	_ = win32.SetWindowTheme(hwnd, if (g_dark != 0) L("DarkMode_Explorer") else L("Explorer"), null);
}

pub fn applyTreeview(hwnd_tree: win32.HWND) void {
	if (g_dark != 0) {
		_ = win32.SetWindowTheme(hwnd_tree, L("DarkMode_Explorer"), null);
		_ = win32.SendMessageW(hwnd_tree, TVM_SETBKCOLOR, 0, colorParam(DARK_BG));
		_ = win32.SendMessageW(hwnd_tree, TVM_SETTEXTCOLOR, 0, colorParam(DARK_TEXT));
	} else {
		_ = win32.SetWindowTheme(hwnd_tree, L("Explorer"), null);
		_ = win32.SendMessageW(hwnd_tree, TVM_SETBKCOLOR, 0, colorParam(COLOR_NONE));
		_ = win32.SendMessageW(hwnd_tree, TVM_SETTEXTCOLOR, 0, colorParam(COLOR_NONE));
	}
	_ = win32.InvalidateRect(hwnd_tree, null, 1);
}

pub fn ctlColor(hdc: win32.HDC) win32.HBRUSH {
	if (g_dark == 0) return null;
	if (g_dark_brush == null) g_dark_brush = win32.CreateSolidBrush(DARK_BG);
	_ = win32.SetTextColor(hdc, DARK_TEXT);
	_ = win32.SetBkColor(hdc, DARK_BG);
	return g_dark_brush;
}

pub fn bgBrush() win32.HBRUSH {
	if (g_dark == 0) return null;
	if (g_dark_brush == null) g_dark_brush = win32.CreateSolidBrush(DARK_BG);
	return g_dark_brush;
}
