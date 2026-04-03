#include "process.h"
#include <winternl.h>
#include <shlwapi.h>

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

typedef NTSTATUS (NTAPI *PFN_NtQSI)(ULONG, PVOID, ULONG, PULONG);
typedef NTSTATUS (NTAPI *PFN_NtProc)(HANDLE);
typedef NTSTATUS (NTAPI *PFN_NtQIP)(HANDLE, DWORD, PVOID, ULONG, PULONG);
typedef BOOL (WINAPI *PFN_IsWow64Process2)(HANDLE, USHORT*, USHORT*);

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

static BYTE* query_all_processes(ULONG* total_size) {
	static PFN_NtQSI fn = NULL;
	if (!fn) fn = (PFN_NtQSI)GetProcAddress(GetModuleHandle(L"ntdll.dll"), "NtQuerySystemInformation");
	if (!fn) return NULL;
	ULONG size = 512 * 1024;
	for (;;) {
		BYTE* buf = (BYTE*)heap_alloc(size);
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

static void swap(process_entry* a, process_entry* b) {
	process_entry temp = *a;
	*a = *b;
	*b = temp;
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
	default:
		break;
	}
	return descending ? -res : res;
}

static void quicksort(process_entry* entries, int low, int high, sort_field field, BOOL descending) {
	if (low < high) {
		process_entry pivot = entries[high];
		int i = low - 1;
		for (int j = low; j < high; j++) {
			if (compare_entries(&entries[j], &pivot, field, descending) <= 0) {
				i++;
				swap(&entries[i], &entries[j]);
			}
		}
		swap(&entries[i + 1], &entries[high]);
		int p = i + 1;
		quicksort(entries, low, p - 1, field, descending);
		quicksort(entries, p + 1, high, field, descending);
	}
}

static USHORT get_native_machine(void) {
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

static void get_process_user(DWORD pid, wchar_t* buf, int len) {
	buf[0] = L'\0';
	if (pid == 0) {
		lstrcpyn(buf, L"SYSTEM", len);
		return; 
	}
	HANDLE hproc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
	if (!hproc) return;
	HANDLE htok = NULL;
	if (!OpenProcessToken(hproc, TOKEN_QUERY, &htok)) {
		CloseHandle(hproc);
		return;
	}
	CloseHandle(hproc);
	DWORD needed = 0;
	GetTokenInformation(htok, TokenUser, NULL, 0, &needed);
	BYTE* ubuf = (BYTE*)heap_alloc(needed);
	if (ubuf && GetTokenInformation(htok, TokenUser, ubuf, needed, &needed)) {
		TOKEN_USER* tu = (TOKEN_USER*)ubuf;
		wchar_t name[64], domain[64];
		DWORD nlen = 64, dlen = 64;
		SID_NAME_USE use;
		if (LookupAccountSidW(NULL, tu->User.Sid, name, &nlen, domain, &dlen, &use)) lstrcpyn(buf, name, len);
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
	BYTE* cbuf = (BYTE*)heap_alloc(needed);
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

process_entry* snapshot_processes(snapshot_entry* snapshots, int* out_count, sort_field field, BOOL descending) {
	FILETIME sys_idle_ft, sys_kernel_ft, sys_user_ft;
	GetSystemTimes(&sys_idle_ft, &sys_kernel_ft, &sys_user_ft);
	ULARGE_INTEGER uli_k, uli_u;
	uli_k.LowPart = sys_kernel_ft.dwLowDateTime; uli_k.HighPart = sys_kernel_ft.dwHighDateTime;
	uli_u.LowPart = sys_user_ft.dwLowDateTime; uli_u.HighPart = sys_user_ft.dwHighDateTime;
	ULONGLONG sys_time = uli_k.QuadPart + uli_u.QuadPart;
	ULONGLONG tick_ms = GetTickCount64();
	ULONG buf_size = 0;
	BYTE* buf = query_all_processes(&buf_size);
	if (!buf) return NULL;
	int capacity = 256;
	int count = 0;
	process_entry* entries = (process_entry*)heap_alloc(capacity * sizeof(process_entry));
	snapshot_entry* old_snaps = (snapshot_entry*)heap_alloc(SNAPSHOT_CAPACITY * sizeof(snapshot_entry));
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
		e->cpu_percent = 0.0;
		e->working_set = spi->WorkingSetSize;
		e->threads = spi->NumberOfThreads;
		e->handles = spi->HandleCount;
		e->start_time = (pid == 0) ? 0 : (ULONGLONG)spi->CreateTime.QuadPart;
		e->base_priority = spi->BasePriority;
		e->suspended = is_process_suspended(pid);
		e->private_bytes = spi->PagefileUsage;
		e->disk_io_rate = 0.0;
		e->page_faults_per_sec = 0.0;
		e->session_id = spi->SessionId;
		e->peak_working_set = spi->PeakWorkingSetSize;
		e->virtual_size = spi->VirtualSize;
		get_process_user(pid, e->user, 64);
		get_process_cmdline(pid, e->cmdline, 256);
		e->arch_machine = get_process_arch(pid);
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
		ULONGLONG io_bytes = (ULONGLONG)spi->ReadTransferCount.QuadPart + (ULONGLONG)spi->WriteTransferCount.QuadPart;
		cpu_snapshot current_snap = { proc_time, sys_time, io_bytes, spi->PageFaultCount, tick_ms };
		update_snapshot(snapshots, pid, current_snap);
		cpu_snapshot* prev = find_snapshot(old_snaps, pid);
		if (prev) {
			ULONGLONG delta_proc = proc_time - prev->process_time;
			ULONGLONG delta_sys = sys_time - prev->system_time;
			if (delta_sys > 0) {
				double pct = (double)delta_proc / (double)delta_sys * 100.0;
				e->cpu_percent = pct < 0.0 ? 0.0 : pct > 100.0 ? 100.0 : pct;
			}
			ULONGLONG delta_ms = tick_ms - prev->tick_ms;
			if (delta_ms > 0) {
				ULONGLONG delta_io = io_bytes - prev->io_bytes;
				e->disk_io_rate = (double)delta_io * 1000.0 / (double)delta_ms;
				ULONGLONG delta_pf = (spi->PageFaultCount >= prev->page_fault_count)
					? spi->PageFaultCount - prev->page_fault_count : 0;
				e->page_faults_per_sec = (double)delta_pf * 1000.0 / (double)delta_ms;
			}
		}
		if (spi->NextEntryOffset == 0) break;
		p += spi->NextEntryOffset;
	}
	heap_free(buf);
	heap_free(old_snaps);
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
