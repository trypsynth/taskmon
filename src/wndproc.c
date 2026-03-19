#include "wndproc.h"
#include "settings.h"
#include "tray.h"
#include "process.h"
#include <windowsx.h>
#include <shellapi.h>
#include <shlobj.h>
#include <commctrl.h>
#include <shlwapi.h>

#define ID_SORT_NAME 101
#define ID_SORT_PID 102
#define ID_SORT_CPU 103
#define ID_SORT_MEMORY 104
#define ID_LISTVIEW 105
#define ID_TRAY_RESTORE 201
#define ID_TRAY_EXIT 202
#define ID_CTX_OPEN_LOCATION 301
#define ID_CTX_END_TASK 302
#define WM_TRAYICON (WM_APP + 1)
#define WM_HIDE_TO_TRAY (WM_APP + 2)
#define ID_REFRESH_TIMER 1
#define ID_VIEW_REFRESH 401
#define ID_AUTOREFRESH_OFF 501
#define ID_AUTOREFRESH_5S 502
#define ID_AUTOREFRESH_10S 503
#define ID_AUTOREFRESH_30S 504
#define ID_AUTOREFRESH_1MIN 505

const wchar_t CLASS_NAME[] = L"TaskmonWndClass";
const wchar_t WINDOW_TITLE[] = L"Taskmon";
static const wchar_t* LABELS[SORT_COUNT] = { L"Name", L"PID", L"CPU", L"Memory" };
static const sort_field FIELDS[SORT_COUNT] = {SORT_FIELD_NAME, SORT_FIELD_PID, SORT_FIELD_CPU, SORT_FIELD_MEMORY};
static const int IDS[SORT_COUNT] = { ID_SORT_NAME, ID_SORT_PID, ID_SORT_CPU, ID_SORT_MEMORY };
static const int widths[SORT_COUNT] = { 120, 70, 70, 100 };

typedef struct {
	UINT id;
	UINT ms;
	const wchar_t* label;
} refresh_option;
static const refresh_option REFRESH_OPTIONS[] = {
	{ ID_AUTOREFRESH_OFF, 0, L"Off" },
	{ ID_AUTOREFRESH_5S, 5000, L"5 seconds" },
	{ ID_AUTOREFRESH_10S, 10000, L"10 seconds"},
	{ ID_AUTOREFRESH_30S, 30000, L"30 seconds"},
	{ ID_AUTOREFRESH_1MIN, 60000, L"1 minute" },
};
#define REFRESH_OPTION_COUNT (sizeof(REFRESH_OPTIONS) / sizeof(REFRESH_OPTIONS[0]))

static HWND g_hwnd = NULL;
static HWND g_hwnd_list = NULL;
static HWND g_sort_btns[SORT_COUNT] = {0};
static HWND g_last_focus = NULL;
static sort_prefs g_prefs;
static snapshot_entry g_snapshots[SNAPSHOT_CAPACITY] = {0};

static BOOL* cur_desc() {
	for (int i = 0; i < SORT_COUNT; ++i) if (FIELDS[i] == g_prefs.field) return &g_prefs.desc[i];
	return &g_prefs.desc[0];
}

static void update_tab_stop() {
	for (int i = 0; i < SORT_COUNT; ++i) {
		LONG_PTR style = GetWindowLongPtr(g_sort_btns[i], GWL_STYLE);
		style = (FIELDS[i] == g_prefs.field) ? (style | WS_TABSTOP) : (style & ~WS_TABSTOP);
		SetWindowLongPtr(g_sort_btns[i], GWL_STYLE, style);
	}
}

