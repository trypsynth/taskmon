#include "sortbar.h"
#include "wndproc.h"
#include "settings.h"
#include "resource.h"
#include "listview.h"
#include "theme.h"
#include <commctrl.h>
#include <shlwapi.h>

static LRESULT CALLBACK sort_group_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data) {
	UNREFERENCED_PARAMETER(id); UNREFERENCED_PARAMETER(data);
	if (msg == WM_COMMAND) return SendMessage(g_hwnd, msg, wp, lp);
	if (msg == WM_CTLCOLORBTN || msg == WM_CTLCOLORSTATIC) {
		LRESULT r = SendMessage(g_hwnd, msg, wp, lp);
		if (r) return r;
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}

static LRESULT CALLBACK sort_btn_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data) {
	UNREFERENCED_PARAMETER(id); UNREFERENCED_PARAMETER(data);
	if (msg == WM_GETDLGCODE) {
		LRESULT r = DefSubclassProc(hwnd, msg, wp, lp) | DLGC_WANTARROWS;
		MSG* pmsg = (MSG*)lp;
		if (pmsg && ((pmsg->message == WM_KEYDOWN && pmsg->wParam == VK_RETURN) || (pmsg->message == WM_CHAR && pmsg->wParam == '\r'))) r |= DLGC_WANTMESSAGE;
		return r;
	}
	if (msg == WM_CHAR && wp == '\r') return 0;
	if (msg == WM_KEYDOWN) {
		if (wp == VK_ESCAPE) {
			PostMessage(g_hwnd, WM_HIDE_TO_TRAY, 0, 0);
			return 0;
		}
		if (wp == VK_RETURN) {
			PostMessage(g_hwnd, WM_COMMAND, MAKEWPARAM(GetDlgCtrlID(hwnd), BN_CLICKED), (LPARAM)hwnd);
			return 0;
		}
		if (wp == VK_LEFT || wp == VK_RIGHT) {
			int idx = -1;
			for (int i = 0; i < g_sort_btn_count; ++i) {
				if (g_sort_btns[i] == hwnd) { idx = i; break; }
			}
			if (idx >= 0) {
				int next = (wp == VK_RIGHT) ? idx + 1 : idx - 1;
				if (next < 0 || next >= g_sort_btn_count) return 0;
				column_id cid = g_sort_btn_cols[next];
				g_prefs.field = COLUMNS[cid].field;
				wchar_t buf[64];
				wnsprintf(buf, 64, L"%s (%s)", COLUMNS[cid].label, g_prefs.desc[(int)g_prefs.field] ? L"descending" : L"ascending");
				SetWindowText(g_sort_btns[next], buf);
				SendMessage(g_sort_btns[next], BM_SETCHECK, BST_CHECKED, 0);
				update_tab_stop();
				SetFocus(g_sort_btns[next]);
				update_sort_ui();
				do_refresh();
				settings_save(&g_prefs);
				return 0;
			}
		}
		if (wp == VK_UP || wp == VK_DOWN) return 0;
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}

void update_tab_stop(void) {
	for (int i = 0; i < g_sort_btn_count; ++i) {
		LONG_PTR style = GetWindowLongPtr(g_sort_btns[i], GWL_STYLE);
		style = (COLUMNS[g_sort_btn_cols[i]].field == g_prefs.field) ? (style | WS_TABSTOP) : (style & ~WS_TABSTOP);
		SetWindowLongPtr(g_sort_btns[i], GWL_STYLE, style);
	}
}

void update_sort_ui(void) {
	for (int i = 0; i < g_sort_btn_count; ++i) {
		column_id cid = g_sort_btn_cols[i];
		BOOL active = (COLUMNS[cid].field == g_prefs.field);
		wchar_t buf[64];
		if (active) wnsprintf(buf, 64, L"%s (%s)", COLUMNS[cid].label, g_prefs.desc[(int)g_prefs.field] ? L"descending" : L"ascending");
		else lstrcpy(buf, COLUMNS[cid].label);
		SetWindowText(g_sort_btns[i], buf);
		SendMessage(g_sort_btns[i], BM_SETCHECK, active ? BST_CHECKED : BST_UNCHECKED, 0);
	}
	HWND header = ListView_GetHeader(g_hwnd_list);
	for (int i = 0; i < g_sort_btn_count; ++i) {
		column_id cid = g_sort_btn_cols[i];
		HDITEM hdi = {0};
		hdi.mask = HDI_FORMAT;
		Header_GetItem(header, i, &hdi);
		hdi.fmt &= ~(HDF_SORTUP | HDF_SORTDOWN);
		if (COLUMNS[cid].field == g_prefs.field) hdi.fmt |= g_prefs.desc[(int)g_prefs.field] ? HDF_SORTDOWN : HDF_SORTUP;
		Header_SetItem(header, i, &hdi);
	}
}

void apply_columns(void) {
	for (int i = 0; i < g_sort_btn_count; ++i) {
		DestroyWindow(g_sort_btns[i]);
		g_sort_btns[i] = NULL;
	}
	g_sort_btn_count = 0;

	int lv_cols = Header_GetItemCount(ListView_GetHeader(g_hwnd_list));
	for (int i = lv_cols - 1; i >= 0; --i) ListView_DeleteColumn(g_hwnd_list, i);

	if (!g_prefs.visible[(int)g_prefs.field]) g_prefs.field = SORT_FIELD_NAME;

	int btn_x = 0;
	int lv_col = 0;
	for (int i = 0; i < COL_COUNT; ++i) {
		if (!g_prefs.visible[i]) continue;
		g_sort_btns[g_sort_btn_count] = CreateWindow(L"BUTTON", COLUMNS[i].label,
			WS_CHILD | WS_VISIBLE | BS_RADIOBUTTON,
			btn_x, 0, COLUMNS[i].width, 1,
			g_hwnd_sort_group, (HMENU)(INT_PTR)(ID_SORT_BASE + i),
			GetModuleHandle(NULL), NULL);
		SetWindowSubclass(g_sort_btns[g_sort_btn_count], sort_btn_proc, g_sort_btn_count, 0);
		g_sort_btn_cols[g_sort_btn_count] = (column_id)i;
		btn_x += COLUMNS[i].width;
		g_sort_btn_count++;
		LVCOLUMN lvc = {0};
		lvc.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
		lvc.pszText = (wchar_t*)COLUMNS[i].header;
		lvc.cx = COLUMNS[i].width;
		lvc.iSubItem = lv_col;
		ListView_InsertColumn(g_hwnd_list, lv_col, &lvc);
		lv_col++;
	}
	SetWindowPos(g_hwnd_sort_group, NULL, 0, 0, btn_x, 1, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
	update_sort_ui();
	update_tab_stop();
	sortbar_apply_theme();
}

void sortbar_apply_theme(void) {
	theme_apply_button(g_hwnd_sort_group);
	for (int i = 0; i < g_sort_btn_count; ++i)
		theme_apply_button(g_sort_btns[i]);
}

HWND sortbar_create(HWND parent) {
	HWND group = CreateWindowEx(WS_EX_CONTROLPARENT, L"BUTTON", L"Sort by",
		WS_CHILD | WS_VISIBLE | BS_GROUPBOX,
		0, 0, 0, 1, parent, NULL, GetModuleHandle(NULL), NULL);
	SetWindowSubclass(group, sort_group_proc, 0, 0);
	return group;
}
