#include "process.hpp"
#include "wndproc.hpp"
#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>
#include <string>
#include <unordered_map>

#define ID_SORT_NAME 101
#define ID_SORT_PID 102
#define ID_SORT_CPU 103
#define ID_SORT_MEMORY 104
#define ID_LISTVIEW 105
#define ID_TRAY_RESTORE 201
#define ID_TRAY_EXIT 202
#define WM_TRAYICON (WM_APP + 1)
#define WM_HIDE_TO_TRAY (WM_APP + 2)
#define TRAY_UID 1

static constexpr int k_btn_count = 4;
static const wchar_t* k_labels[k_btn_count] = { L"Name", L"PID", L"CPU", L"Memory" };
static const sort_field k_fields[k_btn_count] = { sort_field::name, sort_field::pid, sort_field::cpu, sort_field::memory };
static const int k_ids[k_btn_count] = { ID_SORT_NAME, ID_SORT_PID, ID_SORT_CPU, ID_SORT_MEMORY };
static const int k_widths[k_btn_count] = { 120, 70, 70, 100 };

static HWND g_hwnd = nullptr;
static HWND g_hwnd_list = nullptr;
static HWND g_sort_btns[k_btn_count] = {};
static HWND g_last_focus = nullptr;
static sort_field g_sort_by = sort_field::name;
static bool g_sort_desc = false;
static bool g_sort_desc_per_field[k_btn_count] = {};
static std::unordered_map<DWORD, cpu_snapshot> g_snapshots;

static std::wstring ini_path() {
	wchar_t buf[MAX_PATH];
	GetModuleFileName(nullptr, buf, MAX_PATH);
	std::wstring p(buf);
	auto slash = p.find_last_of(L"\\/");
	if (slash != std::wstring::npos) p.resize(slash + 1);
	return p + L"taskmon.ini";
}

static void load_settings() {
	auto path = ini_path();
	const wchar_t* sec = L"sort";
	wchar_t field_buf[32];
	GetPrivateProfileString(sec, L"field", k_labels[0], field_buf, 32, path.c_str());
	for (int i = 0; i < k_btn_count; ++i) {
		if (_wcsicmp(field_buf, k_labels[i]) == 0) {
			g_sort_by = k_fields[i];
			break;
		}
	}
	for (int i = 0; i < k_btn_count; ++i) {
		wchar_t key[32], val[4];
		swprintf_s(key, L"%s_desc", k_labels[i]);
		GetPrivateProfileString(sec, key, L"0", val, 4, path.c_str());
		g_sort_desc_per_field[i] = (val[0] == L'1');
		if (k_fields[i] == g_sort_by) g_sort_desc = g_sort_desc_per_field[i];
	}
}

static void save_settings() {
	auto path = ini_path();
	const wchar_t* sec = L"sort";
	for (int i = 0; i < k_btn_count; ++i) {
		if (k_fields[i] == g_sort_by) WritePrivateProfileString(sec, L"field", k_labels[i], path.c_str());
		wchar_t key[32];
		swprintf_s(key, L"%s_desc", k_labels[i]);
		WritePrivateProfileString(sec, key, g_sort_desc_per_field[i] ? L"1" : L"0", path.c_str());
	}
}

static void add_tray_icon() {
	NOTIFYICONDATA nid{};
	nid.cbSize = sizeof(nid);
	nid.hWnd = g_hwnd;
	nid.uID = TRAY_UID;
	nid.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE;
	nid.uCallbackMessage = WM_TRAYICON;
	nid.hIcon = static_cast<HICON>(LoadImage(nullptr, IDI_APPLICATION, IMAGE_ICON, 0, 0, LR_SHARED));
	wcscpy_s(nid.szTip, L"Taskmon");
	Shell_NotifyIcon(NIM_ADD, &nid);
}

static void remove_tray_icon() {
	NOTIFYICONDATA nid{};
	nid.cbSize = sizeof(nid);
	nid.hWnd = g_hwnd;
	nid.uID = TRAY_UID;
	Shell_NotifyIcon(NIM_DELETE, &nid);
}

static void update_tray_tip(double cpu, SIZE_T mem_bytes) {
	NOTIFYICONDATA nid{};
	nid.cbSize = sizeof(nid);
	nid.hWnd = g_hwnd;
	nid.uID = TRAY_UID;
	nid.uFlags = NIF_TIP;
	swprintf_s(nid.szTip, L"Taskmon, CPU %.1f%%, %.1f GB memory used", cpu, static_cast<double>(mem_bytes) / (1024.0 * 1024.0 * 1024.0));
	Shell_NotifyIcon(NIM_MODIFY, &nid);
}

static void restore_from_tray() {
	ShowWindow(g_hwnd, SW_SHOW);
	SetForegroundWindow(g_hwnd);
}

