#include "settings.h"
#include "resource.h"
#include "theme.h"
#include <commctrl.h>
#include <shlwapi.h>
#include <uxtheme.h>

const column_def COLUMNS[COL_COUNT] = {
	{ L"Name", L"Name", 260, SORT_FIELD_NAME, TRUE, TRUE },
	{ L"PID", L"PID", 80, SORT_FIELD_PID, FALSE, TRUE },
	{ L"CPU", L"CPU %", 90, SORT_FIELD_CPU, FALSE, TRUE },
	{ L"Memory", L"Memory", 120, SORT_FIELD_MEMORY, FALSE, TRUE },
	{ L"Threads", L"Threads", 70, SORT_FIELD_THREADS, FALSE, FALSE },
	{ L"Handles", L"Handles", 70, SORT_FIELD_HANDLES, FALSE, FALSE },
	{ L"Started", L"Started", 100, SORT_FIELD_STARTTIME, FALSE, FALSE },
	{ L"Priority", L"Priority", 100, SORT_FIELD_PRIORITY, FALSE, FALSE },
	{ L"Disk I/O",     L"Disk I/O",     100, SORT_FIELD_DISK_IO,       FALSE, FALSE },
	{ L"Private Bytes", L"Private Bytes", 120, SORT_FIELD_PRIVATE_BYTES, FALSE, FALSE },
	{ L"Page Faults",  L"Page Faults",  100, SORT_FIELD_PAGE_FAULTS,   FALSE, FALSE },
	{ L"User",         L"User",         120, SORT_FIELD_USER,          FALSE, FALSE },
	{ L"Command Line", L"Command Line", 300, SORT_FIELD_CMDLINE,       FALSE, FALSE },
	{ L"Architecture",    L"Architecture",  70,  SORT_FIELD_ARCH,           FALSE, FALSE },
	{ L"Session",         L"Session",       60,  SORT_FIELD_SESSION,        FALSE, FALSE },
	{ L"Peak Memory",     L"Peak Memory",      120, SORT_FIELD_PEAK_WORKING_SET, FALSE, FALSE },
	{ L"Virtual Memory",  L"Virtual Memory",   120, SORT_FIELD_VIRTUAL_MEM,    FALSE, FALSE },
};

const UINT REFRESH_MS[REFRESH_OPTION_COUNT] = { 0, 5000, 10000, 30000, 60000 };
const wchar_t* const REFRESH_LABELS[REFRESH_OPTION_COUNT] = { L"Off", L"5 seconds", L"10 seconds", L"30 seconds", L"1 minute" };

typedef struct {
	UINT refresh_ms;
	BOOL visible[COL_COUNT];
	BOOL skip_kill_confirm;
} settings_dlg_data;

