#include "process.h"
#include <appmodel.h>
#include <pdh.h>
#include <pdhmsg.h>
#include <sddl.h>
#include <shlwapi.h>
#include <winternl.h>
#include <wtsapi32.h>

#define SystemProcessInformation 5
#define STATUS_INFO_LENGTH_MISMATCH 0xC0000004L

typedef struct SPI {
	ULONG NextEntryOffset;
	ULONG NumberOfThreads;
	LARGE_INTEGER WorkingSetPrivateSize;
	ULONG HardFaultCount;
	ULONG NumberOfThreadsHighWatermark;
	ULONGLONG CycleTime;
	LARGE_INTEGER CreateTime;
	LARGE_INTEGER UserTime;
	LARGE_INTEGER KernelTime;
	UNICODE_STRING ImageName;
	LONG BasePriority;
	HANDLE UniqueProcessId;
	HANDLE InheritedFromUniqueProcessId;
	ULONG HandleCount;
	ULONG SessionId;
	ULONG_PTR UniqueProcessKey;
	SIZE_T PeakVirtualSize;
	SIZE_T VirtualSize;
	ULONG PageFaultCount;
	SIZE_T PeakWorkingSetSize;
	SIZE_T WorkingSetSize;
	SIZE_T QuotaPeakPagedPoolUsage;
	SIZE_T QuotaPagedPoolUsage;
	SIZE_T QuotaPeakNonPagedPoolUsage;
	SIZE_T QuotaNonPagedPoolUsage;
	SIZE_T PagefileUsage;
	SIZE_T PeakPagefileUsage;
	SIZE_T PrivatePageCount;
	LARGE_INTEGER ReadOperationCount;
	LARGE_INTEGER WriteOperationCount;
	LARGE_INTEGER OtherOperationCount;
	LARGE_INTEGER ReadTransferCount;
	LARGE_INTEGER WriteTransferCount;
	LARGE_INTEGER OtherTransferCount;
} SPI;

typedef NTSTATUS(NTAPI* PFN_NtQSI)(ULONG, PVOID, ULONG, PULONG);
typedef NTSTATUS(NTAPI* PFN_NtProc)(HANDLE);
typedef NTSTATUS(NTAPI* PFN_NtQIP)(HANDLE, DWORD, PVOID, ULONG, PULONG);
typedef BOOL(WINAPI* PFN_IsWow64Process2)(HANDLE, USHORT*, USHORT*);

static DWORD g_suspended_pids[SNAPSHOT_CAPACITY];
static int g_suspended_count = 0;

static void* heap_alloc(SIZE_T size) {
	return HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size);
}

static void* heap_realloc(void* ptr, SIZE_T size) {
	return HeapReAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, ptr, size);
}

static void heap_free(void* ptr) {
	HeapFree(GetProcessHeap(), 0, ptr);
}

static PDH_HQUERY g_pdh_query = NULL;
static PDH_HCOUNTER g_pdh_util = NULL;
static PDH_HCOUNTER g_pdh_mem_dedicated = NULL;
static PDH_HCOUNTER g_pdh_mem_shared = NULL;
static BOOL g_pdh_ready = FALSE;
static BOOL g_pdh_init_attempted = FALSE;

typedef struct {
	DWORD pid;
	double gpu_percent;
	ULONGLONG gpu_memory;
	BOOL active;
} gpu_stat_entry;
static gpu_stat_entry g_gpu_stats[SNAPSHOT_CAPACITY];

static void init_gpu_counters(void) {
	g_pdh_init_attempted = TRUE;
	if (PdhOpenQueryW(NULL, 0, &g_pdh_query) != ERROR_SUCCESS) return;
	BOOL ok = TRUE;
	ok &= PdhAddEnglishCounterW(g_pdh_query, L"\\GPU Engine(*)\\Utilization Percentage", 0, &g_pdh_util) == ERROR_SUCCESS;
	ok &= PdhAddEnglishCounterW(g_pdh_query, L"\\GPU Process Memory(*)\\Dedicated Usage", 0, &g_pdh_mem_dedicated) == ERROR_SUCCESS;
	ok &= PdhAddEnglishCounterW(g_pdh_query, L"\\GPU Process Memory(*)\\Shared Usage", 0, &g_pdh_mem_shared) == ERROR_SUCCESS;
	if (!ok) {
		PdhCloseQuery(g_pdh_query);
		g_pdh_query = NULL;
		return;
	}
	g_pdh_ready = TRUE;
}

void gpu_cleanup(void) {
	if (g_pdh_query) {
		PdhCloseQuery(g_pdh_query);
		g_pdh_query = NULL;
	}
	g_pdh_ready = FALSE;
}

static void add_gpu_stat(DWORD pid, double percent, ULONGLONG memory) {
	int h = pid % SNAPSHOT_CAPACITY;
	int i = h;
	do {
		if (!g_gpu_stats[i].active || g_gpu_stats[i].pid == pid) {
			g_gpu_stats[i].active = TRUE;
			g_gpu_stats[i].pid = pid;
			g_gpu_stats[i].gpu_percent += percent;
			g_gpu_stats[i].gpu_memory += memory;
			return;
		}
		i = (i + 1) % SNAPSHOT_CAPACITY;
	} while (i != h);
}

static void get_gpu_stat(DWORD pid, double* out_percent, ULONGLONG* out_memory) {
	*out_percent = 0.0;
	*out_memory = 0;
	int h = pid % SNAPSHOT_CAPACITY;
	int i = h;
	do {
		if (!g_gpu_stats[i].active) return;
		if (g_gpu_stats[i].pid == pid) {
			*out_percent = g_gpu_stats[i].gpu_percent;
			*out_memory = g_gpu_stats[i].gpu_memory;
			return;
		}
		i = (i + 1) % SNAPSHOT_CAPACITY;
	} while (i != h);
}

/* Instance names look like "pid_1234_luid_0x00000000_0x0000abcd_phys_0_eng_0_engtype_3D". */
static DWORD parse_pid_from_instance(const wchar_t* name) {
	const wchar_t prefix[] = L"pid_";
	int i = 0;
	for (; prefix[i]; i++) {
		if (name[i] != prefix[i]) return 0;
	}
	if (name[i] < L'0' || name[i] > L'9') return 0;
	DWORD pid = 0;
	while (name[i] >= L'0' && name[i] <= L'9') {
		pid = pid * 10 + (name[i] - L'0');
		i++;
	}
	return pid;
}

