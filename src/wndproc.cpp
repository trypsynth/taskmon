#include "wndproc.hpp"
#include "settings.hpp"
#include "tray.hpp"
#include "process.hpp"
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <commctrl.h>
#include <string>
#include <unordered_map>

#define ID_SORT_NAME    101
#define ID_SORT_PID     102
#define ID_SORT_CPU     103
#define ID_SORT_MEMORY  104
#define ID_LISTVIEW     105
#define ID_TRAY_RESTORE 201
#define ID_TRAY_EXIT    202
#define ID_CTX_OPEN_LOCATION 301
#define ID_CTX_END_TASK      302
#define WM_TRAYICON     (WM_APP + 1)
#define WM_HIDE_TO_TRAY (WM_APP + 2)

static const wchar_t*  k_labels[k_sort_count] = { L"Name", L"PID", L"CPU", L"Memory" };
static const sort_field k_fields[k_sort_count] = { sort_field::name, sort_field::pid, sort_field::cpu, sort_field::memory };
static const int        k_ids[k_sort_count]    = { ID_SORT_NAME, ID_SORT_PID, ID_SORT_CPU, ID_SORT_MEMORY };
static const int        k_widths[k_sort_count] = { 120, 70, 70, 100 };

static HWND      g_hwnd      = nullptr;
static HWND      g_hwnd_list = nullptr;
static HWND      g_sort_btns[k_sort_count] = {};
static HWND      g_last_focus = nullptr;
static sort_prefs g_prefs;
static std::unordered_map<DWORD, cpu_snapshot> g_snapshots;

// Returns a reference to the desc flag for whichever field is currently active.
static bool& cur_desc() {
	for (int i = 0; i < k_sort_count; ++i) if (k_fields[i] == g_prefs.field) return g_prefs.desc[i];
	return g_prefs.desc[0];
}

static void update_tab_stop() {
	for (int i = 0; i < k_sort_count; ++i) {
		LONG_PTR style = GetWindowLongPtr(g_sort_btns[i], GWL_STYLE);
		style = (k_fields[i] == g_prefs.field) ? (style | WS_TABSTOP) : (style & ~WS_TABSTOP);
		SetWindowLongPtr(g_sort_btns[i], GWL_STYLE, style);
	}
}

static void update_sort_ui() {
	for (int i = 0; i < k_sort_count; ++i) {
		bool active = (k_fields[i] == g_prefs.field);
		wchar_t buf[64];
		if (active) swprintf_s(buf, L"%s (%s)", k_labels[i], cur_desc() ? L"descending" : L"ascending");
		else        wcscpy_s(buf, k_labels[i]);
		SetWindowText(g_sort_btns[i], buf);
		SendMessage(g_sort_btns[i], BM_SETCHECK, active ? BST_CHECKED : BST_UNCHECKED, 0);
	}
	HWND header = ListView_GetHeader(g_hwnd_list);
	for (int i = 0; i < k_sort_count; ++i) {
		HDITEM hdi{};
		hdi.mask = HDI_FORMAT;
		Header_GetItem(header, i, &hdi);
		hdi.fmt &= ~(HDF_SORTUP | HDF_SORTDOWN);
		if (k_fields[i] == g_prefs.field) hdi.fmt |= cur_desc() ? HDF_SORTDOWN : HDF_SORTUP;
		Header_SetItem(header, i, &hdi);
	}
}

