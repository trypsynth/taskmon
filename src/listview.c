#include "listview.h"
#include "process.h"
#include "settings.h"
#include "tray.h"
#include "treeview.h"
#include "wndproc.h"
#include <commctrl.h>
#include <shlwapi.h>

/* 100-nanosecond FILETIME ticks to h:mm:ss. */
static void format_duration(ULONGLONG ticks, wchar_t* buf, int len) {
	ULONGLONG total_secs = ticks / 10000000ULL;
	ULONGLONG hours = total_secs / 3600;
	UINT mins = (UINT)((total_secs % 3600) / 60);
	UINT secs = (UINT)(total_secs % 60);
	wnsprintf(buf, len, L"%llu:%02u:%02u", hours, mins, secs);
}

/* Deltas read as a change since the previous refresh, so they carry an explicit
 * sign and go blank when nothing moved. wnsprintf has no '+' flag of its own. */
static void format_byte_delta(LONGLONG delta, wchar_t* buf, int len) {
	if (delta == 0) {
		buf[0] = L'\0';
		return;
	}
	wchar_t size[64];
	StrFormatByteSizeW(delta < 0 ? -delta : delta, size, 64);
	wnsprintf(buf, len, L"%s%s", delta < 0 ? L"-" : L"+", size);
}

static void format_count_delta(int delta, wchar_t* buf, int len) {
	if (delta == 0)
		buf[0] = L'\0';
	else
		wnsprintf(buf, len, L"%s%d", delta < 0 ? L"-" : L"+", delta < 0 ? -delta : delta);
}

/* Like format_duration, but processes routinely run for weeks, so break out days
 * rather than letting the hour count grow without bound. */
static void format_elapsed(ULONGLONG ticks, wchar_t* buf, int len) {
	if (!ticks) {
		buf[0] = L'\0';
		return;
	}
	ULONGLONG total_secs = ticks / 10000000ULL;
	ULONGLONG days = total_secs / 86400;
	UINT hours = (UINT)((total_secs % 86400) / 3600);
	UINT mins = (UINT)((total_secs % 3600) / 60);
	UINT secs = (UINT)(total_secs % 60);
	if (days)
		wnsprintf(buf, len, L"%llud %02u:%02u:%02u", days, hours, mins, secs);
	else
		wnsprintf(buf, len, L"%02u:%02u:%02u", hours, mins, secs);
}

/* Cycle counts run to billions per second, so scale them down to a K/M/G suffix
 * the way StrFormatByteSizeW does for bytes. */
static void format_cycle_rate(double rate, wchar_t* buf, int len) {
	if (rate <= 0) {
		buf[0] = L'\0';
		return;
	}
	const wchar_t* suffix = L"";
	double divisor = 1.0;
	if (rate >= 1000000000.0) {
		suffix = L" G";
		divisor = 1000000000.0;
	} else if (rate >= 1000000.0) {
		suffix = L" M";
		divisor = 1000000.0;
	} else if (rate >= 1000.0) {
		suffix = L" K";
		divisor = 1000.0;
	}
	double scaled = rate / divisor;
	UINT whole = (UINT)scaled;
	UINT frac = (UINT)((scaled - whole) * 100 + 0.5);
	if (frac >= 100) {
		whole++;
		frac = 0;
	}
	if (divisor == 1.0)
		wnsprintf(buf, len, L"%u/s", whole);
	else
		wnsprintf(buf, len, L"%u.%02u%s/s", whole, frac, suffix);
}