// Only the active sort button holds WS_TABSTOP so the group counts as one tab stop.
static void update_tab_stop() {
	for (int i = 0; i < k_btn_count; ++i) {
		LONG_PTR style = GetWindowLongPtr(g_sort_btns[i], GWL_STYLE);
		if (k_fields[i] == g_sort_by)
			style |= WS_TABSTOP;
		else
			style &= ~WS_TABSTOP;
		SetWindowLongPtr(g_sort_btns[i], GWL_STYLE, style);
	}
}

static void update_sort_ui() {
	for (int i = 0; i < k_btn_count; ++i) {
		bool active = (k_fields[i] == g_sort_by);
		wchar_t buf[64];
		if (active)
			swprintf_s(buf, L"%s (%s)", k_labels[i], g_sort_desc ? L"descending" : L"ascending");
		else
			wcscpy_s(buf, k_labels[i]);
		SetWindowText(g_sort_btns[i], buf);
		SendMessage(g_sort_btns[i], BM_SETCHECK, active ? BST_CHECKED : BST_UNCHECKED, 0);
	}

	// Update column header sort arrows
	HWND hwnd_header = ListView_GetHeader(g_hwnd_list);
	for (int i = 0; i < k_btn_count; ++i) {
		HDITEM hdi{};
		hdi.mask = HDI_FORMAT;
		Header_GetItem(hwnd_header, i, &hdi);
		hdi.fmt &= ~(HDF_SORTUP | HDF_SORTDOWN);
		if (k_fields[i] == g_sort_by)
			hdi.fmt |= g_sort_desc ? HDF_SORTDOWN : HDF_SORTUP;
		Header_SetItem(hwnd_header, i, &hdi);
	}
}