static void accumulate_counter_array(PDH_HCOUNTER counter, DWORD format, BOOL is_percent) {
	DWORD buf_size = 0, item_count = 0;
	PDH_STATUS st = PdhGetFormattedCounterArrayW(counter, format, &buf_size, &item_count, NULL);
	if (st != PDH_MORE_DATA || buf_size == 0) return;
	PDH_FMT_COUNTERVALUE_ITEM_W* items = heap_alloc(buf_size);
	if (!items) return;
	st = PdhGetFormattedCounterArrayW(counter, format, &buf_size, &item_count, items);
	if (st == ERROR_SUCCESS) {
		for (DWORD i = 0; i < item_count; i++) {
			DWORD pid = parse_pid_from_instance(items[i].szName);
			if (!pid) continue;
			if (is_percent)
				add_gpu_stat(pid, items[i].FmtValue.doubleValue, 0);
			else
				add_gpu_stat(pid, 0.0, (ULONGLONG)items[i].FmtValue.largeValue);
		}
	}
	heap_free(items);
}

static void refresh_gpu_stats(void) {
	if (!g_pdh_init_attempted) init_gpu_counters();
	memset(g_gpu_stats, 0, sizeof(g_gpu_stats));
	if (!g_pdh_ready) return;
	if (PdhCollectQueryData(g_pdh_query) != ERROR_SUCCESS) return;
	accumulate_counter_array(g_pdh_util, PDH_FMT_DOUBLE, TRUE);
	accumulate_counter_array(g_pdh_mem_dedicated, PDH_FMT_LARGE, FALSE);
	accumulate_counter_array(g_pdh_mem_shared, PDH_FMT_LARGE, FALSE);
}

typedef struct {
	DWORD pid;
	wchar_t name[64];
} svc_entry;
static svc_entry* g_svc_map = NULL;
static int g_svc_count = 0;

static void build_service_map() {
	heap_free(g_svc_map);
	g_svc_map = NULL;
	g_svc_count = 0;
	SC_HANDLE hscm = OpenSCManager(NULL, NULL, SC_MANAGER_ENUMERATE_SERVICE);
	if (!hscm) return;
	DWORD needed = 0, count = 0, resume = 0;
	EnumServicesStatusExW(hscm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_STATE_ALL,
		NULL, 0, &needed, &count, &resume, NULL);
	if (!needed) {
		CloseServiceHandle(hscm);
		return;
	}
	BYTE* buf = heap_alloc(needed);
	if (!buf) {
		CloseServiceHandle(hscm);
		return;
	}
	resume = 0;
	if (EnumServicesStatusExW(hscm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_STATE_ALL,
			buf, needed, &needed, &count, &resume, NULL)) {
		g_svc_map = heap_alloc(count * sizeof(svc_entry));
		if (g_svc_map) {
			ENUM_SERVICE_STATUS_PROCESSW* sv = (ENUM_SERVICE_STATUS_PROCESSW*)buf;
			for (DWORD i = 0; i < count; i++) {
				DWORD pid = sv[i].ServiceStatusProcess.dwProcessId;
				if (!pid) continue;
				g_svc_map[g_svc_count].pid = pid;
				lstrcpyn(g_svc_map[g_svc_count].name, sv[i].lpServiceName, 64);
				g_svc_count++;
			}
		}
	}
	heap_free(buf);
	CloseServiceHandle(hscm);
}

static void get_services_for_pid(DWORD pid, wchar_t* buf, int len) {
	buf[0] = L'\0';
	if (!pid || !g_svc_map) return;
	int pos = 0;
	for (int i = 0; i < g_svc_count && pos < len - 1; i++) {
		if (g_svc_map[i].pid != pid) continue;
		if (pos > 0 && pos + 2 < len) {
			buf[pos++] = L';';
			buf[pos++] = L' ';
		}
		int nlen = lstrlen(g_svc_map[i].name);
		if (pos + nlen >= len) nlen = len - pos - 1;
		if (nlen > 0) {
			memcpy(buf + pos, g_svc_map[i].name, nlen * sizeof(wchar_t));
			pos += nlen;
		}
		buf[pos] = L'\0';
	}
}

typedef struct {
	DWORD pid;
	wchar_t title[128];
} win_entry;
static win_entry* g_win_map = NULL;
static int g_win_count = 0;
static int g_win_capacity = 0;

static BOOL CALLBACK enum_windows_proc(HWND hwnd, LPARAM lparam) {
	UNREFERENCED_PARAMETER(lparam);
	if (!IsWindowVisible(hwnd)) return TRUE;
	if (GetWindow(hwnd, GW_OWNER) != NULL) return TRUE; /* only true top-level windows */
	wchar_t title[128];
	int len = GetWindowText(hwnd, title, 128);
	if (len == 0) return TRUE;
	DWORD pid = 0;
	GetWindowThreadProcessId(hwnd, &pid);
	if (!pid) return TRUE;
	for (int i = 0; i < g_win_count; i++)
		if (g_win_map[i].pid == pid) return TRUE; /* keep the first (topmost z-order) window per pid */
	if (g_win_count >= g_win_capacity) {
		g_win_capacity = g_win_capacity ? g_win_capacity * 2 : 64;
		g_win_map = heap_realloc(g_win_map, g_win_capacity * sizeof(win_entry));
		if (!g_win_map) {
			g_win_capacity = 0;
			g_win_count = 0;
			return FALSE;
		}
	}
	g_win_map[g_win_count].pid = pid;
	lstrcpyn(g_win_map[g_win_count].title, title, 128);
	g_win_count++;
	return TRUE;
}

static void build_window_map() {
	g_win_count = 0;
	if (!g_win_map) {
		/* heap_realloc is HeapReAlloc, which (unlike CRT realloc) requires a
		 * real existing block, so seed one here; otherwise growth in the
		 * callback would call it with NULL. */
		g_win_capacity = 64;
		g_win_map = heap_alloc(g_win_capacity * sizeof(win_entry));
	}
	EnumWindows(enum_windows_proc, 0);
}

static void get_window_title_for_pid(DWORD pid, wchar_t* buf, int len) {
	buf[0] = L'\0';
	if (!pid) return;
	for (int i = 0; i < g_win_count; i++) {
		if (g_win_map[i].pid == pid) {
			lstrcpyn(buf, g_win_map[i].title, len);
			return;
		}
	}
}

