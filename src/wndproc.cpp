#include "process.hpp"
#include "wndproc.hpp"
#include <windows.h>
#include <commctrl.h>
#include <string>
#include <unordered_map>

#define ID_SORT_NAME   101
#define ID_SORT_PID    102
#define ID_SORT_CPU    103
#define ID_SORT_MEMORY 104
#define ID_LISTVIEW    105

static constexpr int k_btn_count = 4;
static const wchar_t* k_labels[k_btn_count]  = { L"Name", L"PID", L"CPU", L"Memory" };
static const sort_field k_fields[k_btn_count] = { sort_field::name, sort_field::pid, sort_field::cpu, sort_field::memory };
static const int k_ids[k_btn_count]           = { ID_SORT_NAME, ID_SORT_PID, ID_SORT_CPU, ID_SORT_MEMORY };
static const int k_widths[k_btn_count]        = { 120, 70, 70, 100 };

static HWND g_hwnd_list = nullptr;
static HWND g_sort_btns[k_btn_count] = {};
static HWND g_last_focus = nullptr;
static sort_field g_sort_by = sort_field::name;
static bool g_sort_desc = false;
static std::unordered_map<DWORD, cpu_snapshot> g_snapshots;

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
			swprintf_s(buf, L"%s, %s", k_labels[i], g_sort_desc ? L"descending" : L"ascending");
		else
			wcscpy_s(buf, k_labels[i]);
		SetWindowText(g_sort_btns[i], buf);
		SendMessage(g_sort_btns[i], BM_SETCHECK, active ? BST_CHECKED : BST_UNCHECKED, 0);
	}

	// Update column header sort arrows
	HWND hwnd_header = ListView_GetHeader(g_hwnd_list);
	for (int i = 0; i < k_btn_count; ++i) {
		HDITEMW hdi{};
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
	int i = 0;
	for (auto& e : entries) {
		LVITEMW lvi{};
		lvi.mask = LVIF_TEXT;
		lvi.iItem = i;
		lvi.pszText = e.name.data();
		ListView_InsertItem(g_hwnd_list, &lvi);
		auto pid_str = std::to_wstring(e.pid);
		ListView_SetItemText(g_hwnd_list, i, 1, pid_str.data());
		wchar_t cpu_buf[16];
		swprintf_s(cpu_buf, L"%.1f", e.cpu_percent);
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
}

// Arrow keys immediately select the adjacent sort; Space/Enter fall through to BN_CLICKED.
static LRESULT CALLBACK sort_btn_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR, DWORD_PTR) {
	if (msg == WM_KEYDOWN) {
		if (wp == VK_LEFT || wp == VK_RIGHT) {
			int idx = -1;
			for (int i = 0; i < k_btn_count; ++i)
				if (g_sort_btns[i] == hwnd) { idx = i; break; }
			if (idx >= 0) {
				int next = (wp == VK_RIGHT) ? (idx + 1) % k_btn_count
				                            : (idx + k_btn_count - 1) % k_btn_count;
				g_sort_by = k_fields[next];
				g_sort_desc = false;
				update_sort_ui();
				update_tab_stop();
				do_refresh();
				SetFocus(g_sort_btns[next]);
				return 0;
			}
		}
		if (wp == VK_UP || wp == VK_DOWN)
			return 0; // swallow — don't let focus escape to the list
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
		INITCOMMONCONTROLSEX icc{};
		icc.dwSize = sizeof(icc);
		icc.dwICC = ICC_LISTVIEW_CLASSES;
		InitCommonControlsEx(&icc);
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
		ListView_SetExtendedListViewStyle(g_hwnd_list,
			LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES | LVS_EX_HEADERDRAGDROP);
		auto add_col = [&](int idx, const wchar_t* text, int width) {
			LVCOLUMNW lvc{};
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
		update_sort_ui();
		update_tab_stop();
		do_refresh();
		SetFocus(g_hwnd_list);
		return 0;
	}
	case WM_COMMAND: {
		if (HIWORD(wp) == BN_CLICKED) {
			WORD id = LOWORD(wp);
			for (int i = 0; i < k_btn_count; ++i) {
				if (k_ids[i] == id) {
					if (k_fields[i] == g_sort_by)
						g_sort_desc = !g_sort_desc;
					else {
						g_sort_by = k_fields[i];
						g_sort_desc = false;
					}
					update_sort_ui();
					update_tab_stop();
					do_refresh();
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
			if (clicked == g_sort_by)
				g_sort_desc = !g_sort_desc;
			else {
				g_sort_by = clicked;
				g_sort_desc = false;
			}
			update_sort_ui();
			update_tab_stop();
			do_refresh();
		}
		return DefWindowProc(hwnd, msg, wp, lp);
	}
	case WM_KEYDOWN:
		if (wp == VK_F5) do_refresh();
		return 0;
	case WM_DESTROY:
		PostQuitMessage(0);
		return 0;
	}
	return DefWindowProc(hwnd, msg, wp, lp);
}
