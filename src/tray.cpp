#include <cstdio>
#include "tray.hpp"
#include <shellapi.h>

static constexpr UINT k_uid  = 1;
static HWND           s_hwnd = nullptr;
static UINT           s_msg  = 0;
static wchar_t        s_name[64] = L"App";

void tray_add(HWND hwnd, UINT callback_msg, const wchar_t* app_name) {
	s_hwnd = hwnd;
	s_msg  = callback_msg;
	wcscpy_s(s_name, app_name);
	NOTIFYICONDATA nid{};
	nid.cbSize           = sizeof(nid);
	nid.hWnd             = s_hwnd;
	nid.uID              = k_uid;
	nid.uFlags           = NIF_ICON | NIF_TIP | NIF_MESSAGE;
	nid.uCallbackMessage = s_msg;
	nid.hIcon            = static_cast<HICON>(LoadImage(nullptr, IDI_APPLICATION, IMAGE_ICON, 0, 0, LR_SHARED));
	wcscpy_s(nid.szTip, s_name);
	Shell_NotifyIcon(NIM_ADD, &nid);
}

void tray_remove() {
	NOTIFYICONDATA nid{};
	nid.cbSize = sizeof(nid);
	nid.hWnd   = s_hwnd;
	nid.uID    = k_uid;
	Shell_NotifyIcon(NIM_DELETE, &nid);
}

void tray_update_tip(double cpu_pct, SIZE_T mem_bytes) {
	NOTIFYICONDATA nid{};
	nid.cbSize = sizeof(nid);
	nid.hWnd   = s_hwnd;
	nid.uID    = k_uid;
	nid.uFlags = NIF_TIP;
	swprintf_s(nid.szTip, L"%s, CPU %.1f%%, %.1f GB memory used", s_name, cpu_pct, static_cast<double>(mem_bytes) / (1024.0 * 1024.0 * 1024.0));
	Shell_NotifyIcon(NIM_MODIFY, &nid);
}

void tray_restore() {
	ShowWindow(s_hwnd, SW_SHOW);
	SetForegroundWindow(s_hwnd);
}