static BYTE* query_all_processes(ULONG* total_size) {
	static PFN_NtQSI fn = NULL;
	if (!fn) fn = (PFN_NtQSI)GetProcAddress(GetModuleHandle(L"ntdll.dll"), "NtQuerySystemInformation");
	if (!fn) return NULL;
	ULONG size = 512 * 1024;
	for (;;) {
		BYTE* buf = heap_alloc(size);
		if (!buf) return NULL;
		ULONG returned = 0;
		NTSTATUS st = fn(SystemProcessInformation, buf, size, &returned);
		if (st == 0) {
			*total_size = returned ? returned : size;
			return buf;
		}
		heap_free(buf);
		if (st == (NTSTATUS)STATUS_INFO_LENGTH_MISMATCH) {
			size = returned ? returned + 65536 : size * 2;
			continue;
		}
		return NULL;
	}
}

static void update_snapshot(snapshot_entry* snapshots, DWORD pid, cpu_snapshot snap) {
	int h = pid % SNAPSHOT_CAPACITY;
	int i = h;
	do {
		if (!snapshots[i].active || snapshots[i].pid == pid) {
			snapshots[i].active = TRUE;
			snapshots[i].pid = pid;
			snapshots[i].snapshot = snap;
			return;
		}
		i = (i + 1) % SNAPSHOT_CAPACITY;
	} while (i != h);
}

static cpu_snapshot* find_snapshot(snapshot_entry* snapshots, DWORD pid) {
	int h = pid % SNAPSHOT_CAPACITY;
	int i = h;
	do {
		if (!snapshots[i].active) return NULL;
		if (snapshots[i].pid == pid) return &snapshots[i].snapshot;
		i = (i + 1) % SNAPSHOT_CAPACITY;
	} while (i != h);
	return NULL;
}

/* process_entry is large enough now that copying it by value risks overflowing
 * the no-CRT stack-probe-free frame budget (__chkstk isn't linkable here), so
 * swaps and the pivot copy go through a heap scratch buffer instead. */
static void swap(process_entry* a, process_entry* b, process_entry* scratch) {
	memcpy(scratch, a, sizeof(process_entry));
	memcpy(a, b, sizeof(process_entry));
	memcpy(b, scratch, sizeof(process_entry));
}

