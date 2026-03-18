#include "wndproc.hpp"
#include "settings.hpp"
#include "tray.hpp"
#include "process.hpp"
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <shlobj.h>
#include <commctrl.h>
#include <string>
#include <unordered_map>

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

#define ID_REFRESH_TIMER  1
#define ID_VIEW_REFRESH   401
#define ID_AUTOREFRESH_OFF   501
#define ID_AUTOREFRESH_1S    502
#define ID_AUTOREFRESH_2S    503
#define ID_AUTOREFRESH_5S    504
#define ID_AUTOREFRESH_10S   505
#define ID_AUTOREFRESH_30S   506
#define ID_AUTOREFRESH_1MIN  507

static const wchar_t* k_labels[k_sort_count] = { L"Name", L"PID", L"CPU", L"Memory" };
static const sort_field k_fields[k_sort_count] = { sort_field::name, sort_field::pid, sort_field::cpu, sort_field::memory };
static const int k_ids[k_sort_count] = { ID_SORT_NAME, ID_SORT_PID, ID_SORT_CPU, ID_SORT_MEMORY };
static const int k_widths[k_sort_count] = { 120, 70, 70, 100 };

struct refresh_option { UINT id; UINT ms; const wchar_t* label; };
static constexpr refresh_option k_refresh_options[] = {
	{ ID_AUTOREFRESH_OFF,   0,      L"Off"       },
	{ ID_AUTOREFRESH_1S,    1000,   L"1 second"  },
	{ ID_AUTOREFRESH_2S,    2000,   L"2 seconds" },
	{ ID_AUTOREFRESH_5S,    5000,   L"5 seconds" },
	{ ID_AUTOREFRESH_10S,   10000,  L"10 seconds"},
	{ ID_AUTOREFRESH_30S,   30000,  L"30 seconds"},
	{ ID_AUTOREFRESH_1MIN,  60000,  L"1 minute"  },
};
static constexpr int k_refresh_option_count = static_cast<int>(std::size(k_refresh_options));

static HWND g_hwnd = nullptr;
static HWND g_hwnd_list = nullptr;
static HWND g_sort_btns[k_sort_count] = {};
static HWND g_last_focus = nullptr;
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
		else wcscpy_s(buf, k_labels[i]);
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

