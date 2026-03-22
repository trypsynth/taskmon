#include "settings.h"
#include "resource.h"
#include <shlwapi.h>

const column_def COLUMNS[COL_COUNT] = {
	{ L"Name",    260, SORT_FIELD_NAME,    TRUE,  TRUE  },
	{ L"PID",      80, SORT_FIELD_PID,     FALSE, TRUE  },
	{ L"CPU",      90, SORT_FIELD_CPU,     FALSE, TRUE  },
	{ L"Memory",  120, SORT_FIELD_MEMORY,  FALSE, TRUE  },
	{ L"Threads",  70, SORT_FIELD_THREADS, FALSE, FALSE },
	{ L"Handles",  70, SORT_FIELD_HANDLES, FALSE, FALSE },
};

const UINT REFRESH_MS[REFRESH_OPTION_COUNT] = { 0, 5000, 10000, 30000, 60000 };
const wchar_t* const REFRESH_LABELS[REFRESH_OPTION_COUNT] = { L"Off", L"5 seconds", L"10 seconds", L"30 seconds", L"1 minute" };

typedef struct {
	UINT refresh_ms;
	BOOL visible[COL_COUNT];
} settings_dlg_data;

static INT_PTR CALLBACK settings_dlg_proc(HWND hdlg, UINT msg, WPARAM wp, LPARAM lp) {
	switch (msg) {
	case WM_INITDIALOG: {
		SetWindowLongPtr(hdlg, DWLP_USER, lp);
		settings_dlg_data* data = (settings_dlg_data*)lp;
		HWND combo = GetDlgItem(hdlg, IDC_REFRESH_COMBO);
		int sel = 0;
		for (int i = 0; i < REFRESH_OPTION_COUNT; ++i) {
			SendMessage(combo, CB_ADDSTRING, 0, (LPARAM)REFRESH_LABELS[i]);
			if (REFRESH_MS[i] == data->refresh_ms) sel = i;
		}
		SendMessage(combo, CB_SETCURSEL, sel, 0);
		HFONT font = (HFONT)SendMessage(hdlg, WM_GETFONT, 0, 0);
		for (int i = 0; i < COL_COUNT; ++i) {
			HWND chk = CreateWindow(L"BUTTON", COLUMNS[i].label, WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTOCHECKBOX, 12, 36 + i * 11, 170, 10, hdlg, (HMENU)(INT_PTR)(IDC_COL_BASE + i), GetModuleHandle(NULL), NULL);
			SendMessage(chk, WM_SETFONT, (WPARAM)font, FALSE);
			SendMessage(chk, BM_SETCHECK, data->visible[i] ? BST_CHECKED : BST_UNCHECKED, 0);
			if (COLUMNS[i].always_visible) EnableWindow(chk, FALSE);
		}
		// Move OK and Cancel after the checkboxes in Z-order so tab goes combo -> checkboxes -> OK -> Cancel
		HWND last_chk = GetDlgItem(hdlg, IDC_COL_BASE + COL_COUNT - 1);
		SetWindowPos(GetDlgItem(hdlg, IDOK), last_chk, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
		SetWindowPos(GetDlgItem(hdlg, IDCANCEL), GetDlgItem(hdlg, IDOK), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
		return TRUE;
	}
	case WM_COMMAND:
		if (LOWORD(wp) == IDOK) {
			settings_dlg_data* data = (settings_dlg_data*)GetWindowLongPtr(hdlg, DWLP_USER);
			HWND combo = GetDlgItem(hdlg, IDC_REFRESH_COMBO);
			int sel = (int)SendMessage(combo, CB_GETCURSEL, 0, 0);
			data->refresh_ms = (sel >= 0 && sel < REFRESH_OPTION_COUNT) ? REFRESH_MS[sel] : 0;
			for (int i = 0; i < COL_COUNT; ++i) {
				if (!COLUMNS[i].always_visible) data->visible[i] = SendMessage(GetDlgItem(hdlg, IDC_COL_BASE + i), BM_GETCHECK, 0, 0) == BST_CHECKED;
			}
			EndDialog(hdlg, 1);
			return TRUE;
		}
		if (LOWORD(wp) == IDCANCEL) {
			EndDialog(hdlg, 0);
			return TRUE;
		}
		break;
	}
	return FALSE;
}

BOOL open_settings(HWND parent, UINT current_ms, const BOOL* current_visible, UINT* out_ms, BOOL* out_visible) {
	settings_dlg_data data;
	data.refresh_ms = current_ms;
	for (int i = 0; i < COL_COUNT; ++i) data.visible[i] = current_visible[i];
	INT_PTR result = DialogBoxParam(GetModuleHandle(NULL), MAKEINTRESOURCE(IDD_SETTINGS), parent, settings_dlg_proc, (LPARAM)&data);
	if (!result) return FALSE;
	*out_ms = data.refresh_ms;
	for (int i = 0; i < COL_COUNT; ++i) out_visible[i] = data.visible[i];
	return TRUE;
}

static void get_ini_path(wchar_t* buf) {
	GetModuleFileName(NULL, buf, MAX_PATH);
	PathRemoveFileSpec(buf);
	PathAppend(buf, L"taskmon.ini");
}

void settings_load(sort_prefs* prefs) {
	wchar_t path[MAX_PATH];
	get_ini_path(path);
	prefs->field = SORT_FIELD_NAME;
	prefs->refresh_ms = 0;
	for (int i = 0; i < COL_COUNT; ++i) {
		prefs->desc[i] = FALSE;
		prefs->visible[i] = COLUMNS[i].always_visible;
	}
	wchar_t field_buf[64];
	GetPrivateProfileString(L"sort", L"field", COLUMNS[0].label, field_buf, 64, path);
	for (int i = 0; i < COL_COUNT; ++i) {
		if (StrCmpI(field_buf, COLUMNS[i].label) == 0) {
			prefs->field = COLUMNS[i].field;
			break;
		}
	}
	for (int i = 0; i < COL_COUNT; ++i) {
		wchar_t key[64], val[4];
		wnsprintf(key, 64, L"%s_desc", COLUMNS[i].label);
		GetPrivateProfileString(L"sort", key, L"0", val, 4, path);
		prefs->desc[i] = (val[0] == L'1');
	}
	wchar_t ms_buf[16];
	GetPrivateProfileString(L"refresh", L"interval_ms", L"2000", ms_buf, 16, path);
	prefs->refresh_ms = (UINT)StrToInt(ms_buf);
	for (int i = 0; i < COL_COUNT; ++i) {
		wchar_t key[64], val[4];
		wnsprintf(key, 64, L"%s_visible", COLUMNS[i].label);
		wchar_t def[2] = { COLUMNS[i].default_visible ? L'1' : L'0', L'\0' };
		GetPrivateProfileString(L"columns", key, def, val, 4, path);
		prefs->visible[i] = COLUMNS[i].always_visible || (val[0] == L'1');
	}
}

void settings_save(const sort_prefs* prefs) {
	wchar_t path[MAX_PATH];
	get_ini_path(path);
	for (int i = 0; i < COL_COUNT; ++i) {
		if (COLUMNS[i].field == prefs->field)
			WritePrivateProfileString(L"sort", L"field", COLUMNS[i].label, path);
		wchar_t key[64];
		wnsprintf(key, 64, L"%s_desc", COLUMNS[i].label);
		WritePrivateProfileString(L"sort", key, prefs->desc[i] ? L"1" : L"0", path);
	}
	wchar_t ms_str[16];
	wnsprintf(ms_str, 16, L"%u", prefs->refresh_ms);
	WritePrivateProfileString(L"refresh", L"interval_ms", ms_str, path);
	for (int i = 0; i < COL_COUNT; ++i) {
		if (COLUMNS[i].always_visible) continue;
		wchar_t key[64];
		wnsprintf(key, 64, L"%s_visible", COLUMNS[i].label);
		WritePrivateProfileString(L"columns", key, prefs->visible[i] ? L"1" : L"0", path);
	}
}
