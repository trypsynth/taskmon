#pragma once
#include <string>
#include <unordered_map>
#include <vector>
#include <windows.h>

enum class sort_field {
	name,
	pid,
	cpu,
	memory,
};

struct process_entry {
	DWORD pid;
	std::wstring name;
	double cpu_percent;
	SIZE_T working_set;
};

struct cpu_snapshot {
	ULONGLONG process_time;
	ULONGLONG system_time;
};

std::vector<process_entry> snapshot_processes(std::unordered_map<DWORD, cpu_snapshot>& prev_snapshots, sort_field sort_by, bool descending = false);
