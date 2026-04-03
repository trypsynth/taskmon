#include "wndproc.h"
#include "settings.h"
#include "tray.h"
#include "process.h"
#include "resource.h"
#include "listview.h"
#include "sortbar.h"
#include "theme.h"
#include <windowsx.h>
#include <shellapi.h>
#include <shlobj.h>
#include <commctrl.h>
#include <shlwapi.h>

#define ID_LISTVIEW 105
#define ID_TRAY_RESTORE 201
#define ID_TRAY_EXIT 202
#define ID_CTX_OPEN_LOCATION   301
#define ID_CTX_SUSPEND         303
#define ID_CTX_RESUME          304
#define ID_CTX_PRIORITY_BASE   310  // +0=Idle +1=BelowNormal +2=Normal +3=AboveNormal +4=High +5=Realtime

static const struct { DWORD cls; const wchar_t* label; } PRIORITY_CLASSES[] = {
	{ IDLE_PRIORITY_CLASS,          L"Idle"         },
	{ BELOW_NORMAL_PRIORITY_CLASS,  L"Below Normal" },
	{ NORMAL_PRIORITY_CLASS,        L"Normal"       },
	{ ABOVE_NORMAL_PRIORITY_CLASS,  L"Above Normal" },
	{ HIGH_PRIORITY_CLASS,          L"High"         },
	{ REALTIME_PRIORITY_CLASS,      L"Realtime"     },
};
#define PRIORITY_CLASS_COUNT 6
#define WM_TRAYICON (WM_APP + 1)
#define ID_REFRESH_TIMER 1
#define ID_PRIME_TIMER   2
#define ID_HOTKEY_TOGGLE 1

const wchar_t CLASS_NAME[] = L"TaskmonWndClass";
const wchar_t WINDOW_TITLE[] = L"Taskmon";

HWND g_hwnd = NULL;
HWND g_hwnd_list = NULL;
HWND g_hwnd_sort_group = NULL;
HWND g_hwnd_status = NULL;
HWND g_sort_btns[COL_COUNT] = {0};
column_id g_sort_btn_cols[COL_COUNT] = {0};
int g_sort_btn_count = 0;
static HWND g_last_focus = NULL;
sort_prefs g_prefs;
snapshot_entry g_snapshots[SNAPSHOT_CAPACITY] = {0};

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
	wnsprintf(message, 512, L"End \"%s\" (PID %u)?\n\nUnsaved data may be lost.", name[0] ? name : L"this process", pid);
	return MessageBox(hwnd, message, L"Confirm End Task", MB_ICONQUESTION | MB_YESNO | MB_DEFBUTTON2) == IDYES;
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

