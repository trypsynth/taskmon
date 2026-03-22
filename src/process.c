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
} SPI;

typedef NTSTATUS (NTAPI *PFN_NtQSI)(ULONG, PVOID, ULONG, PULONG);

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

process_entry* snapshot_processes(snapshot_entry* snapshots, int* out_count, sort_field field, BOOL descending) {
	FILETIME sys_idle_ft, sys_kernel_ft, sys_user_ft;
	GetSystemTimes(&sys_idle_ft, &sys_kernel_ft, &sys_user_ft);
	ULARGE_INTEGER uli_k, uli_u;
	uli_k.LowPart = sys_kernel_ft.dwLowDateTime; uli_k.HighPart = sys_kernel_ft.dwHighDateTime;
	uli_u.LowPart = sys_user_ft.dwLowDateTime; uli_u.HighPart = sys_user_ft.dwHighDateTime;
	ULONGLONG sys_time = uli_k.QuadPart + uli_u.QuadPart;
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
		cpu_snapshot current_snap = { proc_time, sys_time };
		update_snapshot(snapshots, pid, current_snap);
		cpu_snapshot* prev = find_snapshot(old_snaps, pid);
		if (prev) {
			ULONGLONG delta_proc = proc_time - prev->process_time;
			ULONGLONG delta_sys = sys_time - prev->system_time;
			if (delta_sys > 0) {
				double pct = (double)delta_proc / (double)delta_sys * 100.0;
				e->cpu_percent = pct < 0.0 ? 0.0 : pct > 100.0 ? 100.0 : pct;
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