static void update_sort_ui() {
	for (int i = 0; i < SORT_COUNT; ++i) {
		BOOL active = (FIELDS[i] == g_prefs.field);
		wchar_t buf[64];
		if (active) wnsprintf(buf, 64, L"%s (%s)", LABELS[i], *cur_desc() ? L"descending" : L"ascending");
		else lstrcpy(buf, LABELS[i]);
		SetWindowText(g_sort_btns[i], buf);
		SendMessage(g_sort_btns[i], BM_SETCHECK, active ? BST_CHECKED : BST_UNCHECKED, 0);
	}
	HWND header = ListView_GetHeader(g_hwnd_list);
	for (int i = 0; i < SORT_COUNT; ++i) {
		HDITEM hdi = {0};
		hdi.mask = HDI_FORMAT;
		Header_GetItem(header, i, &hdi);
		hdi.fmt &= ~(HDF_SORTUP | HDF_SORTDOWN);
		if (FIELDS[i] == g_prefs.field) hdi.fmt |= *cur_desc() ? HDF_SORTDOWN : HDF_SORTUP;
		Header_SetItem(header, i, &hdi);
	}
}

static void populate_list(process_entry* entries, int count) {
	DWORD selected_pid = 0;
	int selected = ListView_GetNextItem(g_hwnd_list, -1, LVNI_SELECTED);
	if (selected != -1) {
		LVITEM lvi = {0};
		lvi.mask = LVIF_PARAM;
		lvi.iItem = selected;
		if (ListView_GetItem(g_hwnd_list, &lvi)) selected_pid = (DWORD)lvi.lParam;
	}
	DWORD top_pid = 0;
	int top_idx = ListView_GetTopIndex(g_hwnd_list);
	if (top_idx != -1 && ListView_GetItemCount(g_hwnd_list) > 0) {
		LVITEM lvi = {0};
		lvi.mask = LVIF_PARAM;
		lvi.iItem = top_idx;
		if (ListView_GetItem(g_hwnd_list, &lvi)) top_pid = (DWORD)lvi.lParam;
	}
	SendMessage(g_hwnd_list, WM_SETREDRAW, FALSE, 0);
	ListView_DeleteAllItems(g_hwnd_list);
	double total_cpu = 0;
	SIZE_T total_mem = 0;
	int new_selected_idx = -1;
	int new_top_idx = -1;
	for (int i = 0; i < count; i++) {
		process_entry* e = &entries[i];
		if (e->pid != 0) total_cpu += e->cpu_percent;
		total_mem += e->working_set;
		LVITEM lvi = {0};
		lvi.mask = LVIF_TEXT | LVIF_PARAM;
		lvi.iItem = i;
		lvi.pszText = e->name;
		lvi.lParam = (LPARAM)e->pid;
		ListView_InsertItem(g_hwnd_list, &lvi);
		if (e->pid == selected_pid) new_selected_idx = i;
		if (e->pid == top_pid) new_top_idx = i;
		wchar_t buf[32];
		wnsprintf(buf, 32, L"%u", e->pid);
		ListView_SetItemText(g_hwnd_list, i, 1, buf);
		int cpu_whole = (int)e->cpu_percent;
		int cpu_frac = (int)((e->cpu_percent - cpu_whole) * 100 + 0.5);
		if (cpu_frac >= 100) {
			cpu_whole++;
			cpu_frac = 0;
		}
		wnsprintf(buf, 32, L"%d.%02d", cpu_whole, cpu_frac);
		ListView_SetItemText(g_hwnd_list, i, 2, buf);
		wnsprintf(buf, 32, L"%u K", (UINT)(e->working_set / 1024));
		ListView_SetItemText(g_hwnd_list, i, 3, buf);
	}
	if (new_selected_idx != -1) {
		ListView_SetItemState(g_hwnd_list, new_selected_idx, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
	} else if (ListView_GetItemCount(g_hwnd_list) > 0) {
		ListView_SetItemState(g_hwnd_list, 0, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
	}
	if (new_top_idx != -1) {
		RECT rc;
		if (ListView_GetItemRect(g_hwnd_list, 0, &rc, LVIR_BOUNDS)) {
			int item_height = rc.bottom - rc.top;
			ListView_Scroll(g_hwnd_list, 0, new_top_idx * item_height);
		}
	}
	SendMessage(g_hwnd_list, WM_SETREDRAW, TRUE, 0);
	InvalidateRect(g_hwnd_list, NULL, FALSE);
	tray_update_tip(total_cpu, total_mem);
}

static void do_refresh() {
	int count = 0;
	process_entry* entries = snapshot_processes(g_snapshots, &count, g_prefs.field, *cur_desc());
	if (entries) {
		populate_list(entries, count);
		free_process_entries(entries);
	}
}

static BOOL open_item_location(const wchar_t* path) {
	wchar_t folder[MAX_PATH];
	lstrcpy(folder, path);
	PathRemoveFileSpec(folder);
	LPITEMIDLIST folder_pidl = ILCreateFromPath(folder);
	LPITEMIDLIST item_pidl = ILCreateFromPath(path);
	if (!folder_pidl || !item_pidl) {
		if (folder_pidl) ILFree(folder_pidl);
		if (item_pidl) ILFree(item_pidl);
		return FALSE;
	}
	LPCITEMIDLIST child = ILFindLastID(item_pidl);
	LPCITEMIDLIST children[] = { child };
	HRESULT hr = SHOpenFolderAndSelectItems(folder_pidl, 1, children, 0);
	ILFree(item_pidl);
	ILFree(folder_pidl);
	if (SUCCEEDED(hr)) return TRUE;
	return (INT_PTR)ShellExecute(NULL, L"open", folder, NULL, NULL, SW_SHOW) > 32;
}

static BOOL confirm_end_task(HWND hwnd, const wchar_t* name, DWORD pid) {
	wchar_t message[512];
	wnsprintf(message, 512, L"End \"%s\" (PID %u)?\n\nUnsaved data may be lost.", name[0] ? name : L"this process", pid);
	return MessageBox(hwnd, message, L"Confirm End Task", MB_ICONWARNING | MB_OKCANCEL | MB_DEFBUTTON2) == IDOK;
}

static LRESULT CALLBACK sort_btn_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data) {
	if (msg == WM_GETDLGCODE) {
		LRESULT r = DefSubclassProc(hwnd, msg, wp, lp) | DLGC_WANTARROWS;
		MSG* pmsg = (MSG*)lp;
		if (pmsg && ((pmsg->message == WM_KEYDOWN && pmsg->wParam == VK_RETURN) || (pmsg->message == WM_CHAR && pmsg->wParam == '\r'))) r |= DLGC_WANTMESSAGE;
		return r;
	}
	if (msg == WM_CHAR && wp == '\r') return 0;
	if (msg == WM_KEYDOWN) {
		if (wp == VK_ESCAPE) {
			PostMessage(GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0);
			return 0;
		}
		if (wp == VK_F5) {
			do_refresh();
			return 0;
		}
		if (wp == VK_RETURN) {
			PostMessage(GetParent(hwnd), WM_COMMAND, MAKEWPARAM(GetDlgCtrlID(hwnd), BN_CLICKED), (LPARAM)hwnd);
			return 0;
		}
		if (wp == VK_LEFT || wp == VK_RIGHT) {
			int idx = -1;
			for (int i = 0; i < SORT_COUNT; ++i) {
				if (g_sort_btns[i] == hwnd) {
					idx = i;
					break;
				}
			}
			if (idx >= 0) {
				int next = (wp == VK_RIGHT) ? idx + 1 : idx - 1;
				if (next < 0 || next >= SORT_COUNT) return 0;
				g_prefs.field = FIELDS[next];
				wchar_t buf[64];
				wnsprintf(buf, 64, L"%s (%s)", LABELS[next], *cur_desc() ? L"descending" : L"ascending");
				SetWindowText(g_sort_btns[next], buf);
				SendMessage(g_sort_btns[next], BM_SETCHECK, BST_CHECKED, 0);
				update_tab_stop();
				SetFocus(g_sort_btns[next]);
				update_sort_ui();
				do_refresh();
				settings_save(&g_prefs, LABELS, FIELDS);
				return 0;
			}
		}
		if (wp == VK_UP || wp == VK_DOWN) return 0;
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}

static LRESULT CALLBACK list_key_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data) {
	if (msg == WM_KEYDOWN) {
		if (wp == 'E' && (GetKeyState(VK_CONTROL) & 0x8000)) {
			PostMessage(GetParent(hwnd), WM_COMMAND, ID_CTX_END_TASK, 0);
			return 0;
		}
		if (wp == VK_ESCAPE) {
			PostMessage(GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0);
			return 0;
		}
		if (wp == VK_F5) {
			do_refresh();
			return 0;
		}
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}

static void create_menu_bar(HWND hwnd) {
	HMENU bar = CreateMenu();
	HMENU view = CreatePopupMenu();
	HMENU sub = CreatePopupMenu();
	for (int i = 0; i < REFRESH_OPTION_COUNT; ++i) AppendMenu(sub, MF_STRING, REFRESH_OPTIONS[i].id, REFRESH_OPTIONS[i].label);
	AppendMenu(view, MF_STRING, ID_VIEW_REFRESH, L"Refresh\tF5");
	AppendMenu(view, MF_SEPARATOR, 0, NULL);
	AppendMenu(view, MF_POPUP, (UINT_PTR)sub, L"Auto-refresh");
	AppendMenu(bar, MF_POPUP, (UINT_PTR)view, L"View");
	SetMenu(hwnd, bar);
}

static void set_refresh_interval(HWND hwnd, UINT ms) {
	BOOL found = FALSE;
	for (int i = 0; i < REFRESH_OPTION_COUNT; ++i) {
		if (REFRESH_OPTIONS[i].ms == ms) {
			found = TRUE;
			break;
		}
	}
	if (!found) ms = 0;
	g_prefs.refresh_ms = ms;
	KillTimer(hwnd, ID_REFRESH_TIMER);
	if (ms > 0) SetTimer(hwnd, ID_REFRESH_TIMER, ms, NULL);
	HMENU bar = GetMenu(hwnd);
	if (!bar) {
		settings_save(&g_prefs, LABELS, FIELDS);
		return;
	}
	HMENU view = GetSubMenu(bar, 0);
	if (!view) {
		settings_save(&g_prefs, LABELS, FIELDS);
		return;
	}
	HMENU sub = GetSubMenu(view, 2);
	if (!sub) {
		settings_save(&g_prefs, LABELS, FIELDS);
		return;
	}
	UINT first = REFRESH_OPTIONS[0].id;
	UINT last = REFRESH_OPTIONS[REFRESH_OPTION_COUNT - 1].id;
	for (int i = 0; i < REFRESH_OPTION_COUNT; ++i) {
		if (REFRESH_OPTIONS[i].ms == ms) {
			CheckMenuRadioItem(sub, first, last, REFRESH_OPTIONS[i].id, MF_BYCOMMAND);
			break;
		}
	}
	settings_save(&g_prefs, LABELS, FIELDS);
}

LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
	switch (msg) {
	case WM_ACTIVATE:
		if (LOWORD(wp) == WA_INACTIVE) g_last_focus = GetFocus();
		else SetFocus(g_last_focus ? g_last_focus : g_hwnd_list);
		return 0;
	case WM_CREATE: {
		g_hwnd = hwnd;
		INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_LISTVIEW_CLASSES };
		InitCommonControlsEx(&icc);
		CreateWindow(L"BUTTON", L"Sort by", WS_CHILD | WS_VISIBLE | BS_GROUPBOX, 0, 0, 360, 1, hwnd, NULL, GetModuleHandle(NULL), NULL);
		int btn_x = 0;
		for (int i = 0; i < SORT_COUNT; ++i) {
			g_sort_btns[i] = CreateWindow(L"BUTTON", LABELS[i], WS_CHILD | WS_VISIBLE | BS_RADIOBUTTON, btn_x, 0, widths[i], 1, hwnd, (HMENU)(INT_PTR)IDS[i], GetModuleHandle(NULL), NULL);
			SetWindowSubclass(g_sort_btns[i], sort_btn_proc, i, 0);
			btn_x += widths[i];
		}
		g_hwnd_list = CreateWindowEx(0, WC_LISTVIEWW, NULL, WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SHOWSELALWAYS, 0, 1, 760, 559, hwnd, (HMENU)(INT_PTR)ID_LISTVIEW, GetModuleHandle(NULL), NULL);
		SetWindowSubclass(g_hwnd_list, list_key_proc, 0, 0);
		ListView_SetExtendedListViewStyle(g_hwnd_list, LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES | LVS_EX_HEADERDRAGDROP);
		LVCOLUMN lvc = {0};
		lvc.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
		lvc.pszText = L"Name"; lvc.cx = 260; lvc.iSubItem = 0; ListView_InsertColumn(g_hwnd_list, 0, &lvc);
		lvc.pszText = L"PID"; lvc.cx = 80; lvc.iSubItem = 1; ListView_InsertColumn(g_hwnd_list, 1, &lvc);
		lvc.pszText = L"CPU Percent"; lvc.cx = 90; lvc.iSubItem = 2; ListView_InsertColumn(g_hwnd_list, 2, &lvc);
		lvc.pszText = L"Memory"; lvc.cx = 120; lvc.iSubItem = 3; ListView_InsertColumn(g_hwnd_list, 3, &lvc);
		settings_load(&g_prefs, LABELS, FIELDS);
		update_sort_ui();
		update_tab_stop();
		create_menu_bar(hwnd);
		tray_add(hwnd, WM_TRAYICON, WINDOW_TITLE);
		do_refresh();
		set_refresh_interval(hwnd, g_prefs.refresh_ms);
		SetFocus(g_hwnd_list);
		return 0;
	}
	case WM_HIDE_TO_TRAY:
		ShowWindow(hwnd, SW_HIDE);
		return 0;
	case WM_TRAYICON:
		if (lp == WM_LBUTTONUP) {
			tray_restore();
		} else if (lp == WM_RBUTTONUP) {
			HMENU menu = CreatePopupMenu();
			AppendMenu(menu, MF_STRING, ID_TRAY_RESTORE, L"Restore");
			AppendMenu(menu, MF_STRING, ID_TRAY_EXIT, L"Exit");
			POINT pt;
			GetCursorPos(&pt);
			SetForegroundWindow(hwnd);
			TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, NULL);
			PostMessage(hwnd, WM_NULL, 0, 0);
			DestroyMenu(menu);
		}
		return 0;
	case WM_COMMAND: {
		WORD id = LOWORD(wp);
		if (id == ID_TRAY_RESTORE) {
			tray_restore();
			return 0;
		}
		if (id == ID_TRAY_EXIT) {
			DestroyWindow(hwnd);
			return 0;
		}
		if (id == IDCANCEL) {
			PostMessage(hwnd, WM_HIDE_TO_TRAY, 0, 0);
			return 0;
		}
		if (id == ID_CTX_OPEN_LOCATION || id == ID_CTX_END_TASK) {
			int selected = ListView_GetNextItem(g_hwnd_list, -1, LVNI_SELECTED);
			if (selected != -1) {
				LVITEM lvi = {0};
				lvi.iItem = selected;
				lvi.mask = LVIF_PARAM;
				ListView_GetItem(g_hwnd_list, &lvi);
				wchar_t name[260] = {0};
				ListView_GetItemText(g_hwnd_list, selected, 0, name, 260);
				DWORD pid = (DWORD)lvi.lParam;
				if (id == ID_CTX_OPEN_LOCATION) {
					wchar_t path[MAX_PATH];
					get_process_path(pid, path, MAX_PATH);
					if (path[0]) open_item_location(path);
				} else if (id == ID_CTX_END_TASK) {
					if (confirm_end_task(hwnd, name, pid)) {
						terminate_process(pid);
						do_refresh();
					}
				}
			}
			return 0;
		}
		if (id == ID_VIEW_REFRESH) {
			do_refresh();
			return 0;
		}
		for (int i = 0; i < REFRESH_OPTION_COUNT; ++i) {
			if (id == REFRESH_OPTIONS[i].id) {
				set_refresh_interval(hwnd, REFRESH_OPTIONS[i].ms);
				return 0;
			}
		}
		if (HIWORD(wp) == BN_CLICKED) {
			for (int i = 0; i < SORT_COUNT; ++i) {
				if (IDS[i] == id) {
					if (FIELDS[i] == g_prefs.field) *cur_desc() = !*cur_desc();
					else g_prefs.field = FIELDS[i];
					update_sort_ui();
					update_tab_stop();
					do_refresh();
					settings_save(&g_prefs, LABELS, FIELDS);
					break;
				}
			}
		}
		return 0;
	}
	case WM_CONTEXTMENU: {
		if ((HWND)wp == g_hwnd_list) {
			int selected = ListView_GetNextItem(g_hwnd_list, -1, LVNI_SELECTED);
			if (selected != -1) {
				LVITEM lvi = {0};
				lvi.iItem = selected;
				lvi.mask = LVIF_PARAM;
				ListView_GetItem(g_hwnd_list, &lvi);
				DWORD pid = (DWORD)lvi.lParam;
				POINT pt;
				pt.x = GET_X_LPARAM(lp);
				pt.y = GET_Y_LPARAM(lp);
				if (pt.x == -1 && pt.y == -1) {
					RECT rc;
					ListView_GetItemRect(g_hwnd_list, selected, &rc, LVIR_BOUNDS);
					MapWindowPoints(g_hwnd_list, HWND_DESKTOP, (LPPOINT)&rc, 2);
					pt.x = rc.left + (rc.right - rc.left) / 2;
					pt.y = rc.top + (rc.bottom - rc.top) / 2;
				}
				HMENU menu = CreatePopupMenu();
				wchar_t path[MAX_PATH];
				get_process_path(pid, path, MAX_PATH);
				if (path[0]) AppendMenu(menu, MF_STRING, ID_CTX_OPEN_LOCATION, L"Open file location");
				AppendMenu(menu, MF_STRING, ID_CTX_END_TASK, L"End task\tCtrl+E");
				TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, NULL);
				DestroyMenu(menu);
			}
		}
		return 0;
	}
	case WM_NOTIFY: {
		NMHDR* hdr = (NMHDR*)lp;
		if (hdr->idFrom == (UINT_PTR)ID_LISTVIEW && hdr->code == LVN_COLUMNCLICK) {
			NMLISTVIEW* nmlv = (NMLISTVIEW*)lp;
			if (nmlv->iSubItem >= 0 && nmlv->iSubItem < SORT_COUNT) {
				if (FIELDS[nmlv->iSubItem] == g_prefs.field) *cur_desc() = !*cur_desc();
				else g_prefs.field = FIELDS[nmlv->iSubItem];
				update_sort_ui();
				update_tab_stop();
				do_refresh();
				settings_save(&g_prefs, LABELS, FIELDS);
			}
		}
		return DefWindowProc(hwnd, msg, wp, lp);
	}
	case WM_TIMER:
		if (wp == ID_REFRESH_TIMER) {
			do_refresh();
			return 0;
		}
		break;
	case WM_DESTROY:
		KillTimer(hwnd, ID_REFRESH_TIMER);
		tray_remove();
		PostQuitMessage(0);
		return 0;
	}
	return DefWindowProc(hwnd, msg, wp, lp);
}