static void create_menu_bar(HWND hwnd) {
	HMENU bar = CreateMenu();
	HMENU view = CreatePopupMenu();
	AppendMenu(view, MF_STRING, ID_VIEW_REFRESH, L"Refresh\tF5");
	AppendMenu(view, MF_SEPARATOR, 0, NULL);
	AppendMenu(view, MF_STRING | (g_prefs.always_on_top ? MF_CHECKED : 0), ID_VIEW_ALWAYS_ON_TOP, L"Always on Top");
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
		RegisterHotKey(hwnd, ID_HOTKEY_TOGGLE, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, VK_OEM_3);
		INITCOMMONCONTROLSEX icc = { sizeof(icc), ICC_LISTVIEW_CLASSES | ICC_BAR_CLASSES };
		InitCommonControlsEx(&icc);
		g_hwnd_sort_group = sortbar_create(hwnd);
		// Hidden label — GW_HWNDPREV of the list view points here, so MSAA/UIA
		// use "Processes" as the list's accessible name instead of the group box.
		CreateWindow(L"STATIC", L"Processes", WS_CHILD | SS_LEFT,
			0, 0, 0, 0, hwnd, NULL, GetModuleHandle(NULL), NULL);
		g_hwnd_list = CreateWindowEx(0, WC_LISTVIEWW, L"Processes", WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SHOWSELALWAYS, 0, 1, 760, 537, hwnd, (HMENU)(INT_PTR)ID_LISTVIEW, GetModuleHandle(NULL), NULL);
		SetWindowSubclass(g_hwnd_list, list_key_proc, 0, 0);
		ListView_SetExtendedListViewStyle(g_hwnd_list, LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES | LVS_EX_HEADERDRAGDROP);
		g_hwnd_status = CreateWindowEx(0, STATUSCLASSNAME, NULL, WS_CHILD | WS_VISIBLE, 0, 0, 0, 0, hwnd, NULL, GetModuleHandle(NULL), NULL);
		settings_load(&g_prefs);
		theme_update();
		apply_columns();
		theme_apply_titlebar(hwnd);
		theme_apply_listview(g_hwnd_list);
		SetWindowTheme(g_hwnd_status, theme_is_dark() ? L"DarkMode_Explorer" : L"Explorer", NULL);
		create_menu_bar(hwnd);
		tray_add(hwnd, WM_TRAYICON, WINDOW_TITLE);
		if (g_prefs.always_on_top)
			SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
		if (g_prefs.window_width > 0) {
			POINT pt = { g_prefs.window_left + 50, g_prefs.window_top + 50 };
			if (MonitorFromPoint(pt, MONITOR_DEFAULTTONULL))
				SetWindowPos(hwnd, NULL, g_prefs.window_left, g_prefs.window_top,
					g_prefs.window_width, g_prefs.window_height, SWP_NOZORDER | SWP_NOACTIVATE);
		}
		// Prime the snapshot table so the first real refresh has deltas to work from.
		// Discard results — the list stays empty until ID_PRIME_TIMER fires with accurate CPU.
		{
			int count = 0;
			process_entry* primed = snapshot_processes(g_snapshots, &count, g_prefs.field, g_prefs.desc[(int)g_prefs.field]);
			if (primed) free_process_entries(primed);
		}
		SetTimer(hwnd, ID_PRIME_TIMER, 250, NULL);
		set_refresh_interval(hwnd, g_prefs.refresh_ms);
		SetFocus(g_hwnd_list);
		return 0;
	}
	case WM_SIZE: {
		if (g_hwnd_list && g_hwnd_status) {
			int w = LOWORD(lp), h = HIWORD(lp);
			SendMessage(g_hwnd_status, WM_SIZE, wp, lp);
			RECT sr;
			GetClientRect(g_hwnd_status, &sr);
			SetWindowPos(g_hwnd_list, NULL, 0, 1, w, h - 1 - (sr.bottom - sr.top), SWP_NOZORDER | SWP_NOACTIVATE);
		}
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
		if (id == ID_CTX_SUSPEND || id == ID_CTX_RESUME) {
			int selected = ListView_GetNextItem(g_hwnd_list, -1, LVNI_SELECTED);
			if (selected != -1) {
				LVITEM lvi = {0};
				lvi.iItem = selected;
				lvi.mask = LVIF_PARAM;
				ListView_GetItem(g_hwnd_list, &lvi);
				if (id == ID_CTX_SUSPEND) suspend_process((DWORD)lvi.lParam);
				else                       resume_process((DWORD)lvi.lParam);
				do_refresh();
			}
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
		if (id >= ID_CTX_PRIORITY_BASE && id < ID_CTX_PRIORITY_BASE + PRIORITY_CLASS_COUNT) {
			int selected = ListView_GetNextItem(g_hwnd_list, -1, LVNI_SELECTED);
			if (selected != -1) {
				LVITEM lvi = {0};
				lvi.iItem = selected;
				lvi.mask = LVIF_PARAM;
				ListView_GetItem(g_hwnd_list, &lvi);
				set_process_priority((DWORD)lvi.lParam, PRIORITY_CLASSES[id - ID_CTX_PRIORITY_BASE].cls);
				do_refresh();
			}
			return 0;
		}
		if (id == ID_VIEW_ALWAYS_ON_TOP) {
			g_prefs.always_on_top = !g_prefs.always_on_top;
			HMENU view = GetSubMenu(GetMenu(hwnd), 0);
			CheckMenuItem(view, ID_VIEW_ALWAYS_ON_TOP, g_prefs.always_on_top ? MF_CHECKED : MF_UNCHECKED);
			SetWindowPos(hwnd, g_prefs.always_on_top ? HWND_TOPMOST : HWND_NOTOPMOST,
				0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
			settings_save(&g_prefs);
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
					if (COLUMNS[cid].field == g_prefs.field) g_prefs.desc[(int)g_prefs.field] = !g_prefs.desc[(int)g_prefs.field];
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
				if (is_process_suspended(pid))
					AppendMenu(menu, MF_STRING, ID_CTX_RESUME,  L"Resume");
				else
					AppendMenu(menu, MF_STRING, ID_CTX_SUSPEND, L"Suspend");
				AppendMenu(menu, MF_STRING, ID_CTX_END_TASK, L"End task\tDelete");
				HMENU pri_menu = CreatePopupMenu();
				DWORD cur_cls = 0;
				HANDLE ph = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
				if (ph) { cur_cls = GetPriorityClass(ph); CloseHandle(ph); }
				for (int i = 0; i < PRIORITY_CLASS_COUNT; ++i) {
					UINT flags = MF_STRING | (PRIORITY_CLASSES[i].cls == cur_cls ? MF_CHECKED : 0);
					AppendMenu(pri_menu, flags, ID_CTX_PRIORITY_BASE + i, PRIORITY_CLASSES[i].label);
				}
				AppendMenu(menu, MF_POPUP, (UINT_PTR)pri_menu, L"Priority");
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
				if (COLUMNS[cid].field == g_prefs.field) g_prefs.desc[(int)g_prefs.field] = !g_prefs.desc[(int)g_prefs.field];
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
		if (wp == ID_PRIME_TIMER) {
			KillTimer(hwnd, ID_PRIME_TIMER);
			do_refresh();
			return 0;
		}
		if (wp == ID_REFRESH_TIMER) {
			do_refresh();
			return 0;
		}
		break;
	case WM_HOTKEY:
		if (wp == ID_HOTKEY_TOGGLE) {
			if (!IsWindowVisible(hwnd)) {
				tray_restore();
			} else if (GetForegroundWindow() != hwnd) {
				SetForegroundWindow(hwnd);
			} else {
				PostMessage(hwnd, WM_HIDE_TO_TRAY, 0, 0);
			}
		}
		return 0;
	case WM_SETTINGCHANGE:
		if (lp && lstrcmp((LPCWSTR)lp, L"ImmersiveColorSet") == 0) {
			theme_update();
			theme_apply_titlebar(hwnd);
			theme_apply_listview(g_hwnd_list);
			SetWindowTheme(g_hwnd_status, theme_is_dark() ? L"DarkMode_Explorer" : L"Explorer", NULL);
			sortbar_apply_theme();
			RedrawWindow(hwnd, NULL, NULL, RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN);
		}
		return 0;
	case WM_ERASEBKGND: {
		HBRUSH br = theme_bg_brush();
		if (br) {
			RECT rc;
			GetClientRect(hwnd, &rc);
			FillRect((HDC)wp, &rc, br);
			return 1;
		}
		break;
	}
	case WM_CTLCOLORSTATIC:
	case WM_CTLCOLORBTN: {
		HBRUSH br = theme_ctl_color((HDC)wp);
		if (br) return (LRESULT)br;
		break;
	}
	case WM_DESTROY: {
		WINDOWPLACEMENT wpl = { sizeof(wpl) };
		GetWindowPlacement(hwnd, &wpl);
		g_prefs.window_left   = wpl.rcNormalPosition.left;
		g_prefs.window_top    = wpl.rcNormalPosition.top;
		g_prefs.window_width  = wpl.rcNormalPosition.right  - wpl.rcNormalPosition.left;
		g_prefs.window_height = wpl.rcNormalPosition.bottom - wpl.rcNormalPosition.top;
		settings_save(&g_prefs);
		UnregisterHotKey(hwnd, ID_HOTKEY_TOGGLE);
		KillTimer(hwnd, ID_REFRESH_TIMER);
		tray_remove();
		PostQuitMessage(0);
		return 0;
	}
	}
	return DefWindowProc(hwnd, msg, wp, lp);
}
