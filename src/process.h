#pragma once
#include <windows.h>

typedef enum {
	SORT_FIELD_NAME,
	SORT_FIELD_PID,
	SORT_FIELD_CPU,
	SORT_FIELD_MEMORY,
	SORT_FIELD_THREADS,
	SORT_FIELD_HANDLES,
	SORT_FIELD_STARTTIME,
	SORT_FIELD_PRIORITY,
	SORT_FIELD_DISK_IO,
	SORT_FIELD_PRIVATE_BYTES,
	SORT_FIELD_PAGE_FAULTS,
	SORT_FIELD_USER,
	SORT_FIELD_CMDLINE,
	SORT_FIELD_ARCH,
	SORT_FIELD_SESSION,
	SORT_FIELD_PEAK_WORKING_SET,
	SORT_FIELD_VIRTUAL_MEM,
	SORT_FIELD_GDI_OBJECTS,
	SORT_FIELD_USER_OBJECTS,
	SORT_FIELD_INTEGRITY,
	SORT_FIELD_PPID,
	SORT_FIELD_PRIVATE_WS,
	SORT_FIELD_PAGED_POOL,
	SORT_FIELD_NONPAGED_POOL,
	SORT_FIELD_IO_READ,
	SORT_FIELD_IO_WRITE,
	SORT_FIELD_IO_OTHER,
	SORT_FIELD_COUNT,
} sort_field;

typedef struct {
	DWORD pid;
	DWORD parent_pid;
	wchar_t name[64];
	double cpu_percent;
	SIZE_T working_set;
	SIZE_T private_working_set;
	SIZE_T paged_pool;
	SIZE_T non_paged_pool;
	DWORD threads;
	DWORD handles;
	ULONGLONG start_time;
	int base_priority;
	BOOL suspended;
	double disk_io_rate;
	double io_read_rate;
	double io_write_rate;
	double io_other_rate;
	SIZE_T private_bytes;
	double page_faults_per_sec;
	wchar_t user[64];
	wchar_t cmdline[256];
	USHORT arch_machine;
	DWORD session_id;
	SIZE_T peak_working_set;
	SIZE_T virtual_size;
	DWORD gdi_objects;
	DWORD user_objects;
	DWORD integrity_level;
} process_entry;

typedef struct {
	ULONGLONG process_time;
	ULONGLONG system_time;
	ULONGLONG io_bytes;
	ULONGLONG io_read;
	ULONGLONG io_write;
	ULONGLONG io_other;
	ULONG page_fault_count;
	ULONGLONG tick_ms;
} cpu_snapshot;

typedef struct {
	DWORD pid;
	cpu_snapshot snapshot;
	BOOL active;
} snapshot_entry;

#define SNAPSHOT_CAPACITY 1024

process_entry* snapshot_processes(snapshot_entry* snapshots, int* count, sort_field field, BOOL descending);
void free_process_entries(process_entry* entries);
void get_process_path(DWORD pid, wchar_t* path, DWORD size);
BOOL terminate_process(DWORD pid);
BOOL set_process_priority(DWORD pid, DWORD priority_class);
BOOL is_process_suspended(DWORD pid);
BOOL suspend_process(DWORD pid);
BOOL resume_process(DWORD pid);
