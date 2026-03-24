#include "listview.h"
#include "wndproc.h"
#include "settings.h"
#include "process.h"
#include "tray.h"
#include <commctrl.h>
#include <shlwapi.h>

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
	case COL_PRIORITY: {
		const wchar_t* label;
		switch (e->base_priority) {
		case  4: label = L"Idle";         break;
		case  6: label = L"Below Normal"; break;
		case  8: label = L"Normal";       break;
		case 10: label = L"Above Normal"; break;
		case 13: label = L"High";         break;
		case 24: label = L"Realtime";     break;
		default: wnsprintf(buf, len, L"%d", e->base_priority); return;
		}
		lstrcpyn(buf, label, len);
		break;
	}
	case COL_STARTTIME: {
		if (!e->start_time) { buf[0] = L'\0'; break; }
		FILETIME ft, lft;
		ft.dwLowDateTime  = (DWORD)(e->start_time & 0xFFFFFFFF);
		ft.dwHighDateTime = (DWORD)(e->start_time >> 32);
		FileTimeToLocalFileTime(&ft, &lft);
		SYSTEMTIME st, now;
		FileTimeToSystemTime(&lft, &st);
		GetLocalTime(&now);
		if (st.wYear == now.wYear && st.wMonth == now.wMonth && st.wDay == now.wDay)
			wnsprintf(buf, len, L"%02d:%02d:%02d", st.wHour, st.wMinute, st.wSecond);
		else
			wnsprintf(buf, len, L"%02d/%02d %02d:%02d", st.wMonth, st.wDay, st.wHour, st.wMinute);
		break;
	}
	case COL_DISK_IO: {
		ULONGLONG rate = (ULONGLONG)e->disk_io_rate;
		if (rate >= 1024ULL * 1024) {
			int whole = (int)(rate / (1024 * 1024));
			int frac  = (int)((rate % (1024 * 1024)) * 10 / (1024 * 1024));
			wnsprintf(buf, len, L"%d.%d MB/s", whole, frac);
		} else if (rate >= 1024) {
			wnsprintf(buf, len, L"%u KB/s", (UINT)(rate / 1024));
		} else if (rate > 0) {
			wnsprintf(buf, len, L"%u B/s", (UINT)rate);
		} else {
			buf[0] = L'\0';
		}
		break;
	}
	case COL_PRIVATE_BYTES:
		wnsprintf(buf, len, L"%u K", (UINT)(e->private_bytes / 1024));
		break;
	case COL_PAGE_FAULTS: {
		UINT pf = (UINT)(e->page_faults_per_sec + 0.5);
		if (pf > 0)
			wnsprintf(buf, len, L"%u /s", pf);
		else
			buf[0] = L'\0';
		break;
	}
	case COL_USER:
		lstrcpyn(buf, e->user, len);
		break;
	case COL_CMDLINE:
		lstrcpyn(buf, e->cmdline, len);
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

void do_refresh(void) {
	int count = 0;
	process_entry* entries = snapshot_processes(g_snapshots, &count, g_prefs.field, g_prefs.desc[(int)g_prefs.field]);
	if (entries) {
		populate_list(entries, count);
		free_process_entries(entries);
	}
}

LRESULT CALLBACK list_key_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data) {
	UNREFERENCED_PARAMETER(id); UNREFERENCED_PARAMETER(data);
	if (msg == WM_KEYDOWN && wp == VK_ESCAPE) {
		PostMessage(GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0);
		return 0;
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}
