#include "wndproc.h"
#include "settings.h"
#include "tray.h"
#include "process.h"
#include "resource.h"
#include <windowsx.h>
#include <shellapi.h>
#include <shlobj.h>
#include <commctrl.h>
#include <shlwapi.h>

#define ID_SORT_BASE 110
#define ID_LISTVIEW 105
#define ID_TRAY_RESTORE 201
#define ID_TRAY_EXIT 202
#define ID_CTX_OPEN_LOCATION 301
#define ID_CTX_END_TASK 302
#define WM_TRAYICON (WM_APP + 1)
#define WM_HIDE_TO_TRAY (WM_APP + 2)
#define ID_REFRESH_TIMER 1

const wchar_t CLASS_NAME[] = L"TaskmonWndClass";
const wchar_t WINDOW_TITLE[] = L"Taskmon";

static HWND g_hwnd = NULL;
static HWND g_hwnd_list = NULL;
static HWND g_hwnd_sort_group = NULL;
static HWND g_sort_btns[COL_COUNT] = {0};
static column_id g_sort_btn_cols[COL_COUNT] = {0};
static int g_sort_btn_count = 0;
static HWND g_last_focus = NULL;
static sort_prefs g_prefs;
static snapshot_entry g_snapshots[SNAPSHOT_CAPACITY] = {0};

static BOOL* cur_desc() {
	return &g_prefs.desc[(int)g_prefs.field];
}

static void update_tab_stop() {
	for (int i = 0; i < g_sort_btn_count; ++i) {
		LONG_PTR style = GetWindowLongPtr(g_sort_btns[i], GWL_STYLE);
		style = (COLUMNS[g_sort_btn_cols[i]].field == g_prefs.field) ? (style | WS_TABSTOP) : (style & ~WS_TABSTOP);
		SetWindowLongPtr(g_sort_btns[i], GWL_STYLE, style);
	}
}

static void update_sort_ui() {
	for (int i = 0; i < g_sort_btn_count; ++i) {
		column_id cid = g_sort_btn_cols[i];
		BOOL active = (COLUMNS[cid].field == g_prefs.field);
		wchar_t buf[64];
		if (active) wnsprintf(buf, 64, L"%s (%s)", COLUMNS[cid].label, *cur_desc() ? L"descending" : L"ascending");
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
		if (COLUMNS[cid].field == g_prefs.field) hdi.fmt |= *cur_desc() ? HDF_SORTDOWN : HDF_SORTUP;
		Header_SetItem(header, i, &hdi);
	}
}

