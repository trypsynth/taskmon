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
static const wchar_t* k_labels[k_btn_count]      = { L"Name", L"PID", L"CPU", L"Memory" };
static const sort_field k_fields[k_btn_count]     = { sort_field::name, sort_field::pid, sort_field::cpu, sort_field::memory };
static const int k_ids[k_btn_count]               = { ID_SORT_NAME, ID_SORT_PID, ID_SORT_CPU, ID_SORT_MEMORY };
static const int k_widths[k_btn_count]            = { 100, 60, 60, 90 };

static HWND g_hwnd_list = nullptr;
static HWND g_sort_btns[k_btn_count] = {};
static sort_field g_sort_by = sort_field::name;
static bool g_sort_desc = false;
static std::unordered_map<DWORD, cpu_snapshot> g_snapshots;

static void update_sort_labels() {
	for (int i = 0; i < k_btn_count; ++i) {
		wchar_t buf[32];
		if (k_fields[i] == g_sort_by)
			swprintf_s(buf, L"%s %s", k_labels[i], g_sort_desc ? L"\u25BC" : L"\u25B2");
		else
			wcscpy_s(buf, k_labels[i]);
		SetWindowText(g_sort_btns[i], buf);
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

// Subclass proc: intercept left/right arrow keys to move focus between sort buttons.
// Space/Enter reach this too but we let DefSubclassProc handle them so the button
// sends BN_CLICKED normally.
static LRESULT CALLBACK sort_btn_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR, DWORD_PTR) {
	if (msg == WM_KEYDOWN && (wp == VK_LEFT || wp == VK_RIGHT)) {
		int idx = -1;
		for (int i = 0; i < k_btn_count; ++i)
			if (g_sort_btns[i] == hwnd) { idx = i; break; }
		if (idx >= 0) {
			int next = (wp == VK_RIGHT) ? (idx + 1) % k_btn_count : (idx + k_btn_count - 1) % k_btn_count;
			SetFocus(g_sort_btns[next]);
			return 0;
		}
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}

LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
	switch (msg) {
	case WM_CREATE: {
		INITCOMMONCONTROLSEX icc{};
		icc.dwSize = sizeof(icc);
		icc.dwICC = ICC_LISTVIEW_CLASSES;
		InitCommonControlsEx(&icc);
		int btn_x = 4;
		for (int i = 0; i < k_btn_count; ++i) {
			g_sort_btns[i] = CreateWindow(L"BUTTON", k_labels[i],
				WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
				btn_x, 4, k_widths[i], 24,
				hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(k_ids[i])),
				GetModuleHandle(nullptr), nullptr);
			SetWindowSubclass(g_sort_btns[i], sort_btn_proc, i, 0);
			btn_x += k_widths[i] + 4;
		}
		update_sort_labels();
		g_hwnd_list = CreateWindowEx(0, WC_LISTVIEWW, nullptr,
			WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SHOWSELALWAYS,
			0, 36, 760, 524,
			hwnd, reinterpret_cast<HMENU>(ID_LISTVIEW),
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
		do_refresh();
		SetFocus(g_hwnd_list);
		return 0;
	}
	case WM_COMMAND: {
		WORD id = LOWORD(wp);
		if (HIWORD(wp) == BN_CLICKED) {
			for (int i = 0; i < k_btn_count; ++i) {
				if (k_ids[i] == id) {
					if (k_fields[i] == g_sort_by)
						g_sort_desc = !g_sort_desc;
					else {
						g_sort_by = k_fields[i];
						g_sort_desc = false;
					}
					update_sort_labels();
					do_refresh();
					break;
				}
			}
		}
		return 0;
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
