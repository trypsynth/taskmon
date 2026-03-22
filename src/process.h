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
	SORT_FIELD_COUNT,
} sort_field;

typedef struct {
	DWORD pid;
	wchar_t name[64];
	double cpu_percent;
	SIZE_T working_set;
	DWORD threads;
	DWORD handles;
	ULONGLONG start_time;
} process_entry;

typedef struct {
	ULONGLONG process_time;
	ULONGLONG system_time;
} cpu_snapshot;

typedef struct {
	DWORD pid;
	cpu_snapshot snapshot;
	BOOL active;
} snapshot_entry;

#define SNAPSHOT_CAPACITY 1024

process_entry* snapshot_processes(snapshot_entry* snapshots, int* count, sort_field field, BOOL descending);
void free_process_entries(process_entry* entries);
void sort_process_entries(process_entry* entries, int count, sort_field field, BOOL descending);
void get_process_path(DWORD pid, wchar_t* path, DWORD size);
BOOL terminate_process(DWORD pid);