static int compare_entries(const process_entry* a, const process_entry* b, sort_field field, BOOL descending) {
	int res = 0;
	switch (field) {
	case SORT_FIELD_NAME:
		res = StrCmpI(a->name, b->name);
		break;
	case SORT_FIELD_PID:
		res = (a->pid < b->pid) ? -1 : (a->pid > b->pid);
		break;
	case SORT_FIELD_CPU:
		res = (a->cpu_percent < b->cpu_percent) ? -1 : (a->cpu_percent > b->cpu_percent);
		break;
	case SORT_FIELD_MEMORY:
		res = (a->working_set < b->working_set) ? -1 : (a->working_set > b->working_set);
		break;
	case SORT_FIELD_THREADS:
		res = (a->threads < b->threads) ? -1 : (a->threads > b->threads);
		break;
	case SORT_FIELD_HANDLES:
		res = (a->handles < b->handles) ? -1 : (a->handles > b->handles);
		break;
	case SORT_FIELD_STARTTIME:
		res = (a->start_time < b->start_time) ? -1 : (a->start_time > b->start_time);
		break;
	case SORT_FIELD_PRIORITY:
		res = (a->base_priority < b->base_priority) ? -1 : (a->base_priority > b->base_priority);
		break;
	case SORT_FIELD_DISK_IO:
		res = (a->disk_io_rate < b->disk_io_rate) ? -1 : (a->disk_io_rate > b->disk_io_rate);
		break;
	case SORT_FIELD_PRIVATE_BYTES:
		res = (a->private_bytes < b->private_bytes) ? -1 : (a->private_bytes > b->private_bytes);
		break;
	case SORT_FIELD_PAGE_FAULTS:
		res = (a->page_faults_per_sec < b->page_faults_per_sec) ? -1 : (a->page_faults_per_sec > b->page_faults_per_sec);
		break;
	case SORT_FIELD_USER:
		res = StrCmpI(a->user, b->user);
		break;
	case SORT_FIELD_CMDLINE:
		res = StrCmpI(a->cmdline, b->cmdline);
		break;
	case SORT_FIELD_ARCH:
		res = (a->arch_machine < b->arch_machine) ? -1 : (a->arch_machine > b->arch_machine);
		break;
	case SORT_FIELD_SESSION:
		res = (a->session_id < b->session_id) ? -1 : (a->session_id > b->session_id);
		break;
	case SORT_FIELD_PEAK_WORKING_SET:
		res = (a->peak_working_set < b->peak_working_set) ? -1 : (a->peak_working_set > b->peak_working_set);
		break;
	case SORT_FIELD_VIRTUAL_MEM:
		res = (a->virtual_size < b->virtual_size) ? -1 : (a->virtual_size > b->virtual_size);
		break;
	case SORT_FIELD_GDI_OBJECTS:
		res = (a->gdi_objects < b->gdi_objects) ? -1 : (a->gdi_objects > b->gdi_objects);
		break;
	case SORT_FIELD_USER_OBJECTS:
		res = (a->user_objects < b->user_objects) ? -1 : (a->user_objects > b->user_objects);
		break;
	case SORT_FIELD_INTEGRITY:
		res = (a->integrity_level < b->integrity_level) ? -1 : (a->integrity_level > b->integrity_level);
		break;
	case SORT_FIELD_PPID:
		res = (a->parent_pid < b->parent_pid) ? -1 : (a->parent_pid > b->parent_pid);
		break;
	case SORT_FIELD_PRIVATE_WS:
		res = (a->private_working_set < b->private_working_set) ? -1 : (a->private_working_set > b->private_working_set);
		break;
	case SORT_FIELD_PAGED_POOL:
		res = (a->paged_pool < b->paged_pool) ? -1 : (a->paged_pool > b->paged_pool);
		break;
	case SORT_FIELD_NONPAGED_POOL:
		res = (a->non_paged_pool < b->non_paged_pool) ? -1 : (a->non_paged_pool > b->non_paged_pool);
		break;
	case SORT_FIELD_IO_READ:
		res = (a->io_read_rate < b->io_read_rate) ? -1 : (a->io_read_rate > b->io_read_rate);
		break;
	case SORT_FIELD_IO_WRITE:
		res = (a->io_write_rate < b->io_write_rate) ? -1 : (a->io_write_rate > b->io_write_rate);
		break;
	case SORT_FIELD_IO_OTHER:
		res = (a->io_other_rate < b->io_other_rate) ? -1 : (a->io_other_rate > b->io_other_rate);
		break;
	case SORT_FIELD_DESCRIPTION:
		res = StrCmpI(a->description, b->description);
		break;
	case SORT_FIELD_COMPANY:
		res = StrCmpI(a->company, b->company);
		break;
	case SORT_FIELD_DPI:
		res = (int)a->dpi_awareness - (int)b->dpi_awareness;
		break;
	case SORT_FIELD_SERVICE:
		res = StrCmpI(a->services, b->services);
		break;
	case SORT_FIELD_GPU:
		res = (a->gpu_percent < b->gpu_percent) ? -1 : (a->gpu_percent > b->gpu_percent);
		break;
	case SORT_FIELD_GPU_MEMORY:
		res = (a->gpu_memory < b->gpu_memory) ? -1 : (a->gpu_memory > b->gpu_memory);
		break;
	case SORT_FIELD_CPU_TIME:
		res = (a->cpu_time < b->cpu_time) ? -1 : (a->cpu_time > b->cpu_time);
		break;
	case SORT_FIELD_ELEVATED:
		res = (a->elevated < b->elevated) ? -1 : (a->elevated > b->elevated);
		break;
	case SORT_FIELD_PATH:
		res = StrCmpI(a->path, b->path);
		break;
	case SORT_FIELD_WINDOW_TITLE:
		res = StrCmpI(a->window_title, b->window_title);
		break;
	case SORT_FIELD_FILE_VERSION:
		res = StrCmpI(a->file_version, b->file_version);
		break;
	case SORT_FIELD_PRODUCT_VERSION:
		res = StrCmpI(a->product_version, b->product_version);
		break;
	case SORT_FIELD_SESSION_NAME:
		res = StrCmpI(a->session_name, b->session_name);
		break;
	case SORT_FIELD_PACKAGE_NAME:
		res = StrCmpI(a->package_name, b->package_name);
		break;
	case SORT_FIELD_PEAK_VIRTUAL_MEM:
		res = (a->peak_virtual_size < b->peak_virtual_size) ? -1 : (a->peak_virtual_size > b->peak_virtual_size);
		break;
	case SORT_FIELD_PEAK_PRIVATE_BYTES:
		res = (a->peak_private_bytes < b->peak_private_bytes) ? -1 : (a->peak_private_bytes > b->peak_private_bytes);
		break;
	case SORT_FIELD_PEAK_PAGED_POOL:
		res = (a->peak_paged_pool < b->peak_paged_pool) ? -1 : (a->peak_paged_pool > b->peak_paged_pool);
		break;
	case SORT_FIELD_PEAK_NONPAGED_POOL:
		res = (a->peak_non_paged_pool < b->peak_non_paged_pool) ? -1 : (a->peak_non_paged_pool > b->peak_non_paged_pool);
		break;
	case SORT_FIELD_PEAK_THREADS:
		res = (a->peak_threads < b->peak_threads) ? -1 : (a->peak_threads > b->peak_threads);
		break;
	case SORT_FIELD_HARD_FAULTS:
		res = (a->hard_faults_per_sec < b->hard_faults_per_sec) ? -1 : (a->hard_faults_per_sec > b->hard_faults_per_sec);
		break;
	case SORT_FIELD_CYCLES:
		res = (a->cycles_per_sec < b->cycles_per_sec) ? -1 : (a->cycles_per_sec > b->cycles_per_sec);
		break;
	case SORT_FIELD_KERNEL_TIME:
		res = (a->kernel_time < b->kernel_time) ? -1 : (a->kernel_time > b->kernel_time);
		break;
	case SORT_FIELD_USER_TIME:
		res = (a->user_time < b->user_time) ? -1 : (a->user_time > b->user_time);
		break;
	case SORT_FIELD_TOTAL_PAGE_FAULTS:
		res = (a->total_page_faults < b->total_page_faults) ? -1 : (a->total_page_faults > b->total_page_faults);
		break;
	case SORT_FIELD_IO_READ_OPS:
		res = (a->io_read_ops < b->io_read_ops) ? -1 : (a->io_read_ops > b->io_read_ops);
		break;
	case SORT_FIELD_IO_WRITE_OPS:
		res = (a->io_write_ops < b->io_write_ops) ? -1 : (a->io_write_ops > b->io_write_ops);
		break;
	case SORT_FIELD_IO_OTHER_OPS:
		res = (a->io_other_ops < b->io_other_ops) ? -1 : (a->io_other_ops > b->io_other_ops);
		break;
	case SORT_FIELD_TOTAL_IO:
		res = (a->total_io_bytes < b->total_io_bytes) ? -1 : (a->total_io_bytes > b->total_io_bytes);
		break;
	case SORT_FIELD_ELAPSED:
		res = (a->elapsed_time < b->elapsed_time) ? -1 : (a->elapsed_time > b->elapsed_time);
		break;
	case SORT_FIELD_SHARED_WS:
		res = (a->shared_working_set < b->shared_working_set) ? -1 : (a->shared_working_set > b->shared_working_set);
		break;
	case SORT_FIELD_PARENT_NAME:
		res = StrCmpI(a->parent_name, b->parent_name);
		break;
	case SORT_FIELD_PRIVATE_BYTES_DELTA:
		res = (a->private_bytes_delta < b->private_bytes_delta) ? -1 : (a->private_bytes_delta > b->private_bytes_delta);
		break;
	case SORT_FIELD_WORKING_SET_DELTA:
		res = (a->working_set_delta < b->working_set_delta) ? -1 : (a->working_set_delta > b->working_set_delta);
		break;
	case SORT_FIELD_HANDLE_DELTA:
		res = (a->handle_delta < b->handle_delta) ? -1 : (a->handle_delta > b->handle_delta);
		break;
	case SORT_FIELD_THREAD_DELTA:
		res = (a->thread_delta < b->thread_delta) ? -1 : (a->thread_delta > b->thread_delta);
		break;
	case SORT_FIELD_VIRTUALIZATION:
		res = (a->virtualization < b->virtualization) ? -1 : (a->virtualization > b->virtualization);
		break;
	case SORT_FIELD_APP_CONTAINER:
		res = (a->app_container < b->app_container) ? -1 : (a->app_container > b->app_container);
		break;
	case SORT_FIELD_DOMAIN:
		res = StrCmpI(a->domain, b->domain);
		break;
	case SORT_FIELD_USER_SID:
		res = StrCmpI(a->user_sid, b->user_sid);
		break;
	default:
		break;
	}
	return descending ? -res : res;
}

