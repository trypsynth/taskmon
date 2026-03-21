#include "settings.h"
#include "resource.h"
#include <shlwapi.h>

const UINT REFRESH_MS[REFRESH_OPTION_COUNT] = { 0, 5000, 10000, 30000, 60000 };
const wchar_t* const REFRESH_LABELS[REFRESH_OPTION_COUNT] = { L"Off", L"5 seconds", L"10 seconds", L"30 seconds", L"1 minute" };

static INT_PTR CALLBACK settings_dlg_proc(HWND hdlg, UINT msg, WPARAM wp, LPARAM lp) {
	switch (msg) {
	case WM_INITDIALOG: {
		UINT current_ms = (UINT)lp;
		HWND combo = GetDlgItem(hdlg, IDC_REFRESH_COMBO);
		int sel = 0;
		for (int i = 0; i < REFRESH_OPTION_COUNT; ++i) {
			SendMessage(combo, CB_ADDSTRING, 0, (LPARAM)REFRESH_LABELS[i]);
			if (REFRESH_MS[i] == current_ms) sel = i;
		}
		SendMessage(combo, CB_SETCURSEL, sel, 0);
		return TRUE;
	}
	case WM_COMMAND:
		if (LOWORD(wp) == IDOK) {
			HWND combo = GetDlgItem(hdlg, IDC_REFRESH_COMBO);
			int sel = (int)SendMessage(combo, CB_GETCURSEL, 0, 0);
			EndDialog(hdlg, sel >= 0 && sel < REFRESH_OPTION_COUNT ? sel : 0);
			return TRUE;
		}
		if (LOWORD(wp) == IDCANCEL) {
			EndDialog(hdlg, -1);
			return TRUE;
		}
		break;
	}
	return FALSE;
}

UINT open_settings(HWND parent, UINT current_ms) {
	INT_PTR sel = DialogBoxParam(GetModuleHandle(NULL), MAKEINTRESOURCE(IDD_SETTINGS), parent, settings_dlg_proc, (LPARAM)current_ms);
	if (sel < 0 || sel >= REFRESH_OPTION_COUNT) return (UINT)-1;
	return REFRESH_MS[sel];
}

static void get_ini_path(wchar_t* buf) {
	GetModuleFileName(NULL, buf, MAX_PATH);
	PathRemoveFileSpec(buf);
	PathAppend(buf, L"taskmon.ini");
}

void settings_load(sort_prefs* prefs, const wchar_t** labels, const sort_field* fields) {
	wchar_t path[MAX_PATH];
	get_ini_path(path);
	prefs->field = fields[0];
	prefs->refresh_ms = 0;
	for (int i = 0; i < SORT_COUNT; i++) prefs->desc[i] = FALSE;
	wchar_t field_buf[32];
	GetPrivateProfileString(L"sort", L"field", labels[0], field_buf, 32, path);
	for (int i = 0; i < SORT_COUNT; i++) {
		if (StrCmpI(field_buf, labels[i]) == 0) {
			prefs->field = fields[i];
			break;
		}
	}
	for (int i = 0; i < SORT_COUNT; i++) {
		wchar_t key[32], val[4];
		wnsprintf(key, 32, L"%s_desc", labels[i]);
		GetPrivateProfileString(L"sort", key, L"0", val, 4, path);
		prefs->desc[i] = (val[0] == L'1');
	}
	wchar_t ms_buf[16];
	GetPrivateProfileString(L"refresh", L"interval_ms", L"2000", ms_buf, 16, path);
	prefs->refresh_ms = (UINT)StrToInt(ms_buf);
}

void settings_save(const sort_prefs* prefs, const wchar_t** labels, const sort_field* fields) {
	wchar_t path[MAX_PATH];
	get_ini_path(path);
	for (int i = 0; i < SORT_COUNT; i++) {
		if (fields[i] == prefs->field) WritePrivateProfileString(L"sort", L"field", labels[i], path);
		wchar_t key[32];
		wnsprintf(key, 32, L"%s_desc", labels[i]);
		WritePrivateProfileString(L"sort", key, prefs->desc[i] ? L"1" : L"0", path);
	}
	wchar_t ms_str[16];
	wnsprintf(ms_str, 16, L"%u", prefs->refresh_ms);
	WritePrivateProfileString(L"refresh", L"interval_ms", ms_str, path);
}
