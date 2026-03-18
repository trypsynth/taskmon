#include "tray.h"
#include <shellapi.h>
#include <shlwapi.h>

static UINT s_uid = 1;
static HWND s_hwnd = NULL;
static UINT s_msg = 0;
static wchar_t s_name[64];

void tray_add(HWND hwnd, UINT callback_msg, const wchar_t* app_name) {
	s_hwnd = hwnd;
	s_msg = callback_msg;
	lstrcpy(s_name, app_name);
	NOTIFYICONDATA nid = {0};
	nid.cbSize = sizeof(nid);
	nid.hWnd = s_hwnd;
	nid.uID = s_uid;
	nid.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE;
	nid.uCallbackMessage = s_msg;
	nid.hIcon = (HICON)LoadImage(NULL, (LPCWSTR)IDI_APPLICATION, IMAGE_ICON, 0, 0, LR_SHARED | LR_DEFAULTSIZE);
	lstrcpy(nid.szTip, s_name);
	Shell_NotifyIcon(NIM_ADD, &nid);
}

void tray_remove() {
	NOTIFYICONDATA nid = {0};
	nid.cbSize = sizeof(nid);
	nid.hWnd = s_hwnd;
	nid.uID = s_uid;
	Shell_NotifyIcon(NIM_DELETE, &nid);
}

void tray_update_tip(double cpu_pct, SIZE_T mem_bytes) {
	NOTIFYICONDATA nid = {0};
	nid.cbSize = sizeof(nid);
	nid.hWnd = s_hwnd;
	nid.uID = s_uid;
	nid.uFlags = NIF_TIP;
	int mem_mb = (int)(mem_bytes / (1024 * 1024));
	if (mem_mb > 1024) {
		int mem_gb_int = mem_mb / 1024;
		int mem_gb_frac = (mem_mb % 1024) * 10 / 1024;
		wnsprintf(nid.szTip, 128, L"%s, CPU %.1f%%, %d.%d GB memory used", s_name, cpu_pct, mem_gb_int, mem_gb_frac);
	} else {
		wnsprintf(nid.szTip, 128, L"%s, CPU %.1f%%, %d MB memory used", s_name, cpu_pct, mem_mb);
	}
	Shell_NotifyIcon(NIM_MODIFY, &nid);
}

void tray_restore() {
	ShowWindow(s_hwnd, SW_SHOW);
	SetForegroundWindow(s_hwnd);
}