static void format_column(const process_entry* e, column_id cid, wchar_t* buf, int len) {
	switch (cid) {
	case COL_PID:
		wnsprintf(buf, len, L"%u", e->pid);
		break;
	case COL_CPU: {
		int whole = (int)e->cpu_percent;
		int frac = (int)((e->cpu_percent - whole) * 100 + 0.5);
		if (frac >= 100) {
			whole++;
			frac = 0;
		}
		wnsprintf(buf, len, L"%d.%02d", whole, frac);
		break;
	}
	case COL_MEMORY:
		StrFormatByteSizeW(e->working_set, buf, len);
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
		case 4:
			label = L"Idle";
			break;
		case 6:
			label = L"Below Normal";
			break;
		case 8:
			label = L"Normal";
			break;
		case 10:
			label = L"Above Normal";
			break;
		case 13:
			label = L"High";
			break;
		case 24:
			label = L"Realtime";
			break;
		default:
			wnsprintf(buf, len, L"%d", e->base_priority);
			return;
		}
		lstrcpyn(buf, label, len);
		break;
	}
	case COL_STARTTIME: {
		if (!e->start_time) {
			buf[0] = L'\0';
			break;
		}
		FILETIME ft, lft;
		ft.dwLowDateTime = (DWORD)(e->start_time & 0xFFFFFFFF);
		ft.dwHighDateTime = (DWORD)(e->start_time >> 32);
		FileTimeToLocalFileTime(&ft, &lft);
		SYSTEMTIME st, now;
		FileTimeToSystemTime(&lft, &st);
		GetLocalTime(&now);
		if (st.wYear == now.wYear && st.wMonth == now.wMonth && st.wDay == now.wDay)
			wnsprintf(buf, len, L"%02d:%02d:%02d", st.wHour, st.wMinute, st.wSecond);
		else if (st.wYear == now.wYear)
			wnsprintf(buf, len, L"%02d/%02d %02d:%02d", st.wMonth, st.wDay, st.wHour, st.wMinute);
		else
			wnsprintf(buf, len, L"%02d/%02d/%04d %02d:%02d", st.wMonth, st.wDay, st.wYear, st.wHour, st.wMinute);
		break;
	}
	case COL_DISK_IO:
		if (e->disk_io_rate > 0) {
			StrFormatByteSizeW((LONGLONG)e->disk_io_rate, buf, len);
			lstrcat(buf, L"/s");
		} else
			buf[0] = L'\0';
		break;
	case COL_PRIVATE_BYTES:
		StrFormatByteSizeW(e->private_bytes, buf, len);
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
	case COL_ARCH:
		switch (e->arch_machine) {
		case 0x014c:
			lstrcpyn(buf, L"x86", len);
			break;
		case 0x8664:
			lstrcpyn(buf, L"x64", len);
			break;
		case 0xAA64:
			lstrcpyn(buf, L"ARM64", len);
			break;
		default:
			buf[0] = L'\0';
			break;
		}
		break;
	case COL_SESSION:
		wnsprintf(buf, len, L"%u", e->session_id);
		break;
	case COL_PEAK_WORKING_SET:
		StrFormatByteSizeW(e->peak_working_set, buf, len);
		break;
	case COL_VIRTUAL_MEM:
		StrFormatByteSizeW(e->virtual_size, buf, len);
		break;
	case COL_GDI_OBJECTS:
		if (e->gdi_objects)
			wnsprintf(buf, len, L"%u", e->gdi_objects);
		else
			buf[0] = L'\0';
		break;
	case COL_USER_OBJECTS:
		if (e->user_objects)
			wnsprintf(buf, len, L"%u", e->user_objects);
		else
			buf[0] = L'\0';
		break;
	case COL_INTEGRITY: {
		const wchar_t* label;
		switch (e->integrity_level) {
		case 0x0000:
			label = L"Untrusted";
			break;
		case 0x1000:
			label = L"Low";
			break;
		case 0x2000:
			label = L"Medium";
			break;
		case 0x2100:
			label = L"Medium+";
			break;
		case 0x3000:
			label = L"High";
			break;
		case 0x4000:
			label = L"System";
			break;
		case 0x5000:
			label = L"Protected";
			break;
		default:
			label = NULL;
			break;
		}
		if (label)
			lstrcpyn(buf, label, len);
		else
			wnsprintf(buf, len, L"0x%04X", e->integrity_level);
		break;
	}
	case COL_PPID:
		if (e->parent_pid)
			wnsprintf(buf, len, L"%u", e->parent_pid);
		else
			buf[0] = L'\0';
		break;
	case COL_PRIVATE_WS:
		StrFormatByteSizeW(e->private_working_set, buf, len);
		break;
	case COL_PAGED_POOL:
		StrFormatByteSizeW(e->paged_pool, buf, len);
		break;
	case COL_NONPAGED_POOL:
		StrFormatByteSizeW(e->non_paged_pool, buf, len);
		break;
	case COL_IO_READ:
		if (e->io_read_rate > 0) {
			StrFormatByteSizeW((LONGLONG)e->io_read_rate, buf, len);
			lstrcat(buf, L"/s");
		} else
			buf[0] = L'\0';
		break;
	case COL_IO_WRITE:
		if (e->io_write_rate > 0) {
			StrFormatByteSizeW((LONGLONG)e->io_write_rate, buf, len);
			lstrcat(buf, L"/s");
		} else
			buf[0] = L'\0';
		break;
	case COL_IO_OTHER:
		if (e->io_other_rate > 0) {
			StrFormatByteSizeW((LONGLONG)e->io_other_rate, buf, len);
			lstrcat(buf, L"/s");
		} else
			buf[0] = L'\0';
		break;
	case COL_DESCRIPTION:
		lstrcpyn(buf, e->description, len);
		break;
	case COL_COMPANY:
		lstrcpyn(buf, e->company, len);
		break;
	case COL_DPI: {
		const wchar_t* label;
		switch (e->dpi_awareness) {
		case TM_DPI_UNAWARE:
			label = L"Unaware";
			break;
		case TM_DPI_SYSTEM_AWARE:
			label = L"System";
			break;
		case TM_DPI_PER_MONITOR_AWARE:
			label = L"Per-Monitor";
			break;
		default:
			label = L"Unknown";
			break;
		}
		lstrcpyn(buf, label, len);
		break;
	}
	case COL_SERVICE:
		lstrcpyn(buf, e->services, len);
		break;
	case COL_GPU: {
		int whole = (int)e->gpu_percent;
		int frac = (int)((e->gpu_percent - whole) * 100 + 0.5);
		if (frac >= 100) {
			whole++;
			frac = 0;
		}
		wnsprintf(buf, len, L"%d.%02d", whole, frac);
		break;
	}
	case COL_GPU_MEMORY:
		StrFormatByteSizeW((LONGLONG)e->gpu_memory, buf, len);
		break;
	case COL_CPU_TIME:
		format_duration(e->cpu_time, buf, len);
		break;
	case COL_ELEVATED:
		if (e->elevated < 0)
			buf[0] = L'\0';
		else
			lstrcpyn(buf, e->elevated ? L"Yes" : L"No", len);
		break;
	case COL_PATH:
		lstrcpyn(buf, e->path, len);
		break;
	case COL_WINDOW_TITLE:
		lstrcpyn(buf, e->window_title, len);
		break;
	case COL_FILE_VERSION:
		lstrcpyn(buf, e->file_version, len);
		break;
	case COL_PRODUCT_VERSION:
		lstrcpyn(buf, e->product_version, len);
		break;
	case COL_SESSION_NAME:
		lstrcpyn(buf, e->session_name, len);
		break;
	case COL_PACKAGE_NAME:
		lstrcpyn(buf, e->package_name, len);
		break;
	case COL_PEAK_VIRTUAL_MEM:
		StrFormatByteSizeW(e->peak_virtual_size, buf, len);
		break;
	case COL_PEAK_PRIVATE_BYTES:
		StrFormatByteSizeW(e->peak_private_bytes, buf, len);
		break;
	case COL_PEAK_PAGED_POOL:
		StrFormatByteSizeW(e->peak_paged_pool, buf, len);
		break;
	case COL_PEAK_NONPAGED_POOL:
		StrFormatByteSizeW(e->peak_non_paged_pool, buf, len);
		break;
	case COL_PEAK_THREADS:
		wnsprintf(buf, len, L"%u", e->peak_threads);
		break;
	case COL_HARD_FAULTS: {
		UINT hf = (UINT)(e->hard_faults_per_sec + 0.5);
		if (hf > 0)
			wnsprintf(buf, len, L"%u /s", hf);
		else
			buf[0] = L'\0';
		break;
	}
	case COL_CYCLES:
		format_cycle_rate(e->cycles_per_sec, buf, len);
		break;
	case COL_KERNEL_TIME:
		format_duration(e->kernel_time, buf, len);
		break;
	case COL_USER_TIME:
		format_duration(e->user_time, buf, len);
		break;
	case COL_TOTAL_PAGE_FAULTS:
		wnsprintf(buf, len, L"%u", e->total_page_faults);
		break;
	case COL_IO_READ_OPS:
		wnsprintf(buf, len, L"%llu", e->io_read_ops);
		break;
	case COL_IO_WRITE_OPS:
		wnsprintf(buf, len, L"%llu", e->io_write_ops);
		break;
	case COL_IO_OTHER_OPS:
		wnsprintf(buf, len, L"%llu", e->io_other_ops);
		break;
	case COL_TOTAL_IO:
		StrFormatByteSizeW((LONGLONG)e->total_io_bytes, buf, len);
		break;
	case COL_ELAPSED:
		format_elapsed(e->elapsed_time, buf, len);
		break;
	case COL_SHARED_WS:
		StrFormatByteSizeW(e->shared_working_set, buf, len);
		break;
	case COL_PARENT_NAME:
		lstrcpyn(buf, e->parent_name, len);
		break;
	case COL_PRIVATE_BYTES_DELTA:
		format_byte_delta(e->private_bytes_delta, buf, len);
		break;
	case COL_WORKING_SET_DELTA:
		format_byte_delta(e->working_set_delta, buf, len);
		break;
	case COL_HANDLE_DELTA:
		format_count_delta(e->handle_delta, buf, len);
		break;
	case COL_THREAD_DELTA:
		format_count_delta(e->thread_delta, buf, len);
		break;
	default:
		buf[0] = L'\0';
		break;
	}
}