static void quicksort(process_entry* entries, int low, int high, sort_field field, BOOL descending) {
	if (low >= high) return;
	typedef struct {
		int low, high;
	} stack_entry;
	stack_entry stack[64];
	process_entry* pivot = heap_alloc(sizeof(process_entry));
	process_entry* swap_tmp = heap_alloc(sizeof(process_entry));
	if (!pivot || !swap_tmp) {
		heap_free(pivot);
		heap_free(swap_tmp);
		return;
	}
	int top = -1;
	int l = low, h = high;
	for (;;) {
		memcpy(pivot, &entries[l + (h - l) / 2], sizeof(process_entry));
		int i = l, j = h;
		while (i <= j) {
			while (compare_entries(&entries[i], pivot, field, descending) < 0) i++;
			while (compare_entries(&entries[j], pivot, field, descending) > 0) j--;
			if (i <= j) {
				swap(&entries[i], &entries[j], swap_tmp);
				i++;
				j--;
			}
		}
		BOOL left_smaller = (j - l) < (h - i);
		int next_low = 0, next_high = 0;
		BOOL have_next = FALSE;
		if (left_smaller) {
			if (l < j) { next_low = l; next_high = j; have_next = TRUE; }
			if (i < h) stack[++top] = (stack_entry){i, h};
		} else {
			if (i < h) { next_low = i; next_high = h; have_next = TRUE; }
			if (l < j) stack[++top] = (stack_entry){l, j};
		}
		if (have_next) {
			l = next_low;
			h = next_high;
		} else if (top >= 0) {
			stack_entry range = stack[top--];
			l = range.low;
			h = range.high;
		} else {
			break;
		}
	}
	heap_free(pivot);
	heap_free(swap_tmp);
}

static USHORT get_native_machine() {
	static USHORT native = 0;
	if (native) return native;
	PFN_IsWow64Process2 fn = (PFN_IsWow64Process2)GetProcAddress(GetModuleHandle(L"kernel32.dll"), "IsWow64Process2");
	if (fn) {
		USHORT proc_machine;
		fn(GetCurrentProcess(), &proc_machine, &native);
	} else {
		SYSTEM_INFO si;
		GetNativeSystemInfo(&si);
		switch (si.wProcessorArchitecture) {
		case PROCESSOR_ARCHITECTURE_AMD64:
			native = 0x8664;
			break;
		case PROCESSOR_ARCHITECTURE_ARM64:
			native = 0xAA64;
			break;
		default:
			native = 0x014c;
			break;
		}
	}
	return native;
}

static USHORT get_process_arch(DWORD pid) {
	static PFN_IsWow64Process2 fn = NULL;
	static BOOL fn_checked = FALSE;
	if (!fn_checked) {
		fn_checked = TRUE;
		fn = (PFN_IsWow64Process2)GetProcAddress(GetModuleHandle(L"kernel32.dll"), "IsWow64Process2");
	}
	if (pid == 0) return get_native_machine();
	HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (!h) return 0;
	USHORT arch = 0;
	if (fn) {
		USHORT proc_machine, native;
		if (fn(h, &proc_machine, &native))
			arch = (proc_machine == IMAGE_FILE_MACHINE_UNKNOWN) ? native : proc_machine;
	} else {
		BOOL is_wow64 = FALSE;
		IsWow64Process(h, &is_wow64);
		arch = is_wow64 ? 0x014c : get_native_machine();
	}
	CloseHandle(h);
	return arch;
}

static DWORD get_process_gui_resources(DWORD pid, DWORD flags) {
	if (pid == 0) return 0;
	HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (!h) return 0;
	DWORD count = GetGuiResources(h, flags);
	CloseHandle(h);
	return count;
}

typedef struct {
	DWORD integrity_level;
	int elevated;       /* -1 = unknown, 0 = no, 1 = yes */
	int virtualization; /* -1 = unknown, 0 = not allowed, 1 = disabled, 2 = enabled */
	int app_container;  /* -1 = unknown, 0 = no, 1 = yes */
	wchar_t user[64];
	wchar_t domain[64];
	wchar_t sid[128];
} token_info;

/* Everything here comes off one token, so open the process and its token once
 * rather than once per attribute. "Unknown" values mean the token was out of
 * reach, which is normal for protected processes and other users' processes. */
static void get_process_token_info(DWORD pid, token_info* ti) {
	ti->integrity_level = 0;
	ti->elevated = -1;
	ti->virtualization = -1;
	ti->app_container = -1;
	ti->user[0] = L'\0';
	ti->domain[0] = L'\0';
	ti->sid[0] = L'\0';
	if (pid == 0) {
		ti->integrity_level = 0x4000; /* SYSTEM */
		ti->elevated = 0;
		lstrcpyn(ti->user, L"SYSTEM", 64);
		return;
	}
	HANDLE hproc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (!hproc) return;
	HANDLE htok = NULL;
	BOOL opened = OpenProcessToken(hproc, TOKEN_QUERY, &htok);
	CloseHandle(hproc);
	if (!opened) return;
	DWORD needed = 0;
	GetTokenInformation(htok, TokenIntegrityLevel, NULL, 0, &needed);
	BYTE* buf = heap_alloc(needed);
	if (buf && GetTokenInformation(htok, TokenIntegrityLevel, buf, needed, &needed)) {
		TOKEN_MANDATORY_LABEL* tml = (TOKEN_MANDATORY_LABEL*)buf;
		DWORD sub_count = *GetSidSubAuthorityCount(tml->Label.Sid);
		ti->integrity_level = *GetSidSubAuthority(tml->Label.Sid, sub_count - 1);
	}
	heap_free(buf);
	TOKEN_ELEVATION elev = {0};
	if (GetTokenInformation(htok, TokenElevation, &elev, sizeof(elev), &needed))
		ti->elevated = elev.TokenIsElevated ? 1 : 0;
	DWORD allowed = 0, enabled = 0;
	if (GetTokenInformation(htok, TokenVirtualizationAllowed, &allowed, sizeof(allowed), &needed)) {
		if (!allowed)
			ti->virtualization = 0;
		else if (GetTokenInformation(htok, TokenVirtualizationEnabled, &enabled, sizeof(enabled), &needed))
			ti->virtualization = enabled ? 2 : 1;
	}
	DWORD is_container = 0;
	if (GetTokenInformation(htok, TokenIsAppContainer, &is_container, sizeof(is_container), &needed))
		ti->app_container = is_container ? 1 : 0;
	needed = 0;
	GetTokenInformation(htok, TokenUser, NULL, 0, &needed);
	BYTE* ubuf = heap_alloc(needed);
	if (ubuf && GetTokenInformation(htok, TokenUser, ubuf, needed, &needed)) {
		TOKEN_USER* tu = (TOKEN_USER*)ubuf;
		wchar_t name[64], domain[64];
		DWORD nlen = 64, dlen = 64;
		SID_NAME_USE use;
		if (LookupAccountSidW(NULL, tu->User.Sid, name, &nlen, domain, &dlen, &use)) {
			lstrcpyn(ti->user, name, 64);
			lstrcpyn(ti->domain, domain, 64);
		}
		LPWSTR sid_str = NULL;
		if (ConvertSidToStringSidW(tu->User.Sid, &sid_str)) {
			lstrcpyn(ti->sid, sid_str, 128);
			LocalFree(sid_str);
		}
	}
	heap_free(ubuf);
	CloseHandle(htok);
}