static void do_refresh() {
	auto entries = snapshot_processes(g_snapshots, g_prefs.field, cur_desc());
	SendMessage(g_hwnd_list, WM_SETREDRAW, FALSE, 0);
	ListView_DeleteAllItems(g_hwnd_list);
	double total_cpu = 0;
	SIZE_T total_mem = 0;
	int i = 0;
	for (auto& e : entries) {
		total_cpu += e.cpu_percent;
		total_mem += e.working_set;
		LVITEM lvi{};
		lvi.mask    = LVIF_TEXT | LVIF_PARAM;
		lvi.iItem   = i;
		lvi.pszText = e.name.data();
		lvi.lParam  = e.pid;
		ListView_InsertItem(g_hwnd_list, &lvi);
		auto pid_str = std::to_wstring(e.pid);
		ListView_SetItemText(g_hwnd_list, i, 1, pid_str.data());
		wchar_t cpu_buf[16];
		swprintf_s(cpu_buf, L"%.2f", e.cpu_percent);
		ListView_SetItemText(g_hwnd_list, i, 2, cpu_buf);
		wchar_t mem_buf[32];
		swprintf_s(mem_buf, L"%zu K", e.working_set / 1024);
		ListView_SetItemText(g_hwnd_list, i, 3, mem_buf);
		++i;
	}
	if (ListView_GetItemCount(g_hwnd_list) > 0)
		ListView_SetItemState(g_hwnd_list, 0, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
	SendMessage(g_hwnd_list, WM_SETREDRAW, TRUE, 0);
	InvalidateRect(g_hwnd_list, nullptr, FALSE);
	tray_update_tip(total_cpu, total_mem);
}

// Arrow keys immediately switch the active sort field; Space/Enter fall through to BN_CLICKED.
static LRESULT CALLBACK sort_btn_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR, DWORD_PTR) {
	if (msg == WM_KEYDOWN) {
		if (wp == VK_ESCAPE) { PostMessage(GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0); return 0; }
		if (wp == VK_LEFT || wp == VK_RIGHT) {
			int idx = -1;
			for (int i = 0; i < k_sort_count; ++i) if (g_sort_btns[i] == hwnd) { idx = i; break; }
			if (idx >= 0) {
				int next = (wp == VK_RIGHT) ? (idx + 1) % k_sort_count : (idx + k_sort_count - 1) % k_sort_count;
				g_prefs.field = k_fields[next];
				update_sort_ui();
				update_tab_stop();
				do_refresh();
				settings_save(g_prefs, k_labels, k_fields);
				SetFocus(g_sort_btns[next]);
				return 0;
			}
		}
		if (wp == VK_UP || wp == VK_DOWN) return 0; // swallow — don't let focus escape to the list
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}

static LRESULT CALLBACK list_key_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR, DWORD_PTR) {
	if (msg == WM_KEYDOWN) {
		if (wp == 'E' && (GetKeyState(VK_CONTROL) & 0x8000)) {
			PostMessage(GetParent(hwnd), WM_COMMAND, ID_CTX_END_TASK, 0);
			return 0;
		}
		if (wp == VK_ESCAPE) { PostMessage(GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0); return 0; }
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}

LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
	switch (msg) {
	case WM_ACTIVATE:
		if (LOWORD(wp) == WA_INACTIVE) g_last_focus = GetFocus();
		else SetFocus(g_last_focus ? g_last_focus : g_hwnd_list);
		return 0;

	case WM_CREATE: {
		g_hwnd = hwnd;
		INITCOMMONCONTROLSEX icc{ sizeof(icc), ICC_LISTVIEW_CLASSES };
		InitCommonControlsEx(&icc);
		// Invisible groupbox gives screen readers the "Sort by" group label.
		CreateWindow(L"BUTTON", L"Sort by", WS_CHILD | WS_VISIBLE | BS_GROUPBOX, 0, 0, 360, 1, hwnd, nullptr, GetModuleHandle(nullptr), nullptr);
		int btn_x = 0;
		for (int i = 0; i < k_sort_count; ++i) {
			g_sort_btns[i] = CreateWindow(L"BUTTON", k_labels[i], WS_CHILD | WS_VISIBLE | BS_RADIOBUTTON, btn_x, 0, k_widths[i], 1, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(k_ids[i])), GetModuleHandle(nullptr), nullptr);
			SetWindowSubclass(g_sort_btns[i], sort_btn_proc, i, 0);
			btn_x += k_widths[i];
		}
		g_hwnd_list = CreateWindowEx(0, WC_LISTVIEW, nullptr, WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SHOWSELALWAYS, 0, 1, 760, 559, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(ID_LISTVIEW)), GetModuleHandle(nullptr), nullptr);
		SetWindowSubclass(g_hwnd_list, list_key_proc, 0, 0);
		ListView_SetExtendedListViewStyle(g_hwnd_list, LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES | LVS_EX_HEADERDRAGDROP);
		auto add_col = [&](int idx, const wchar_t* text, int width) {
			LVCOLUMN lvc{ LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM, 0, width, const_cast<LPWSTR>(text), 0, idx };
			ListView_InsertColumn(g_hwnd_list, idx, &lvc);
		};
		add_col(0, L"Name",        260);
		add_col(1, L"PID",          80);
		add_col(2, L"CPU Percent",  90);
		add_col(3, L"Memory",      120);
		g_prefs = settings_load(k_labels, k_fields);
		update_sort_ui();
		update_tab_stop();
		tray_add(hwnd, WM_TRAYICON, k_window_title);
		do_refresh();
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
			AppendMenu(menu, MF_STRING, ID_TRAY_EXIT,    L"Exit");
			POINT pt;
			GetCursorPos(&pt);
			SetForegroundWindow(hwnd);
			TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, nullptr);
			PostMessage(hwnd, WM_NULL, 0, 0);
			DestroyMenu(menu);
		}
		return 0;

	case WM_COMMAND: {
		WORD id = LOWORD(wp);
		if (id == ID_TRAY_RESTORE) { tray_restore(); return 0; }
		if (id == ID_TRAY_EXIT)    { DestroyWindow(hwnd); return 0; }
		if (id == IDCANCEL)        { PostMessage(hwnd, WM_HIDE_TO_TRAY, 0, 0); return 0; }
		if (id == ID_CTX_OPEN_LOCATION || id == ID_CTX_END_TASK) {
			int selected = ListView_GetNextItem(g_hwnd_list, -1, LVNI_SELECTED);
			if (selected != -1) {
				LVITEM lvi{};
				lvi.iItem = selected;
				lvi.mask = LVIF_PARAM;
				ListView_GetItem(g_hwnd_list, &lvi);
				DWORD pid = static_cast<DWORD>(lvi.lParam);
				if (id == ID_CTX_OPEN_LOCATION) {
					std::wstring path = get_process_path(pid);
					if (!path.empty()) {
						std::wstring args = L"/select,\"" + path + L"\"";
						ShellExecute(nullptr, L"open", L"explorer.exe", args.c_str(), nullptr, SW_SHOW);
					}
				} else if (id == ID_CTX_END_TASK) {
					terminate_process(pid);
					do_refresh();
				}
			}
			return 0;
		}
		if (HIWORD(wp) == BN_CLICKED) {
			for (int i = 0; i < k_sort_count; ++i) {
				if (k_ids[i] == id) {
					if (k_fields[i] == g_prefs.field) cur_desc() = !cur_desc();
					else g_prefs.field = k_fields[i];
					update_sort_ui();
					update_tab_stop();
					do_refresh();
					settings_save(g_prefs, k_labels, k_fields);
					break;
				}
			}
		}
		return 0;
	}

	case WM_CONTEXTMENU: {
		if (reinterpret_cast<HWND>(wp) == g_hwnd_list) {
			int selected = ListView_GetNextItem(g_hwnd_list, -1, LVNI_SELECTED);
			if (selected != -1) {
				LVITEM lvi{};
				lvi.iItem = selected;
				lvi.mask = LVIF_PARAM;
				ListView_GetItem(g_hwnd_list, &lvi);
				DWORD pid = static_cast<DWORD>(lvi.lParam);
				POINT pt;
				pt.x = GET_X_LPARAM(lp);
				pt.y = GET_Y_LPARAM(lp);
				if (pt.x == -1 && pt.y == -1) {
					RECT rc;
					ListView_GetItemRect(g_hwnd_list, selected, &rc, LVIR_BOUNDS);
					MapWindowPoints(g_hwnd_list, HWND_DESKTOP, reinterpret_cast<LPPOINT>(&rc), 2);
					pt.x = rc.left + (rc.right - rc.left) / 2;
					pt.y = rc.top + (rc.bottom - rc.top) / 2;
				}
				HMENU menu = CreatePopupMenu();
				std::wstring path = get_process_path(pid);
				if (!path.empty()) AppendMenu(menu, MF_STRING, ID_CTX_OPEN_LOCATION, L"Open file location");
				AppendMenu(menu, MF_STRING, ID_CTX_END_TASK, L"End task\tCtrl+E");
				TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, nullptr);
				DestroyMenu(menu);
			}
		}
		return 0;
	}

	case WM_NOTIFY: {
		auto* hdr = reinterpret_cast<NMHDR*>(lp);
		if (hdr->idFrom == static_cast<UINT_PTR>(ID_LISTVIEW) && hdr->code == LVN_COLUMNCLICK) {
			auto* nmlv = reinterpret_cast<NMLISTVIEW*>(lp);
			if (nmlv->iSubItem >= 0 && nmlv->iSubItem < k_sort_count) {
				if (k_fields[nmlv->iSubItem] == g_prefs.field) cur_desc() = !cur_desc();
				else g_prefs.field = k_fields[nmlv->iSubItem];
				update_sort_ui();
				update_tab_stop();
				do_refresh();
				settings_save(g_prefs, k_labels, k_fields);
			}
		}
		return DefWindowProc(hwnd, msg, wp, lp);
	}

	case WM_KEYDOWN:
		if (wp == VK_ESCAPE) { PostMessage(hwnd, WM_HIDE_TO_TRAY, 0, 0); return 0; }
		if (wp == VK_F5)     { do_refresh(); return 0; }
		return 0;

	case WM_DESTROY:
		tray_remove();
		PostQuitMessage(0);
		return 0;
	}
	return DefWindowProc(hwnd, msg, wp, lp);
}
