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

void tray_update_tip(double cpu_pct) {
	NOTIFYICONDATA nid = {0};
	nid.cbSize = sizeof(nid);
	nid.hWnd = s_hwnd;
	nid.uID = s_uid;
	nid.uFlags = NIF_TIP;
	MEMORYSTATUSEX ms = {0};
	ms.dwLength = sizeof(ms);
	GlobalMemoryStatusEx(&ms);
	int mem_mb = (int)((ms.ullTotalPhys - ms.ullAvailPhys) / (1024 * 1024));
	int cpu_whole = (int)cpu_pct;
	int cpu_frac = (int)((cpu_pct - cpu_whole) * 100.0 + 0.5);
	if (cpu_frac >= 100) {
		cpu_whole++;
		cpu_frac = 0;
	}
	if (mem_mb > 1024) {
		int mem_gb_int = mem_mb / 1024;
		int mem_gb_frac = (mem_mb % 1024) * 100 / 1024;
		wnsprintf(nid.szTip, 128, L"CPU %d.%02d%%, %d.%02d GB memory used", cpu_whole, cpu_frac, mem_gb_int, mem_gb_frac);
	} else {
		wnsprintf(nid.szTip, 128, L"CPU %d.%02d%%, %d MB memory used", cpu_whole, cpu_frac, mem_mb);
	}
	Shell_NotifyIcon(NIM_MODIFY, &nid);
}

void tray_restore() {
	ShowWindow(s_hwnd, SW_SHOW);
	SetForegroundWindow(s_hwnd);
}