static double populate_list(process_entry* entries, int count) {
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
		wchar_t buf[300];
		for (int col = 1; col < g_sort_btn_count; ++col) {
			format_column(e, g_sort_btn_cols[col], buf, 300);
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
	return total_cpu;
}

void do_refresh() {
	int count = 0;
	sort_field field = g_prefs.tree_mode ? SORT_FIELD_NAME : g_prefs.field;
	BOOL desc = g_prefs.tree_mode ? FALSE : g_prefs.desc[(int)g_prefs.field];
	process_entry* entries = snapshot_processes(g_snapshots, &count, field, desc);
	if (entries) {
		double total_cpu = g_prefs.tree_mode
							   ? populate_tree_view(entries, count)
							   : populate_list(entries, count);
		free_process_entries(entries);
		if (g_hwnd_status) {
			int cpu_w = (int)total_cpu;
			int cpu_f = (int)((total_cpu - cpu_w) * 100 + 0.5);
			if (cpu_f >= 100) {
				cpu_w++;
				cpu_f = 0;
			}
			MEMORYSTATUSEX ms = {sizeof(ms)};
			GlobalMemoryStatusEx(&ms);
			ULONGLONG in_use = ms.ullTotalPhys - ms.ullAvailPhys;
			ULONGLONG total = ms.ullTotalPhys;
			int iu_w = (int)(in_use / (1024ULL * 1024 * 1024));
			int iu_f = (int)((in_use % (1024ULL * 1024 * 1024)) * 10 / (1024ULL * 1024 * 1024));
			int t_w = (int)(total / (1024ULL * 1024 * 1024));
			int t_f = (int)((total % (1024ULL * 1024 * 1024)) * 10 / (1024ULL * 1024 * 1024));
			wchar_t status[128];
			wnsprintf(status, 128, L"  %d processes  |  CPU: %d.%02d%%  |  Memory: %d.%d / %d.%d GB",
				count, cpu_w, cpu_f, iu_w, iu_f, t_w, t_f);
			SendMessage(g_hwnd_status, SB_SETTEXT, 0, (LPARAM)status);
		}
	}
}

LRESULT CALLBACK list_key_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data) {
	UNREFERENCED_PARAMETER(id);
	UNREFERENCED_PARAMETER(data);
	if (msg == WM_KEYDOWN && wp == VK_ESCAPE) {
		PostMessage(GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0);
		return 0;
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}