static void get_process_cmdline(DWORD pid, wchar_t* buf, int len) {
	buf[0] = L'\0';
	if (pid == 0) return;
	static PFN_NtQIP fn = NULL;
	if (!fn) fn = (PFN_NtQIP)GetProcAddress(GetModuleHandle(L"ntdll.dll"), "NtQueryInformationProcess");
	if (!fn) return;
	HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (!h) return;
	ULONG needed = 0;
	fn(h, 60, NULL, 0, &needed);
	if (needed == 0) needed = 1024;
	BYTE* cbuf = heap_alloc(needed);
	if (cbuf) {
		NTSTATUS st = fn(h, 60, cbuf, needed, NULL);
		if (NT_SUCCESS(st)) {
			UNICODE_STRING* us = (UNICODE_STRING*)cbuf;
			if (us->Buffer && us->Length > 0) {
				int wlen = us->Length / sizeof(wchar_t);
				if (wlen >= len) wlen = len - 1;
				memcpy(buf, us->Buffer, wlen * sizeof(wchar_t));
				buf[wlen] = L'\0';
			}
		}
		heap_free(cbuf);
	}
	CloseHandle(h);
}

static void get_process_version_info(DWORD pid, wchar_t* desc, int desc_len, wchar_t* company, int comp_len,
	wchar_t* file_ver, int file_ver_len, wchar_t* product_ver, int product_ver_len) {
	desc[0] = L'\0';
	company[0] = L'\0';
	file_ver[0] = L'\0';
	product_ver[0] = L'\0';
	wchar_t path[MAX_PATH];
	get_process_path(pid, path, MAX_PATH);
	if (!path[0]) return;
	DWORD dummy;
	DWORD size = GetFileVersionInfoSizeW(path, &dummy);
	if (size == 0) return;
	void* data = heap_alloc(size);
	if (data) {
		if (GetFileVersionInfoW(path, 0, size, data)) {
			struct {
				USHORT lang;
				USHORT codepage;
			}* translate;
			UINT tlen;
			if (VerQueryValueW(data, L"\\VarFileInfo\\Translation", (LPVOID*)&translate, &tlen) && tlen >= sizeof(*translate)) {
				wchar_t subblock[64];
				wchar_t* value;
				UINT vlen;
				wnsprintf(subblock, 64, L"\\StringFileInfo\\%04x%04x\\FileDescription", translate[0].lang, translate[0].codepage);
				if (VerQueryValueW(data, subblock, (LPVOID*)&value, &vlen)) lstrcpyn(desc, value, desc_len);
				wnsprintf(subblock, 64, L"\\StringFileInfo\\%04x%04x\\CompanyName", translate[0].lang, translate[0].codepage);
				if (VerQueryValueW(data, subblock, (LPVOID*)&value, &vlen)) lstrcpyn(company, value, comp_len);
				wnsprintf(subblock, 64, L"\\StringFileInfo\\%04x%04x\\FileVersion", translate[0].lang, translate[0].codepage);
				if (VerQueryValueW(data, subblock, (LPVOID*)&value, &vlen)) lstrcpyn(file_ver, value, file_ver_len);
				wnsprintf(subblock, 64, L"\\StringFileInfo\\%04x%04x\\ProductVersion", translate[0].lang, translate[0].codepage);
				if (VerQueryValueW(data, subblock, (LPVOID*)&value, &vlen)) lstrcpyn(product_ver, value, product_ver_len);
			}
		}
		heap_free(data);
	}
}

static void get_session_name(DWORD session_id, wchar_t* buf, int len) {
	buf[0] = L'\0';
	LPWSTR info = NULL;
	DWORD bytes = 0;
	if (WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, session_id, WTSWinStationName, &info, &bytes)) {
		if (info && info[0]) lstrcpyn(buf, info, len);
		WTSFreeMemory(info);
	}
}

static void get_package_name(DWORD pid, wchar_t* buf, int len) {
	buf[0] = L'\0';
	if (pid == 0) return;
	HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (!h) return;
	UINT32 length = 0;
	GetPackageFullName(h, &length, NULL);
	if (length > 0) {
		wchar_t* name = heap_alloc(length * sizeof(wchar_t));
		if (name) {
			if (GetPackageFullName(h, &length, name) == ERROR_SUCCESS)
				lstrcpyn(buf, name, len);
			heap_free(name);
		}
	}
	CloseHandle(h);
}

static tm_dpi_awareness get_process_dpi_awareness(DWORD pid) {
	typedef HRESULT(WINAPI * PFN_GPDA)(HANDLE, int*);
	static PFN_GPDA fn = NULL;
	static BOOL checked = FALSE;
	if (!checked) {
		HMODULE h = GetModuleHandle(L"shcore.dll");
		if (!h) h = LoadLibrary(L"shcore.dll");
		if (h) fn = (PFN_GPDA)GetProcAddress(h, "GetProcessDpiAwareness");
		checked = TRUE;
	}
	if (!fn) return TM_DPI_UNAWARE;
	HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (!h) return TM_DPI_UNAWARE;
	int awareness = 0;
	fn(h, &awareness);
	CloseHandle(h);
	return (tm_dpi_awareness)awareness;
}