static void format_column(const process_entry* e, column_id cid, wchar_t* buf, int len) {
	switch (cid) {
	case COL_PID:
		wnsprintf(buf, len, L"%u", e->pid);
		break;
	case COL_CPU: {
		int whole = (int)e->cpu_percent;
		int frac = (int)((e->cpu_percent - whole) * 100 + 0.5);
		if (frac >= 100) { whole++; frac = 0; }
		wnsprintf(buf, len, L"%d.%02d", whole, frac);
		break;
	}
	case COL_MEMORY:
		wnsprintf(buf, len, L"%u K", (UINT)(e->working_set / 1024));
		break;
	case COL_THREADS:
		wnsprintf(buf, len, L"%u", e->threads);
		break;
	case COL_HANDLES:
		wnsprintf(buf, len, L"%u", e->handles);
		break;
	default:
		buf[0] = L'\0';
		break;
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
	int new_selected_idx = -1;
	int new_top_idx = -1;
	for (int i = 0; i < count; i++) {
		process_entry* e = &entries[i];
		if (e->pid != 0) total_cpu += e->cpu_percent;
		LVITEM lvi = {0};
		lvi.mask = LVIF_TEXT | LVIF_PARAM;
		lvi.iItem = i;
		lvi.pszText = e->name;
		lvi.lParam = (LPARAM)e->pid;
		ListView_InsertItem(g_hwnd_list, &lvi);
		if (e->pid == selected_pid) new_selected_idx = i;
		if (e->pid == top_pid) new_top_idx = i;
		wchar_t buf[64];
		for (int col = 1; col < g_sort_btn_count; ++col) {
			format_column(e, g_sort_btn_cols[col], buf, 64);
			ListView_SetItemText(g_hwnd_list, i, col, buf);
		}
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
	tray_update_tip(total_cpu);
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

static void set_refresh_interval(HWND hwnd, UINT ms) {
	BOOL found = FALSE;
	for (int i = 0; i < REFRESH_OPTION_COUNT; ++i) {
		if (REFRESH_MS[i] == ms) { found = TRUE; break; }
	}
	if (!found) ms = 0;
	g_prefs.refresh_ms = ms;
	KillTimer(hwnd, ID_REFRESH_TIMER);
	if (ms > 0) SetTimer(hwnd, ID_REFRESH_TIMER, ms, NULL);
	settings_save(&g_prefs);
}

static BOOL confirm_end_task(HWND hwnd, const wchar_t* name, DWORD pid) {
	if (g_prefs.skip_kill_confirm) return TRUE;
	wchar_t message[512];
	wnsprintf(message, 512, L"Do you want to end process \"%s\" (PID %u)?\n\nUnsaved data may be lost.", name[0] ? name : L"this process", pid);
	return MessageBox(hwnd, message, L"Confirm", MB_ICONINFORMATION | MB_YESNO | MB_DEFBUTTON2) == IDYES;
}

static LRESULT CALLBACK sort_group_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data) {
	UNREFERENCED_PARAMETER(id); UNREFERENCED_PARAMETER(data);
	if (msg == WM_COMMAND) return SendMessage(g_hwnd, msg, wp, lp);
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
				wnsprintf(buf, 64, L"%s (%s)", COLUMNS[cid].label, *cur_desc() ? L"descending" : L"ascending");
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

static LRESULT CALLBACK list_key_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data) {
	UNREFERENCED_PARAMETER(id); UNREFERENCED_PARAMETER(data);
	if (msg == WM_KEYDOWN) {
		if (wp == 'E' && (GetKeyState(VK_CONTROL) & 0x8000)) {
			PostMessage(GetParent(hwnd), WM_COMMAND, ID_CTX_END_TASK, 0);
			return 0;
		}
		if (wp == VK_ESCAPE) {
			PostMessage(GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0);
			return 0;
		}
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}

static void apply_columns() {
	// Destroy existing sort buttons
	for (int i = 0; i < g_sort_btn_count; ++i) {
		DestroyWindow(g_sort_btns[i]);
		g_sort_btns[i] = NULL;
	}
	g_sort_btn_count = 0;

	// Remove list view columns right-to-left
	int lv_cols = Header_GetItemCount(ListView_GetHeader(g_hwnd_list));
	for (int i = lv_cols - 1; i >= 0; --i) ListView_DeleteColumn(g_hwnd_list, i);

	// Fall back to Name sort if the current sort column is now hidden
	if (!g_prefs.visible[(int)g_prefs.field]) g_prefs.field = SORT_FIELD_NAME;

	// Create buttons and columns for each visible column
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
	// Resize group box to fit the buttons
	SetWindowPos(g_hwnd_sort_group, NULL, 0, 0, btn_x, 1, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
	update_sort_ui();
	update_tab_stop();
}

static void create_menu_bar(HWND hwnd) {
	HMENU bar = CreateMenu();
	HMENU view = CreatePopupMenu();
	AppendMenu(view, MF_STRING, ID_VIEW_REFRESH, L"Refresh\tF5");
	AppendMenu(view, MF_SEPARATOR, 0, NULL);
	AppendMenu(view, MF_STRING, ID_VIEW_SETTINGS, L"Settings...\tCtrl+,");
	AppendMenu(bar, MF_POPUP, (UINT_PTR)view, L"View");
	SetMenu(hwnd, bar);
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
		g_hwnd_sort_group = CreateWindowEx(WS_EX_CONTROLPARENT, L"BUTTON", L"Sort by",
			WS_CHILD | WS_VISIBLE | BS_GROUPBOX,
			0, 0, 0, 1, hwnd, NULL, GetModuleHandle(NULL), NULL);
		SetWindowSubclass(g_hwnd_sort_group, sort_group_proc, 0, 0);
		// Hidden label — GW_HWNDPREV of the list view points here, so MSAA/UIA
		// use "Processes" as the list's accessible name instead of the group box.
		CreateWindow(L"STATIC", L"Processes", WS_CHILD | SS_LEFT,
			0, 0, 0, 0, hwnd, NULL, GetModuleHandle(NULL), NULL);
		g_hwnd_list = CreateWindowEx(0, WC_LISTVIEWW, L"Processes", WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SHOWSELALWAYS, 0, 1, 760, 559, hwnd, (HMENU)(INT_PTR)ID_LISTVIEW, GetModuleHandle(NULL), NULL);
		SetWindowSubclass(g_hwnd_list, list_key_proc, 0, 0);
		ListView_SetExtendedListViewStyle(g_hwnd_list, LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES | LVS_EX_HEADERDRAGDROP);
		settings_load(&g_prefs);
		apply_columns();
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
						// If the process is gone, select the nearest item to where it was
						int count = ListView_GetItemCount(g_hwnd_list);
						BOOL pid_still_present = FALSE;
						for (int i = 0; i < count && !pid_still_present; i++) {
							LVITEM lvi2 = {0};
							lvi2.mask = LVIF_PARAM;
							lvi2.iItem = i;
							ListView_GetItem(g_hwnd_list, &lvi2);
							if ((DWORD)lvi2.lParam == pid) pid_still_present = TRUE;
						}
						if (!pid_still_present && count > 0) {
							int new_sel = selected < count ? selected : count - 1;
							ListView_SetItemState(g_hwnd_list, new_sel, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
							ListView_EnsureVisible(g_hwnd_list, new_sel, FALSE);
						}
					}
				}
			}
			return 0;
		}
		if (id == ID_VIEW_REFRESH) {
			do_refresh();
			return 0;
		}
		if (id == ID_VIEW_SETTINGS) {
			UINT new_ms;
			BOOL new_visible[COL_COUNT];
			BOOL new_skip_confirm;
			if (open_settings(hwnd, g_prefs.refresh_ms, g_prefs.visible, g_prefs.skip_kill_confirm, &new_ms, new_visible, &new_skip_confirm)) {
				BOOL cols_changed = FALSE;
				for (int i = 0; i < COL_COUNT; ++i)
					if (new_visible[i] != g_prefs.visible[i]) { cols_changed = TRUE; break; }
				for (int i = 0; i < COL_COUNT; ++i) g_prefs.visible[i] = new_visible[i];
				g_prefs.skip_kill_confirm = new_skip_confirm;
				if (new_ms != g_prefs.refresh_ms) set_refresh_interval(hwnd, new_ms);
				if (cols_changed) { apply_columns(); do_refresh(); }
				settings_save(&g_prefs);
			}
			return 0;
		}
		if (HIWORD(wp) == BN_CLICKED) {
			for (int i = 0; i < g_sort_btn_count; ++i) {
				if ((ID_SORT_BASE + (int)g_sort_btn_cols[i]) == id) {
					column_id cid = g_sort_btn_cols[i];
					if (COLUMNS[cid].field == g_prefs.field) *cur_desc() = !*cur_desc();
					else g_prefs.field = COLUMNS[cid].field;
					update_sort_ui();
					update_tab_stop();
					do_refresh();
					settings_save(&g_prefs);
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
			int col = nmlv->iSubItem;
			if (col >= 0 && col < g_sort_btn_count) {
				column_id cid = g_sort_btn_cols[col];
				if (COLUMNS[cid].field == g_prefs.field) *cur_desc() = !*cur_desc();
				else g_prefs.field = COLUMNS[cid].field;
				update_sort_ui();
				update_tab_stop();
				do_refresh();
				settings_save(&g_prefs);
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
