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
	SORT_FIELD_DESCRIPTION,
	SORT_FIELD_COMPANY,
	SORT_FIELD_DPI,
	SORT_FIELD_SERVICE,
	SORT_FIELD_GPU,
	SORT_FIELD_GPU_MEMORY,
	SORT_FIELD_CPU_TIME,
	SORT_FIELD_ELEVATED,
	SORT_FIELD_PATH,
	SORT_FIELD_WINDOW_TITLE,
	SORT_FIELD_FILE_VERSION,
	SORT_FIELD_PRODUCT_VERSION,
	SORT_FIELD_SESSION_NAME,
	SORT_FIELD_PACKAGE_NAME,
	SORT_FIELD_PEAK_VIRTUAL_MEM,
	SORT_FIELD_PEAK_PRIVATE_BYTES,
	SORT_FIELD_PEAK_PAGED_POOL,
	SORT_FIELD_PEAK_NONPAGED_POOL,
	SORT_FIELD_PEAK_THREADS,
	SORT_FIELD_HARD_FAULTS,
	SORT_FIELD_CYCLES,
	SORT_FIELD_KERNEL_TIME,
	SORT_FIELD_USER_TIME,
	SORT_FIELD_TOTAL_PAGE_FAULTS,
	SORT_FIELD_IO_READ_OPS,
	SORT_FIELD_IO_WRITE_OPS,
	SORT_FIELD_IO_OTHER_OPS,
	SORT_FIELD_TOTAL_IO,
	SORT_FIELD_ELAPSED,
	SORT_FIELD_SHARED_WS,
	SORT_FIELD_PARENT_NAME,
	SORT_FIELD_COUNT,
} sort_field;

typedef enum {
	TM_DPI_UNAWARE = 0,
	TM_DPI_SYSTEM_AWARE = 1,
	TM_DPI_PER_MONITOR_AWARE = 2
} tm_dpi_awareness;

typedef struct {
	DWORD pid;
	DWORD parent_pid;
	wchar_t name[64];
	wchar_t description[128];
	wchar_t company[128];
	tm_dpi_awareness dpi_awareness;
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
	wchar_t services[256];
	USHORT arch_machine;
	DWORD session_id;
	SIZE_T peak_working_set;
	SIZE_T virtual_size;
	DWORD gdi_objects;
	DWORD user_objects;
	DWORD integrity_level;
	double gpu_percent;
	ULONGLONG gpu_memory;
	ULONGLONG cpu_time;
	int elevated; /* -1 = unknown, 0 = no, 1 = yes */
	wchar_t path[MAX_PATH];
	wchar_t window_title[128];
	wchar_t file_version[64];
	wchar_t product_version[64];
	wchar_t session_name[64];
	wchar_t package_name[256];
	SIZE_T peak_virtual_size;
	SIZE_T peak_private_bytes;
	SIZE_T peak_paged_pool;
	SIZE_T peak_non_paged_pool;
	DWORD peak_threads;
	double hard_faults_per_sec;
	double cycles_per_sec;
	ULONGLONG kernel_time;
	ULONGLONG user_time;
	ULONG total_page_faults;
	ULONGLONG io_read_ops;
	ULONGLONG io_write_ops;
	ULONGLONG io_other_ops;
	ULONGLONG total_io_bytes;
	ULONGLONG elapsed_time;
	SIZE_T shared_working_set;
	wchar_t parent_name[64];
} process_entry;

typedef struct {
	ULONGLONG process_time;
	ULONGLONG system_time;
	ULONGLONG io_bytes;
	ULONGLONG io_read;
	ULONGLONG io_write;
	ULONGLONG io_other;
	ULONG page_fault_count;
	ULONG hard_fault_count;
	ULONGLONG cycle_time;
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
void gpu_cleanup(void);