process_entry* snapshot_processes(snapshot_entry* snapshots, int* out_count, sort_field field, BOOL descending) {
	build_service_map();
	build_window_map();
	refresh_gpu_stats();
	FILETIME sys_idle_ft, sys_kernel_ft, sys_user_ft;
	GetSystemTimes(&sys_idle_ft, &sys_kernel_ft, &sys_user_ft);
	ULARGE_INTEGER uli_k, uli_u;
	uli_k.LowPart = sys_kernel_ft.dwLowDateTime;
	uli_k.HighPart = sys_kernel_ft.dwHighDateTime;
	uli_u.LowPart = sys_user_ft.dwLowDateTime;
	uli_u.HighPart = sys_user_ft.dwHighDateTime;
	ULONGLONG sys_time = uli_k.QuadPart + uli_u.QuadPart;
	ULONGLONG tick_ms = GetTickCount64();
	FILETIME now_ft;
	GetSystemTimeAsFileTime(&now_ft);
	ULARGE_INTEGER uli_now;
	uli_now.LowPart = now_ft.dwLowDateTime;
	uli_now.HighPart = now_ft.dwHighDateTime;
	ULONGLONG now_ticks = uli_now.QuadPart;
	ULONG buf_size = 0;
	BYTE* buf = query_all_processes(&buf_size);
	if (!buf) return NULL;
	int capacity = 256;
	int count = 0;
	process_entry* entries = heap_alloc(capacity * sizeof(process_entry));
	snapshot_entry* old_snaps = heap_alloc(SNAPSHOT_CAPACITY * sizeof(snapshot_entry));
	memcpy(old_snaps, snapshots, SNAPSHOT_CAPACITY * sizeof(snapshot_entry));
	memset(snapshots, 0, SNAPSHOT_CAPACITY * sizeof(snapshot_entry));
	BYTE* p = buf;
	for (;;) {
		const SPI* spi = (const SPI*)p;
		DWORD pid = (DWORD)(ULONG_PTR)spi->UniqueProcessId;
		if (count >= capacity) {
			capacity *= 2;
			entries = (process_entry*)heap_realloc(entries, capacity * sizeof(process_entry));
		}
		process_entry* e = &entries[count++];
		e->pid = pid;
		e->parent_pid = (DWORD)(ULONG_PTR)spi->InheritedFromUniqueProcessId;
		e->cpu_percent = 0.0;
		e->working_set = spi->WorkingSetSize;
		e->private_working_set = (SIZE_T)spi->WorkingSetPrivateSize.QuadPart;
		e->shared_working_set = (e->working_set > e->private_working_set)
									? e->working_set - e->private_working_set
									: 0;
		e->paged_pool = spi->QuotaPagedPoolUsage;
		e->non_paged_pool = spi->QuotaNonPagedPoolUsage;
		e->threads = spi->NumberOfThreads;
		e->handles = spi->HandleCount;
		e->start_time = (pid == 0) ? 0 : (ULONGLONG)spi->CreateTime.QuadPart;
		e->elapsed_time = (e->start_time && now_ticks > e->start_time) ? now_ticks - e->start_time : 0;
		e->base_priority = spi->BasePriority;
		e->suspended = is_process_suspended(pid);
		e->private_bytes = spi->PagefileUsage;
		e->disk_io_rate = 0.0;
		e->io_read_rate = 0.0;
		e->io_write_rate = 0.0;
		e->io_other_rate = 0.0;
		e->page_faults_per_sec = 0.0;
		e->hard_faults_per_sec = 0.0;
		e->cycles_per_sec = 0.0;
		e->private_bytes_delta = 0;
		e->working_set_delta = 0;
		e->handle_delta = 0;
		e->thread_delta = 0;
		e->session_id = spi->SessionId;
		e->peak_working_set = spi->PeakWorkingSetSize;
		e->virtual_size = spi->VirtualSize;
		e->peak_virtual_size = spi->PeakVirtualSize;
		e->peak_private_bytes = spi->PeakPagefileUsage;
		e->peak_paged_pool = spi->QuotaPeakPagedPoolUsage;
		e->peak_non_paged_pool = spi->QuotaPeakNonPagedPoolUsage;
		e->peak_threads = spi->NumberOfThreadsHighWatermark;
		e->gdi_objects = get_process_gui_resources(pid, GR_GDIOBJECTS);
		e->user_objects = get_process_gui_resources(pid, GR_USEROBJECTS);
		token_info ti;
		get_process_token_info(pid, &ti);
		e->integrity_level = ti.integrity_level;
		e->elevated = ti.elevated;
		e->virtualization = ti.virtualization;
		e->app_container = ti.app_container;
		lstrcpyn(e->user, ti.user, 64);
		lstrcpyn(e->domain, ti.domain, 64);
		lstrcpyn(e->user_sid, ti.sid, 128);
		get_process_cmdline(pid, e->cmdline, 256);
		get_process_version_info(pid, e->description, 128, e->company, 128,
			e->file_version, 64, e->product_version, 64);
		get_services_for_pid(pid, e->services, 256);
		e->dpi_awareness = get_process_dpi_awareness(pid);
		e->arch_machine = get_process_arch(pid);
		get_gpu_stat(pid, &e->gpu_percent, &e->gpu_memory);
		get_process_path(pid, e->path, MAX_PATH);
		get_session_name(e->session_id, e->session_name, 64);
		get_package_name(pid, e->package_name, 256);
		get_window_title_for_pid(pid, e->window_title, 128);
		if (pid == 0) {
			lstrcpy(e->name, L"System Idle Process");
		} else if (spi->ImageName.Buffer && spi->ImageName.Length > 0) {
			int len = spi->ImageName.Length / sizeof(wchar_t);
			if (len > 63) len = 63;
			memcpy(e->name, spi->ImageName.Buffer, len * sizeof(wchar_t));
			e->name[len] = L'\0';
		} else {
			lstrcpy(e->name, L"(unknown)");
		}
		ULONGLONG proc_time = (ULONGLONG)spi->KernelTime.QuadPart + (ULONGLONG)spi->UserTime.QuadPart;
		e->cpu_time = proc_time;
		e->kernel_time = (ULONGLONG)spi->KernelTime.QuadPart;
		e->user_time = (ULONGLONG)spi->UserTime.QuadPart;
		e->total_page_faults = spi->PageFaultCount;
		ULONGLONG io_read = (ULONGLONG)spi->ReadTransferCount.QuadPart;
		ULONGLONG io_write = (ULONGLONG)spi->WriteTransferCount.QuadPart;
		ULONGLONG io_other = (ULONGLONG)spi->OtherTransferCount.QuadPart;
		ULONGLONG io_bytes = io_read + io_write + io_other;
		e->io_read_ops = (ULONGLONG)spi->ReadOperationCount.QuadPart;
		e->io_write_ops = (ULONGLONG)spi->WriteOperationCount.QuadPart;
		e->io_other_ops = (ULONGLONG)spi->OtherOperationCount.QuadPart;
		e->total_io_bytes = io_bytes;
		cpu_snapshot current_snap = {proc_time, sys_time, io_bytes, io_read, io_write, io_other,
			spi->PageFaultCount, spi->HardFaultCount, spi->CycleTime, e->private_bytes,
			e->working_set, e->handles, e->threads, tick_ms};
		update_snapshot(snapshots, pid, current_snap);
		cpu_snapshot* prev = find_snapshot(old_snaps, pid);
		if (prev) {
			e->private_bytes_delta = (LONGLONG)e->private_bytes - (LONGLONG)prev->private_bytes;
			e->working_set_delta = (LONGLONG)e->working_set - (LONGLONG)prev->working_set;
			e->handle_delta = (int)e->handles - (int)prev->handles;
			e->thread_delta = (int)e->threads - (int)prev->threads;
			ULONGLONG delta_proc = proc_time - prev->process_time;
			ULONGLONG delta_sys = sys_time - prev->system_time;
			if (delta_sys > 0) {
				double pct = (double)delta_proc / (double)delta_sys * 100.0;
				e->cpu_percent = pct < 0.0 ? 0.0 : pct > 100.0 ? 100.0
															   : pct;
			}
			ULONGLONG delta_ms = tick_ms - prev->tick_ms;
			if (delta_ms > 0) {
				ULONGLONG delta_io = io_bytes - prev->io_bytes;
				e->disk_io_rate = (double)delta_io * 1000.0 / (double)delta_ms;
				ULONGLONG delta_read = (io_read >= prev->io_read) ? io_read - prev->io_read : 0;
				e->io_read_rate = (double)delta_read * 1000.0 / (double)delta_ms;
				ULONGLONG delta_write = (io_write >= prev->io_write) ? io_write - prev->io_write : 0;
				e->io_write_rate = (double)delta_write * 1000.0 / (double)delta_ms;
				ULONGLONG delta_other = (io_other >= prev->io_other) ? io_other - prev->io_other : 0;
				e->io_other_rate = (double)delta_other * 1000.0 / (double)delta_ms;

				ULONGLONG delta_pf = (spi->PageFaultCount >= prev->page_fault_count)
										 ? spi->PageFaultCount - prev->page_fault_count
										 : 0;
				e->page_faults_per_sec = (double)delta_pf * 1000.0 / (double)delta_ms;
				ULONGLONG delta_hf = (spi->HardFaultCount >= prev->hard_fault_count)
										 ? spi->HardFaultCount - prev->hard_fault_count
										 : 0;
				e->hard_faults_per_sec = (double)delta_hf * 1000.0 / (double)delta_ms;
				ULONGLONG delta_cycles = (spi->CycleTime >= prev->cycle_time) ? spi->CycleTime - prev->cycle_time : 0;
				e->cycles_per_sec = (double)delta_cycles * 1000.0 / (double)delta_ms;
			}
		}
		if (spi->NextEntryOffset == 0) break;
		p += spi->NextEntryOffset;
	}
	heap_free(buf);
	heap_free(old_snaps);
	/* Resolve parent names now that every entry is known. A recycled PID can
	 * point at a process that started after its supposed child, in which case
	 * the real parent is gone rather than whatever now holds the PID. */
	for (int i = 0; i < count; i++) {
		entries[i].parent_name[0] = L'\0';
		DWORD ppid = entries[i].parent_pid;
		if (!ppid || ppid == entries[i].pid) continue;
		for (int j = 0; j < count; j++) {
			if (entries[j].pid != ppid) continue;
			if (entries[j].start_time <= entries[i].start_time)
				lstrcpyn(entries[i].parent_name, entries[j].name, 64);
			break;
		}
		if (!entries[i].parent_name[0]) lstrcpyn(entries[i].parent_name, L"(exited)", 64);
	}
	quicksort(entries, 0, count - 1, field, descending);
	*out_count = count;
	return entries;
}

