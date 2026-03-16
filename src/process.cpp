#include <algorithm>
#include "process.hpp"
#include <ranges>
#include <vector>
#include <windows.h>
#include <winternl.h>

#define SystemProcessInformation 5
#define STATUS_INFO_LENGTH_MISMATCH 0xC0000004L

// Maps hidden SYSTEM_PROCESS_INFORMATION fields (Kernel/UserTime) obscured by winternl.h's Reserved1[48] for direct access; stable since Vista.
struct SPI {
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
	// 4 bytes implicit padding on x64 (HANDLE needs 8-byte alignment)
	HANDLE UniqueProcessId;
	HANDLE InheritedFromUniqueProcessId;
	ULONG HandleCount;
	ULONG SessionId;
	ULONG_PTR UniqueProcessKey;
	SIZE_T PeakVirtualSize;
	SIZE_T VirtualSize;
	ULONG PageFaultCount;
	// 4 bytes implicit padding on x64 (SIZE_T needs 8-byte alignment)
	SIZE_T PeakWorkingSetSize;
	SIZE_T WorkingSetSize;
};

#ifdef _WIN64
static_assert(offsetof(SPI, KernelTime) == 0x30, "SPI layout mismatch");
static_assert(offsetof(SPI, ImageName) == 0x38, "SPI layout mismatch");
static_assert(offsetof(SPI, UniqueProcessId) == 0x50, "SPI layout mismatch");
static_assert(offsetof(SPI, WorkingSetSize) == 0x90, "SPI layout mismatch");
#endif

using PFN_NtQSI = NTSTATUS(NTAPI*)(ULONG, PVOID, ULONG, PULONG);

static std::vector<BYTE> query_all_processes() {
	static PFN_NtQSI fn = reinterpret_cast<PFN_NtQSI>(GetProcAddress(GetModuleHandle(L"ntdll.dll"), "NtQuerySystemInformation"));
	if (!fn) return {};
	ULONG size = 512 * 1024;
	for (;;) {
		std::vector<BYTE> buf(size);
		ULONG returned = 0;
		NTSTATUS st = fn(SystemProcessInformation, buf.data(), size, &returned);
		if (st == 0) {
			buf.resize(returned ? returned : size);
			return buf;
		}
		if (st == (NTSTATUS)STATUS_INFO_LENGTH_MISMATCH) {
			size = returned ? returned + 65536 : size * 2;
			continue;
		}
		return {};
	}
}

std::vector<process_entry> snapshot_processes(std::unordered_map<DWORD, cpu_snapshot>& prev_snapshots, sort_field sort_field, bool descending) {
	FILETIME sys_idle_ft{}, sys_kernel_ft{}, sys_user_ft{};
	GetSystemTimes(&sys_idle_ft, &sys_kernel_ft, &sys_user_ft);
	ULARGE_INTEGER uli_k, uli_u;
	uli_k.LowPart = sys_kernel_ft.dwLowDateTime;
	uli_k.HighPart = sys_kernel_ft.dwHighDateTime;
	uli_u.LowPart = sys_user_ft.dwLowDateTime;
	uli_u.HighPart = sys_user_ft.dwHighDateTime;
	ULONGLONG sys_time = uli_k.QuadPart + uli_u.QuadPart;
	auto buf = query_all_processes();
	if (buf.empty()) return {};
	std::vector<process_entry> entries;
	std::unordered_map<DWORD, cpu_snapshot> new_snapshots;
	const BYTE* p = buf.data();
	for (;;) {
		const auto* spi = reinterpret_cast<const SPI*>(p);
		DWORD pid = static_cast<DWORD>(reinterpret_cast<ULONG_PTR>(spi->UniqueProcessId));
		process_entry entry{};
		entry.pid = pid;
		entry.cpu_percent = 0.0;
		entry.working_set = spi->WorkingSetSize;
		if (pid == 0) entry.name = L"System Idle Process";
		else if (spi->ImageName.Buffer && spi->ImageName.Length > 0) entry.name = std::wstring(spi->ImageName.Buffer, spi->ImageName.Length / sizeof(wchar_t));
		else entry.name = L"(unknown)";
		ULONGLONG proc_time = static_cast<ULONGLONG>(spi->KernelTime.QuadPart) + static_cast<ULONGLONG>(spi->UserTime.QuadPart);
		new_snapshots[pid] = { proc_time, sys_time };
		auto it = prev_snapshots.find(pid);
		if (it != prev_snapshots.end()) {
			ULONGLONG delta_proc = proc_time - it->second.process_time;
			ULONGLONG delta_sys = sys_time - it->second.system_time;
			if (delta_sys > 0) {
				double pct = static_cast<double>(delta_proc) / static_cast<double>(delta_sys) * 100.0;
				entry.cpu_percent = pct < 0.0 ? 0.0 : pct > 100.0 ? 100.0 : pct;
			}
		}
		entries.push_back(std::move(entry));
		if (spi->NextEntryOffset == 0) break;
		p += spi->NextEntryOffset;
	}
	prev_snapshots = std::move(new_snapshots);
	auto cmp = [&](const process_entry& a, const process_entry& b) -> bool {
		bool less_than = false;
		switch (sort_field) {
		case sort_field::name:
			less_than = _wcsicmp(a.name.c_str(), b.name.c_str()) < 0;
			break;
		case sort_field::pid:
			less_than = a.pid < b.pid;
			break;
		case sort_field::cpu:
			less_than = a.cpu_percent < b.cpu_percent;
			break;
		case sort_field::memory:
			less_than = a.working_set < b.working_set;
			break;
		}
		return descending ? !less_than : less_than;
	};
	std::ranges::sort(entries, cmp);
	return entries;
}