static void populate_list(const std::vector<process_entry>& entries) {
	SendMessage(g_hwnd_list, WM_SETREDRAW, FALSE, 0);
	ListView_DeleteAllItems(g_hwnd_list);
	double total_cpu = 0;
	SIZE_T total_mem = 0;
	int i = 0;
	for (const auto& e : entries) {
		if (e.pid != 0) total_cpu += e.cpu_percent;
		total_mem += e.working_set;
		LVITEM lvi{};
		lvi.mask = LVIF_TEXT | LVIF_PARAM;
		lvi.iItem = i;
		lvi.pszText = const_cast<LPWSTR>(e.name.c_str());
		lvi.lParam = e.pid;
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

static void do_refresh() {
	populate_list(snapshot_processes(g_snapshots, g_prefs.field, cur_desc()));
}

static bool open_item_location(const std::wstring& path) {
	size_t separator = path.find_last_of(L"\\/");
	if (separator == std::wstring::npos) return false;
	std::wstring folder = path.substr(0, separator);
	PIDLIST_ABSOLUTE folder_pidl = ILCreateFromPathW(folder.c_str());
	PIDLIST_ABSOLUTE item_pidl = ILCreateFromPathW(path.c_str());
	if (!folder_pidl || !item_pidl) {
		if (folder_pidl) ILFree(folder_pidl);
		if (item_pidl) ILFree(item_pidl);
		return false;
	}
	PCUITEMID_CHILD child = ILFindLastID(item_pidl);
	PCUITEMID_CHILD children[] = { child };
	HRESULT hr = SHOpenFolderAndSelectItems(folder_pidl, 1, children, 0);
	ILFree(item_pidl);
	ILFree(folder_pidl);
	if (SUCCEEDED(hr)) return true;
	return reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", folder.c_str(), nullptr, nullptr, SW_SHOW)) > 32;
}

static bool confirm_end_task(HWND hwnd, const std::wstring& name, DWORD pid) {
	wchar_t message[512];
	swprintf_s(
		message,
		L"End \"%s\" (PID %lu)?\n\nUnsaved data may be lost.",
		name.empty() ? L"this process" : name.c_str(),
		static_cast<unsigned long>(pid));
	return MessageBoxW(hwnd, message, L"Confirm End Task", MB_ICONWARNING | MB_OKCANCEL | MB_DEFBUTTON2) == IDOK;
}

// Arrow keys immediately switch the active sort field; Space/Enter fall through to BN_CLICKED.
static LRESULT CALLBACK sort_btn_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR, DWORD_PTR) {
	if (msg == WM_GETDLGCODE) {
		LRESULT r = DefSubclassProc(hwnd, msg, wp, lp) | DLGC_WANTARROWS;
		auto* pmsg = reinterpret_cast<MSG*>(lp);
		if (pmsg && ((pmsg->message == WM_KEYDOWN && pmsg->wParam == VK_RETURN) || (pmsg->message == WM_CHAR && pmsg->wParam == '\r'))) r |= DLGC_WANTMESSAGE;
		return r;
	}
	if (msg == WM_CHAR && wp == '\r') return 0; // suppress beep: TranslateMessage turns VK_RETURN into WM_CHAR('\r')
	if (msg == WM_KEYDOWN) {
		if (wp == VK_ESCAPE) { PostMessage(GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0); return 0; }
		if (wp == VK_F5) { do_refresh(); return 0; }
		if (wp == VK_RETURN) { PostMessage(GetParent(hwnd), WM_COMMAND, MAKEWPARAM(GetDlgCtrlID(hwnd), BN_CLICKED), reinterpret_cast<LPARAM>(hwnd)); return 0; }
		if (wp == VK_LEFT || wp == VK_RIGHT) {
			int idx = -1;
			for (int i = 0; i < k_sort_count; ++i) if (g_sort_btns[i] == hwnd) { idx = i; break; }
			if (idx >= 0) {
				int next = (wp == VK_RIGHT) ? idx + 1 : idx - 1;
				if (next < 0 || next >= k_sort_count) return 0;
				g_prefs.field = k_fields[next];
				// Pre-set new button text before focus arrives so the screen reader reads the
				// correct label in one announcement, not the old button's text change then the new.
				wchar_t buf[64];
				swprintf_s(buf, L"%s (%s)", k_labels[next], cur_desc() ? L"descending" : L"ascending");
				SetWindowText(g_sort_btns[next], buf);
				SendMessage(g_sort_btns[next], BM_SETCHECK, BST_CHECKED, 0);
				update_tab_stop();
				SetFocus(g_sort_btns[next]);
				// update_sort_ui after focus moves: old button text change is silent, new button text is already correct.
				update_sort_ui();
				do_refresh();
				settings_save(g_prefs, k_labels, k_fields);
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
		if (wp == VK_F5) { do_refresh(); return 0; }
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}

static void create_menu_bar(HWND hwnd) {
	HMENU bar  = CreateMenu();
	HMENU view = CreatePopupMenu();
	HMENU sub  = CreatePopupMenu();
	for (int i = 0; i < k_refresh_option_count; ++i)
		AppendMenu(sub, MF_STRING, k_refresh_options[i].id, k_refresh_options[i].label);
	AppendMenu(view, MF_STRING,  ID_VIEW_REFRESH, L"Refresh\tF5");
	AppendMenu(view, MF_SEPARATOR, 0, nullptr);
	AppendMenu(view, MF_POPUP, reinterpret_cast<UINT_PTR>(sub), L"Auto-refresh");
	AppendMenu(bar,  MF_POPUP, reinterpret_cast<UINT_PTR>(view), L"View");
	SetMenu(hwnd, bar);
}

static void set_refresh_interval(HWND hwnd, UINT ms) {
	g_prefs.refresh_ms = ms;
	KillTimer(hwnd, ID_REFRESH_TIMER);
	if (ms > 0) SetTimer(hwnd, ID_REFRESH_TIMER, ms, nullptr);
	// Submenu order in create_menu_bar: Refresh(0), separator(1), Auto-refresh(2)
	HMENU bar  = GetMenu(hwnd);
	HMENU view = GetSubMenu(bar, 0);
	HMENU sub  = GetSubMenu(view, 2);
	UINT first = k_refresh_options[0].id;
	UINT last  = k_refresh_options[k_refresh_option_count - 1].id;
	bool matched = false;
	for (int i = 0; i < k_refresh_option_count; ++i) {
		if (k_refresh_options[i].ms == ms) {
			CheckMenuRadioItem(sub, first, last, k_refresh_options[i].id, MF_BYCOMMAND);
			matched = true;
			break;
		}
	}
	if (!matched) {
		// Unrecognised value (e.g. hand-edited INI) — fall back to 2 s default.
		g_prefs.refresh_ms = 2000;
		KillTimer(hwnd, ID_REFRESH_TIMER);
		SetTimer(hwnd, ID_REFRESH_TIMER, 2000, nullptr);
		CheckMenuRadioItem(sub, first, last, ID_AUTOREFRESH_2S, MF_BYCOMMAND);
	}
	settings_save(g_prefs, k_labels, k_fields);
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
		// Give screen readers the "Sort by" group label.
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
		add_col(0, L"Name", 260);
		add_col(1, L"PID", 80);
		add_col(2, L"CPU Percent", 90);
		add_col(3, L"Memory", 120);
		g_prefs = settings_load(k_labels, k_fields);
		update_sort_ui();
		update_tab_stop();
		create_menu_bar(hwnd);
		tray_add(hwnd, WM_TRAYICON, k_window_title);
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
			TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, nullptr);
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
				LVITEM lvi{};
				lvi.iItem = selected;
				lvi.mask = LVIF_PARAM;
				ListView_GetItem(g_hwnd_list, &lvi);
				wchar_t name[260]{};
				ListView_GetItemText(g_hwnd_list, selected, 0, name, static_cast<int>(std::size(name)));
				DWORD pid = static_cast<DWORD>(lvi.lParam);
				if (id == ID_CTX_OPEN_LOCATION) {
					std::wstring path = get_process_path(pid);
					if (!path.empty()) open_item_location(path);
				} else if (id == ID_CTX_END_TASK) {
					if (confirm_end_task(hwnd, name, pid)) {
						terminate_process(pid);
						do_refresh();
					}
				}
			}
			return 0;
		}
		if (id == ID_VIEW_REFRESH) { do_refresh(); return 0; }
		for (int i = 0; i < k_refresh_option_count; ++i) {
			if (id == k_refresh_options[i].id) {
				set_refresh_interval(hwnd, k_refresh_options[i].ms);
				return 0;
			}
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
	case WM_TIMER:
		if (wp == ID_REFRESH_TIMER) { do_refresh(); return 0; }
		break;
	case WM_KEYDOWN:
		if (wp == VK_ESCAPE) {
			PostMessage(hwnd, WM_HIDE_TO_TRAY, 0, 0);
			return 0;
		}
		if (wp == VK_F5) {
			do_refresh();
			return 0;
		}
		return 0;
	case WM_DESTROY:
		KillTimer(hwnd, ID_REFRESH_TIMER);
		tray_remove();
		PostQuitMessage(0);
		return 0;
	}
	return DefWindowProc(hwnd, msg, wp, lp);
}