void free_process_entries(process_entry* entries) {
	heap_free(entries);
}

void get_process_path(DWORD pid, wchar_t* path, DWORD size) {
	HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (!h) {
		path[0] = L'\0';
		return;
	}
	if (!QueryFullProcessImageName(h, 0, path, &size)) path[0] = L'\0';
	CloseHandle(h);
}

BOOL terminate_process(DWORD pid) {
	HANDLE h = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
	if (!h) return FALSE;
	BOOL success = TerminateProcess(h, 1);
	CloseHandle(h);
	return success;
}

BOOL is_process_suspended(DWORD pid) {
	for (int i = 0; i < g_suspended_count; i++)
		if (g_suspended_pids[i] == pid) return TRUE;
	return FALSE;
}

BOOL suspend_process(DWORD pid) {
	static PFN_NtProc fn = NULL;
	if (!fn) fn = (PFN_NtProc)GetProcAddress(GetModuleHandle(L"ntdll.dll"), "NtSuspendProcess");
	if (!fn) return FALSE;
	HANDLE h = OpenProcess(PROCESS_SUSPEND_RESUME, FALSE, pid);
	if (!h) return FALSE;
	BOOL ok = NT_SUCCESS(fn(h));
	CloseHandle(h);
	if (ok && g_suspended_count < SNAPSHOT_CAPACITY)
		g_suspended_pids[g_suspended_count++] = pid;
	return ok;
}

BOOL resume_process(DWORD pid) {
	static PFN_NtProc fn = NULL;
	if (!fn) fn = (PFN_NtProc)GetProcAddress(GetModuleHandle(L"ntdll.dll"), "NtResumeProcess");
	if (!fn) return FALSE;
	HANDLE h = OpenProcess(PROCESS_SUSPEND_RESUME, FALSE, pid);
	if (!h) return FALSE;
	BOOL ok = NT_SUCCESS(fn(h));
	CloseHandle(h);
	if (ok) {
		for (int i = 0; i < g_suspended_count; i++) {
			if (g_suspended_pids[i] == pid) {
				g_suspended_pids[i] = g_suspended_pids[--g_suspended_count];
				break;
			}
		}
	}
	return ok;
}

BOOL set_process_priority(DWORD pid, DWORD priority_class) {
	HANDLE h = OpenProcess(PROCESS_SET_INFORMATION, FALSE, pid);
	if (!h) return FALSE;
	BOOL success = SetPriorityClass(h, priority_class);
	CloseHandle(h);
	return success;
}
