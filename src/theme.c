#include "theme.h"
#include <commctrl.h>
#include <uxtheme.h>
#include <dwmapi.h>

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

#define DARK_BG   RGB(32, 32, 32)
#define DARK_TEXT RGB(255, 255, 255)

static BOOL   g_dark = FALSE;
static HBRUSH g_dark_brush = NULL;

void theme_update(void) {
	DWORD value = 1, size = sizeof(value);
	RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL, &value, &size);
	g_dark = (value == 0);
}

BOOL theme_is_dark(void) {
	return g_dark;
}

void theme_apply_titlebar(HWND hwnd) {
	BOOL dark = g_dark;
	DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, sizeof(BOOL));
}

void theme_apply_listview(HWND hwnd_list) {
	if (g_dark) {
		SetWindowTheme(hwnd_list, L"DarkMode_Explorer", NULL);
		ListView_SetBkColor(hwnd_list, DARK_BG);
		ListView_SetTextBkColor(hwnd_list, DARK_BG);
		ListView_SetTextColor(hwnd_list, DARK_TEXT);
	} else {
		SetWindowTheme(hwnd_list, L"Explorer", NULL);
		ListView_SetBkColor(hwnd_list, CLR_DEFAULT);
		ListView_SetTextBkColor(hwnd_list, CLR_DEFAULT);
		ListView_SetTextColor(hwnd_list, CLR_DEFAULT);
	}
	InvalidateRect(hwnd_list, NULL, TRUE);
}

void theme_apply_button(HWND hwnd) {
	SetWindowTheme(hwnd, g_dark ? L"DarkMode_Explorer" : L"Explorer", NULL);
}

HBRUSH theme_ctl_color(HDC hdc) {
	if (!g_dark) return NULL;
	if (!g_dark_brush) g_dark_brush = CreateSolidBrush(DARK_BG);
	SetTextColor(hdc, DARK_TEXT);
	SetBkColor(hdc, DARK_BG);
	return g_dark_brush;
}

HBRUSH theme_bg_brush(void) {
	if (!g_dark) return NULL;
	if (!g_dark_brush) g_dark_brush = CreateSolidBrush(DARK_BG);
	return g_dark_brush;
}