static void do_refresh() {
	auto entries = snapshot_processes(g_snapshots, g_sort_by, g_sort_desc);
	SendMessage(g_hwnd_list, WM_SETREDRAW, FALSE, 0);
	ListView_DeleteAllItems(g_hwnd_list);
	double total_cpu = 0;
	SIZE_T total_mem = 0;
	int i = 0;
	for (auto& e : entries) {
		total_cpu += e.cpu_percent;
		total_mem += e.working_set;
		LVITEM lvi{};
		lvi.mask = LVIF_TEXT;
		lvi.iItem = i;
		lvi.pszText = e.name.data();
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
	update_tray_tip(total_cpu, total_mem);
}

// Arrow keys immediately select the adjacent sort; Space/Enter fall through to BN_CLICKED.
static LRESULT CALLBACK sort_btn_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR, DWORD_PTR) {
	if (msg == WM_KEYDOWN) {
		if (wp == VK_ESCAPE) {
			PostMessage(GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0);
			return 0;
		}
		if (wp == VK_LEFT || wp == VK_RIGHT) {
			int idx = -1;
			for (int i = 0; i < k_btn_count; ++i)
				if (g_sort_btns[i] == hwnd) {
					idx = i;
					break;
				}
			if (idx >= 0) {
				int next = (wp == VK_RIGHT) ? (idx + 1) % k_btn_count
				 : (idx + k_btn_count - 1) % k_btn_count;
				g_sort_by = k_fields[next];
				g_sort_desc = g_sort_desc_per_field[next];
				update_sort_ui();
				update_tab_stop();
				do_refresh();
				save_settings();
				SetFocus(g_sort_btns[next]);
				return 0;
			}
		}
		if (wp == VK_UP || wp == VK_DOWN)
			return 0; // swallow — don't let focus escape to the list
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}

// Forwards Escape from the list view to the main window.
static LRESULT CALLBACK list_key_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR, DWORD_PTR) {
	if (msg == WM_KEYDOWN && wp == VK_ESCAPE) {
		PostMessage(GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0);
		return 0;
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}

LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
	switch (msg) {
	case WM_ACTIVATE:
		if (LOWORD(wp) == WA_INACTIVE) {
			g_last_focus = GetFocus();
		} else {
			if (g_last_focus)
				SetFocus(g_last_focus);
			else
				SetFocus(g_hwnd_list);
		}
		return 0;
	case WM_CREATE: {
		g_hwnd = hwnd;
		INITCOMMONCONTROLSEX icc{};
		icc.dwSize = sizeof(icc);
		icc.dwICC = ICC_LISTVIEW_CLASSES;
		InitCommonControlsEx(&icc);
		// Invisible groupbox gives screen readers the group label "Sort by".
		CreateWindow(L"BUTTON", L"Sort by",
			WS_CHILD | WS_VISIBLE | BS_GROUPBOX,
			0, 0, 360, 1,
			hwnd, nullptr, GetModuleHandle(nullptr), nullptr);
		int btn_x = 0;
		for (int i = 0; i < k_btn_count; ++i) {
			// WS_TABSTOP is set dynamically; only the active button carries it.
			g_sort_btns[i] = CreateWindow(L"BUTTON", k_labels[i],
				WS_CHILD | WS_VISIBLE | BS_RADIOBUTTON,
				btn_x, 0, k_widths[i], 1,
				hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(k_ids[i])),
				GetModuleHandle(nullptr), nullptr);
			SetWindowSubclass(g_sort_btns[i], sort_btn_proc, i, 0);
			btn_x += k_widths[i];
		}
		g_hwnd_list = CreateWindowEx(0, WC_LISTVIEWW, nullptr,
			WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SHOWSELALWAYS,
			0, 1, 760, 559,
			hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(ID_LISTVIEW)),
			GetModuleHandle(nullptr), nullptr);
		SetWindowSubclass(g_hwnd_list, list_key_proc, 0, 0);
		ListView_SetExtendedListViewStyle(g_hwnd_list,
			LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES | LVS_EX_HEADERDRAGDROP);
		auto add_col = [&](int idx, const wchar_t* text, int width) {
			LVCOLUMN lvc{};
			lvc.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_SUBITEM;
			lvc.cx = width;
			lvc.pszText = const_cast<LPWSTR>(text);
			lvc.iSubItem = idx;
			ListView_InsertColumn(g_hwnd_list, idx, &lvc);
		};
		add_col(0, L"Name", 260);
		add_col(1, L"PID", 80);
		add_col(2, L"CPU Percent", 90);
		add_col(3, L"Memory", 120);
		load_settings();
		update_sort_ui();
		update_tab_stop();
		add_tray_icon();
		do_refresh();
		SetFocus(g_hwnd_list);
		return 0;
	}
	case WM_HIDE_TO_TRAY:
		ShowWindow(hwnd, SW_HIDE);
		return 0;
	case WM_TRAYICON:
		if (lp == WM_LBUTTONUP) {
			restore_from_tray();
		} else if (lp == WM_RBUTTONUP) {
			HMENU menu = CreatePopupMenu();
			AppendMenu(menu, MF_STRING, ID_TRAY_RESTORE, L"Restore");
			AppendMenu(menu, MF_STRING, ID_TRAY_EXIT, L"Exit");
			POINT pt;
			GetCursorPos(&pt);
			SetForegroundWindow(hwnd); // required so the menu dismisses when focus is lost
			TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, nullptr);
			PostMessage(hwnd, WM_NULL, 0, 0); // required Win32 quirk to flush menu state
			DestroyMenu(menu);
		}
		return 0;
	case WM_COMMAND: {
		WORD id = LOWORD(wp);
		if (id == ID_TRAY_RESTORE) {
			restore_from_tray();
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
		if (HIWORD(wp) == BN_CLICKED) {
			for (int i = 0; i < k_btn_count; ++i) {
				if (k_ids[i] == id) {
					if (k_fields[i] == g_sort_by) {
						g_sort_desc = !g_sort_desc;
						g_sort_desc_per_field[i] = g_sort_desc;
					} else {
						g_sort_by = k_fields[i];
						g_sort_desc = g_sort_desc_per_field[i];
					}
					update_sort_ui();
					update_tab_stop();
					do_refresh();
					save_settings();
					break;
				}
			}
		}
		return 0;
	}
	case WM_NOTIFY: {
		auto* hdr = reinterpret_cast<NMHDR*>(lp);
		if (hdr->idFrom == static_cast<UINT_PTR>(ID_LISTVIEW) && hdr->code == LVN_COLUMNCLICK) {
			auto* nmlv = reinterpret_cast<NMLISTVIEW*>(lp);
			if (nmlv->iSubItem < 0 || nmlv->iSubItem >= k_btn_count) return 0;
			sort_field clicked = k_fields[nmlv->iSubItem];
			int ci = nmlv->iSubItem;
			if (clicked == g_sort_by) {
				g_sort_desc = !g_sort_desc;
				g_sort_desc_per_field[ci] = g_sort_desc;
			} else {
				g_sort_by = clicked;
				g_sort_desc = g_sort_desc_per_field[ci];
			}
			update_sort_ui();
			update_tab_stop();
			do_refresh();
			save_settings();
		}
		return DefWindowProc(hwnd, msg, wp, lp);
	}
	case WM_KEYDOWN:
		if (wp == VK_ESCAPE) {
			PostMessage(hwnd, WM_HIDE_TO_TRAY, 0, 0);
			return 0;
		}
		if (wp == VK_F5) do_refresh();
		return 0;
	case WM_DESTROY:
		remove_tray_icon();
		PostQuitMessage(0);
		return 0;
	}
	return DefWindowProc(hwnd, msg, wp, lp);
}