static INT_PTR CALLBACK settings_dlg_proc(HWND hdlg, UINT msg, WPARAM wp, LPARAM lp) {
	switch (msg) {
	case WM_INITDIALOG: {
		SetWindowLongPtr(hdlg, DWLP_USER, lp);
		theme_apply_titlebar(hdlg);
		settings_dlg_data* data = (settings_dlg_data*)lp;
		HWND combo = GetDlgItem(hdlg, IDC_REFRESH_COMBO);
		SetWindowTheme(combo, theme_is_dark() ? L"DarkMode_Explorer" : L"Explorer", NULL);
		int sel = 0;
		for (int i = 0; i < REFRESH_OPTION_COUNT; ++i) {
			SendMessage(combo, CB_ADDSTRING, 0, (LPARAM)REFRESH_LABELS[i]);
			if (REFRESH_MS[i] == data->refresh_ms) sel = i;
		}
		SendMessage(combo, CB_SETCURSEL, sel, 0);
		HFONT font = (HFONT)SendMessage(hdlg, WM_GETFONT, 0, 0);
		HWND lv = GetDlgItem(hdlg, IDC_COL_LIST);
		SendMessage(lv, WM_SETFONT, (WPARAM)font, FALSE);
		ListView_SetExtendedListViewStyle(lv, LVS_EX_CHECKBOXES);
		LVCOLUMN lvc = {0};
		lvc.mask = LVCF_WIDTH;
		lvc.cx = 1000;
		ListView_InsertColumn(lv, 0, &lvc);
		int j = 0;
		for (int i = 0; i < COL_COUNT; ++i) {
			if (COLUMNS[i].always_visible) continue;
			LVITEM lvi = {0};
			lvi.mask = LVIF_TEXT | LVIF_PARAM;
			lvi.iItem = j++;
			lvi.pszText = (LPWSTR)COLUMNS[i].label;
			lvi.lParam = i;
			ListView_InsertItem(lv, &lvi);
			ListView_SetCheckState(lv, lvi.iItem, data->visible[i]);
		}
		if (j > 0) ListView_SetItemState(lv, 0, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
		theme_apply_listview(lv);
		HWND skip_chk = CreateWindow(L"BUTTON", L"Disable end task confirmation (not recommended)", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTOCHECKBOX, 7, 118, 176, 10, hdlg, (HMENU)(INT_PTR)IDC_SKIP_CONFIRM, GetModuleHandle(NULL), NULL);
		SendMessage(skip_chk, WM_SETFONT, (WPARAM)font, FALSE);
		SendMessage(skip_chk, BM_SETCHECK, data->skip_kill_confirm ? BST_CHECKED : BST_UNCHECKED, 0);
		// Tab order: combo -> listview -> skip_chk -> OK -> Cancel
		SetWindowPos(skip_chk, lv, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
		SetWindowPos(GetDlgItem(hdlg, IDOK), skip_chk, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
		SetWindowPos(GetDlgItem(hdlg, IDCANCEL), GetDlgItem(hdlg, IDOK), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
		return TRUE;
	}
	case WM_COMMAND:
		if (LOWORD(wp) == IDOK) {
			settings_dlg_data* data = (settings_dlg_data*)GetWindowLongPtr(hdlg, DWLP_USER);
			HWND combo = GetDlgItem(hdlg, IDC_REFRESH_COMBO);
			int sel = (int)SendMessage(combo, CB_GETCURSEL, 0, 0);
			data->refresh_ms = (sel >= 0 && sel < REFRESH_OPTION_COUNT) ? REFRESH_MS[sel] : 0;
			HWND lv = GetDlgItem(hdlg, IDC_COL_LIST);
			int lv_count = ListView_GetItemCount(lv);
			for (int j = 0; j < lv_count; ++j) {
				LVITEM lvi2 = {0};
				lvi2.mask = LVIF_PARAM;
				lvi2.iItem = j;
				ListView_GetItem(lv, &lvi2);
				data->visible[(int)lvi2.lParam] = ListView_GetCheckState(lv, j) ? TRUE : FALSE;
			}
			data->skip_kill_confirm = SendMessage(GetDlgItem(hdlg, IDC_SKIP_CONFIRM), BM_GETCHECK, 0, 0) == BST_CHECKED;
			EndDialog(hdlg, 1);
			return TRUE;
		}
		if (LOWORD(wp) == IDCANCEL) {
			EndDialog(hdlg, 0);
			return TRUE;
		}
		break;
	case WM_CTLCOLORDLG: {
		HBRUSH br = theme_bg_brush();
		if (br) return (INT_PTR)br;
		break;
	}
	case WM_CTLCOLORSTATIC:
	case WM_CTLCOLORBTN:
	case WM_CTLCOLORLISTBOX:
	case WM_CTLCOLOREDIT: {
		HBRUSH br = theme_ctl_color((HDC)wp);
		if (br) return (INT_PTR)br;
		break;
	}
	}
	return FALSE;
}

BOOL open_settings(HWND parent, UINT current_ms, const BOOL* current_visible, BOOL current_skip_confirm, UINT* out_ms, BOOL* out_visible, BOOL* out_skip_confirm) {
	settings_dlg_data data;
	data.refresh_ms = current_ms;
	for (int i = 0; i < COL_COUNT; ++i) data.visible[i] = current_visible[i];
	data.skip_kill_confirm = current_skip_confirm;
	INT_PTR result = DialogBoxParam(GetModuleHandle(NULL), MAKEINTRESOURCE(IDD_SETTINGS), parent, settings_dlg_proc, (LPARAM)&data);
	if (!result) return FALSE;
	*out_ms = data.refresh_ms;
	for (int i = 0; i < COL_COUNT; ++i) out_visible[i] = data.visible[i];
	*out_skip_confirm = data.skip_kill_confirm;
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
	wchar_t skip_buf[4];
	GetPrivateProfileString(L"confirm", L"skip_kill", L"0", skip_buf, 4, path);
	prefs->skip_kill_confirm = (skip_buf[0] == L'1');
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
	WritePrivateProfileString(L"confirm", L"skip_kill", prefs->skip_kill_confirm ? L"1" : L"0", path);
	for (int i = 0; i < COL_COUNT; ++i) {
		if (COLUMNS[i].always_visible) continue;
		wchar_t key[64];
		wnsprintf(key, 64, L"%s_visible", COLUMNS[i].label);
		WritePrivateProfileString(L"columns", key, prefs->visible[i] ? L"1" : L"0", path);
	}
}
