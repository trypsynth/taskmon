const std = @import("std");
const win32 = @import("win32.zig");
const pt = @import("process_types.zig");
const settings = @import("settings.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

fn asFn(comptime T: type, ptr: ?*anyopaque) ?T {
	const p = ptr orelse return null;
	return @ptrFromInt(@intFromPtr(p));
}

fn heapAlloc(size: usize) ?*anyopaque {
	return win32.HeapAlloc(win32.GetProcessHeap(), win32.HEAP_ZERO_MEMORY, size);
}
fn heapRealloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
	return win32.HeapReAlloc(win32.GetProcessHeap(), win32.HEAP_ZERO_MEMORY, ptr, size);
}
fn heapFree(ptr: ?*anyopaque) void {
	_ = win32.HeapFree(win32.GetProcessHeap(), 0, ptr);
}

// Undocumented; hand mirrored from process.c's own local SPI struct (not from
// any SDK header). Must stay byte-for-byte layout compatible with it.
const UNICODE_STRING = extern struct {
	Length: u16,
	MaximumLength: u16,
	Buffer: ?[*]align(1) u16,
};

const SystemProcessInformation = extern struct {
	NextEntryOffset: u32,
	NumberOfThreads: u32,
	WorkingSetPrivateSize: i64,
	HardFaultCount: u32,
	NumberOfThreadsHighWatermark: u32,
	CycleTime: u64,
	CreateTime: i64,
	UserTime: i64,
	KernelTime: i64,
	ImageName: UNICODE_STRING,
	BasePriority: i32,
	UniqueProcessId: ?*anyopaque,
	InheritedFromUniqueProcessId: ?*anyopaque,
	HandleCount: u32,
	SessionId: u32,
	UniqueProcessKey: usize,
	PeakVirtualSize: usize,
	VirtualSize: usize,
	PageFaultCount: u32,
	PeakWorkingSetSize: usize,
	WorkingSetSize: usize,
	QuotaPeakPagedPoolUsage: usize,
	QuotaPagedPoolUsage: usize,
	QuotaPeakNonPagedPoolUsage: usize,
	QuotaNonPagedPoolUsage: usize,
	PagefileUsage: usize,
	PeakPagefileUsage: usize,
	PrivatePageCount: usize,
	ReadOperationCount: i64,
	WriteOperationCount: i64,
	OtherOperationCount: i64,
	ReadTransferCount: i64,
	WriteTransferCount: i64,
	OtherTransferCount: i64,
};

const SYSTEM_PROCESS_INFORMATION_CLASS: win32.ULONG = 5;
const STATUS_INFO_LENGTH_MISMATCH: i32 = @bitCast(@as(u32, 0xC0000004));

const FnNtQSI = *const fn (win32.ULONG, ?*anyopaque, win32.ULONG, ?*win32.ULONG) callconv(.c) i32;
const FnNtProc = *const fn (win32.HANDLE) callconv(.c) i32;
const FnNtQIP = *const fn (win32.HANDLE, win32.DWORD, ?*anyopaque, win32.ULONG, ?*win32.ULONG) callconv(.c) i32;
const FnIsWow64Process2 = *const fn (win32.HANDLE, *win32.USHORT, *win32.USHORT) callconv(.c) win32.BOOL;

var g_suspended_pids: [pt.SNAPSHOT_CAPACITY]win32.DWORD = std.mem.zeroes([pt.SNAPSHOT_CAPACITY]win32.DWORD);
var g_suspended_count: i32 = 0;

var g_pdh_query: win32.PDH_HQUERY = null;
var g_pdh_util: win32.PDH_HCOUNTER = null;
var g_pdh_mem_dedicated: win32.PDH_HCOUNTER = null;
var g_pdh_mem_shared: win32.PDH_HCOUNTER = null;
var g_pdh_ready: bool = false;
var g_pdh_init_attempted: bool = false;

const GpuStatEntry = extern struct {
	pid: win32.DWORD,
	gpu_percent: f64,
	gpu_memory: u64,
	active: win32.BOOL,
};
var g_gpu_stats: [pt.SNAPSHOT_CAPACITY]GpuStatEntry = std.mem.zeroes([pt.SNAPSHOT_CAPACITY]GpuStatEntry);

fn initGpuCounters() void {
	g_pdh_init_attempted = true;
	if (win32.PdhOpenQueryW(null, 0, &g_pdh_query) != 0) return;
	const ok1 = win32.PdhAddEnglishCounterW(g_pdh_query, L("\\GPU Engine(*)\\Utilization Percentage"), 0, &g_pdh_util) == 0;
	const ok2 = win32.PdhAddEnglishCounterW(g_pdh_query, L("\\GPU Process Memory(*)\\Dedicated Usage"), 0, &g_pdh_mem_dedicated) == 0;
	const ok3 = win32.PdhAddEnglishCounterW(g_pdh_query, L("\\GPU Process Memory(*)\\Shared Usage"), 0, &g_pdh_mem_shared) == 0;
	if (!(ok1 and ok2 and ok3)) {
		_ = win32.PdhCloseQuery(g_pdh_query);
		g_pdh_query = null;
		return;
	}
	g_pdh_ready = true;
}

pub export fn gpu_cleanup() callconv(.c) void {
	if (g_pdh_query != null) {
		_ = win32.PdhCloseQuery(g_pdh_query);
		g_pdh_query = null;
	}
	g_pdh_ready = false;
}

fn addGpuStat(pid: win32.DWORD, percent: f64, memory: u64) void {
	const h: usize = pid % pt.SNAPSHOT_CAPACITY;
	var i = h;
	while (true) {
		if (g_gpu_stats[i].active == 0 or g_gpu_stats[i].pid == pid) {
			g_gpu_stats[i].active = 1;
			g_gpu_stats[i].pid = pid;
			g_gpu_stats[i].gpu_percent += percent;
			g_gpu_stats[i].gpu_memory += memory;
			return;
		}
		i = (i + 1) % pt.SNAPSHOT_CAPACITY;
		if (i == h) break;
	}
}

fn getGpuStat(pid: win32.DWORD, out_percent: *f64, out_memory: *u64) void {
	out_percent.* = 0.0;
	out_memory.* = 0;
	const h: usize = pid % pt.SNAPSHOT_CAPACITY;
	var i = h;
	while (true) {
		if (g_gpu_stats[i].active == 0) return;
		if (g_gpu_stats[i].pid == pid) {
			out_percent.* = g_gpu_stats[i].gpu_percent;
			out_memory.* = g_gpu_stats[i].gpu_memory;
			return;
		}
		i = (i + 1) % pt.SNAPSHOT_CAPACITY;
		if (i == h) break;
	}
}

// Instance names look like "pid_1234_luid_0x00000000_0x0000abcd_phys_0_eng_0_engtype_3D".
fn parsePidFromInstance(name: [*:0]align(1) const u16) win32.DWORD {
	const prefix = [_]u16{ 'p', 'i', 'd', '_' };
	var i: usize = 0;
	while (i < prefix.len) : (i += 1) {
		if (name[i] != prefix[i]) return 0;
	}
	if (name[i] < '0' or name[i] > '9') return 0;
	var pid: win32.DWORD = 0;
	while (name[i] >= '0' and name[i] <= '9') : (i += 1) {
		pid = pid * 10 + (name[i] - '0');
	}
	return pid;
}

fn accumulateCounterArray(counter: win32.PDH_HCOUNTER, format: win32.DWORD, is_percent: bool) void {
	var buf_size: win32.DWORD = 0;
	var item_count: win32.DWORD = 0;
	var st = win32.PdhGetFormattedCounterArrayW(counter, format, &buf_size, &item_count, null);
	if (st != win32.PDH_MORE_DATA or buf_size == 0) return;
	const items_raw = heapAlloc(buf_size) orelse return;
	const items: [*]win32.PDH_FMT_COUNTERVALUE_ITEM_W = @ptrCast(@alignCast(items_raw));
	st = win32.PdhGetFormattedCounterArrayW(counter, format, &buf_size, &item_count, items);
	if (st == 0) {
		var i: win32.DWORD = 0;
		while (i < item_count) : (i += 1) {
			const name = items[i].szName orelse continue;
			const pid = parsePidFromInstance(name);
			if (pid == 0) continue;
			if (is_percent) addGpuStat(pid, items[i].FmtValue.value.doubleValue, 0) else addGpuStat(pid, 0.0, @intCast(items[i].FmtValue.value.largeValue));
		}
	}
	heapFree(items_raw);
}

fn refreshGpuStats() void {
	if (!g_pdh_init_attempted) initGpuCounters();
	g_gpu_stats = std.mem.zeroes(@TypeOf(g_gpu_stats));
	if (!g_pdh_ready) return;
	if (win32.PdhCollectQueryData(g_pdh_query) != 0) return;
	accumulateCounterArray(g_pdh_util, win32.PDH_FMT_DOUBLE, true);
	accumulateCounterArray(g_pdh_mem_dedicated, win32.PDH_FMT_LARGE, false);
	accumulateCounterArray(g_pdh_mem_shared, win32.PDH_FMT_LARGE, false);
}

const SvcEntry = extern struct {
	pid: win32.DWORD,
	name: [64]u16,
};
var g_svc_map: ?[*]SvcEntry = null;
var g_svc_count: i32 = 0;

fn buildServiceMap() void {
	heapFree(@ptrCast(g_svc_map));
	g_svc_map = null;
	g_svc_count = 0;
	const hscm = win32.OpenSCManagerW(null, null, win32.SC_MANAGER_ENUMERATE_SERVICE);
	if (hscm == null) return;
	var needed: win32.DWORD = 0;
	var count: win32.DWORD = 0;
	var resume_handle: win32.DWORD = 0;
	_ = win32.EnumServicesStatusExW(hscm, win32.SC_ENUM_PROCESS_INFO, win32.SERVICE_WIN32, win32.SERVICE_STATE_ALL, null, 0, &needed, &count, &resume_handle, null);
	if (needed == 0) {
		_ = win32.CloseServiceHandle(hscm);
		return;
	}
	const buf_raw = heapAlloc(needed) orelse {
		_ = win32.CloseServiceHandle(hscm);
		return;
	};
	const buf: [*]u8 = @ptrCast(buf_raw);
	resume_handle = 0;
	if (win32.EnumServicesStatusExW(hscm, win32.SC_ENUM_PROCESS_INFO, win32.SERVICE_WIN32, win32.SERVICE_STATE_ALL, buf, needed, &needed, &count, &resume_handle, null) != 0) {
		if (heapAlloc(@as(usize, count) * @sizeOf(SvcEntry))) |map_raw| {
			const map: [*]SvcEntry = @ptrCast(@alignCast(map_raw));
			g_svc_map = map;
			const sv: [*]win32.ENUM_SERVICE_STATUS_PROCESSW = @ptrCast(@alignCast(buf));
			var i: win32.DWORD = 0;
			while (i < count) : (i += 1) {
				const pid = sv[i].ServiceStatusProcess.dwProcessId;
				if (pid == 0) continue;
				const idx: usize = @intCast(g_svc_count);
				map[idx].pid = pid;
				_ = win32.lstrcpynW(@ptrCast(&map[idx].name), sv[i].lpServiceName.?, 64);
				g_svc_count += 1;
			}
		}
	}
	heapFree(buf);
	_ = win32.CloseServiceHandle(hscm);
}

fn getServicesForPid(pid: win32.DWORD, buf: [*:0]u16, len: i32) void {
	buf[0] = 0;
	const map = g_svc_map orelse return;
	if (pid == 0) return;
	var pos: i32 = 0;
	var i: i32 = 0;
	while (i < g_svc_count and pos < len - 1) : (i += 1) {
		if (map[@intCast(i)].pid != pid) continue;
		if (pos > 0 and pos + 2 < len) {
			buf[@intCast(pos)] = ';';
			pos += 1;
			buf[@intCast(pos)] = ' ';
			pos += 1;
		}
		var nlen: i32 = win32.lstrlenW(@ptrCast(&map[@intCast(i)].name));
		if (pos + nlen >= len) nlen = len - pos - 1;
		if (nlen > 0) {
			const src: [*]const u16 = @ptrCast(&map[@intCast(i)].name);
			var k: i32 = 0;
			while (k < nlen) : (k += 1) buf[@intCast(pos + k)] = src[@intCast(k)];
			pos += nlen;
		}
		buf[@intCast(pos)] = 0;
	}
}

const WinEntry = extern struct {
	pid: win32.DWORD,
	title: [128]u16,
};
var g_win_map: ?[*]WinEntry = null;
var g_win_count: i32 = 0;
var g_win_capacity: i32 = 0;

fn enumWindowsProc(hwnd: win32.HWND, lparam: win32.LPARAM) callconv(.c) win32.BOOL {
	_ = lparam;
	if (win32.IsWindowVisible(hwnd) == 0) return 1;
	if (win32.GetWindow(hwnd, win32.GW_OWNER) != null) return 1; // only true top-level windows
	var title: [128:0]u16 = std.mem.zeroes([128:0]u16);
	const len = win32.GetWindowTextW(hwnd, &title, 128);
	if (len == 0) return 1;
	var pid: win32.DWORD = 0;
	_ = win32.GetWindowThreadProcessId(hwnd, &pid);
	if (pid == 0) return 1;
	if (g_win_map) |map| {
		var i: i32 = 0;
		while (i < g_win_count) : (i += 1) {
			if (map[@intCast(i)].pid == pid) return 1; // keep the first (topmost z-order) window per pid
		}
	}
	if (g_win_count >= g_win_capacity) {
		g_win_capacity = if (g_win_capacity != 0) g_win_capacity * 2 else 64;
		if (heapRealloc(@ptrCast(g_win_map), @as(usize, @intCast(g_win_capacity)) * @sizeOf(WinEntry))) |new_map_raw| {
			g_win_map = @ptrCast(@alignCast(new_map_raw));
		} else {
			g_win_capacity = 0;
			g_win_count = 0;
			return 0;
		}
	}
	const map = g_win_map.?;
	const idx: usize = @intCast(g_win_count);
	map[idx].pid = pid;
	_ = win32.lstrcpynW(@ptrCast(&map[idx].title), @ptrCast(&title), 128);
	g_win_count += 1;
	return 1;
}

fn buildWindowMap() void {
	g_win_count = 0;
	if (g_win_map == null) {
		// heap_realloc is HeapReAlloc, which (unlike CRT realloc) requires a
		// real existing block, so seed one here; otherwise growth in the
		// callback would call it with NULL.
		g_win_capacity = 64;
		const raw = heapAlloc(@as(usize, @intCast(g_win_capacity)) * @sizeOf(WinEntry));
		g_win_map = if (raw) |r| @ptrCast(@alignCast(r)) else null;
	}
	_ = win32.EnumWindows(enumWindowsProc, 0);
}

fn getWindowTitleForPid(pid: win32.DWORD, buf: [*:0]u16, len: i32) void {
	buf[0] = 0;
	if (pid == 0) return;
	const map = g_win_map orelse return;
	var i: i32 = 0;
	while (i < g_win_count) : (i += 1) {
		if (map[@intCast(i)].pid == pid) {
			_ = win32.lstrcpynW(buf, @ptrCast(&map[@intCast(i)].title), len);
			return;
		}
	}
}

var g_nt_qsi_fn: ?FnNtQSI = null;

fn queryAllProcesses(total_size: *win32.ULONG) ?[*]u8 {
	if (g_nt_qsi_fn == null) {
		g_nt_qsi_fn = asFn(FnNtQSI, win32.GetProcAddress(win32.GetModuleHandleW(L("ntdll.dll")), "NtQuerySystemInformation"));
	}
	const fn_ptr = g_nt_qsi_fn orelse return null;
	var size: win32.ULONG = 512 * 1024;
	while (true) {
		const buf = heapAlloc(size) orelse return null;
		var returned: win32.ULONG = 0;
		const st = fn_ptr(SYSTEM_PROCESS_INFORMATION_CLASS, buf, size, &returned);
		if (st == 0) {
			total_size.* = if (returned != 0) returned else size;
			return @ptrCast(buf);
		}
		heapFree(buf);
		if (st == STATUS_INFO_LENGTH_MISMATCH) {
			size = if (returned != 0) returned + 65536 else size * 2;
			continue;
		}
		return null;
	}
}

fn updateSnapshot(snapshots: [*]pt.SnapshotEntry, pid: win32.DWORD, snap: pt.CpuSnapshot) void {
	const h: usize = pid % pt.SNAPSHOT_CAPACITY;
	var i = h;
	while (true) {
		if (snapshots[i].active == 0 or snapshots[i].pid == pid) {
			snapshots[i].active = 1;
			snapshots[i].pid = pid;
			snapshots[i].snapshot = snap;
			return;
		}
		i = (i + 1) % pt.SNAPSHOT_CAPACITY;
		if (i == h) break;
	}
}

fn findSnapshot(snapshots: [*]pt.SnapshotEntry, pid: win32.DWORD) ?*pt.CpuSnapshot {
	const h: usize = pid % pt.SNAPSHOT_CAPACITY;
	var i = h;
	while (true) {
		if (snapshots[i].active == 0) return null;
		if (snapshots[i].pid == pid) return &snapshots[i].snapshot;
		i = (i + 1) % pt.SNAPSHOT_CAPACITY;
		if (i == h) break;
	}
	return null;
}

// process_entry is large enough now that copying it by value risks overflowing
// the no-CRT stack-probe-free frame budget (__chkstk isn't linkable here), so
// swaps and the pivot copy go through explicit memcpy (never a struct-value
// temporary) just like the original C.
fn swapEntries(a: *pt.ProcessEntry, b: *pt.ProcessEntry, scratch: *pt.ProcessEntry) void {
	@memcpy(std.mem.asBytes(scratch), std.mem.asBytes(a));
	@memcpy(std.mem.asBytes(a), std.mem.asBytes(b));
	@memcpy(std.mem.asBytes(b), std.mem.asBytes(scratch));
}

fn cmp(a: anytype, b: @TypeOf(a)) i32 {
	if (a < b) return -1;
	if (a > b) return 1;
	return 0;
}

fn compareEntries(a: *const pt.ProcessEntry, b: *const pt.ProcessEntry, field: settings.SortField, descending: win32.BOOL) i32 {
	const res: i32 = switch (field) {
		.SORT_FIELD_NAME => win32.StrCmpIW(@ptrCast(&a.name), @ptrCast(&b.name)),
		.SORT_FIELD_PID => cmp(a.pid, b.pid),
		.SORT_FIELD_CPU => cmp(a.cpu_percent, b.cpu_percent),
		.SORT_FIELD_MEMORY => cmp(a.working_set, b.working_set),
		.SORT_FIELD_THREADS => cmp(a.threads, b.threads),
		.SORT_FIELD_HANDLES => cmp(a.handles, b.handles),
		.SORT_FIELD_STARTTIME => cmp(a.start_time, b.start_time),
		.SORT_FIELD_PRIORITY => cmp(a.base_priority, b.base_priority),
		.SORT_FIELD_DISK_IO => cmp(a.disk_io_rate, b.disk_io_rate),
		.SORT_FIELD_PRIVATE_BYTES => cmp(a.private_bytes, b.private_bytes),
		.SORT_FIELD_PAGE_FAULTS => cmp(a.page_faults_per_sec, b.page_faults_per_sec),
		.SORT_FIELD_USER => win32.StrCmpIW(@ptrCast(&a.user), @ptrCast(&b.user)),
		.SORT_FIELD_CMDLINE => win32.StrCmpIW(@ptrCast(&a.cmdline), @ptrCast(&b.cmdline)),
		.SORT_FIELD_ARCH => cmp(a.arch_machine, b.arch_machine),
		.SORT_FIELD_SESSION => cmp(a.session_id, b.session_id),
		.SORT_FIELD_PEAK_WORKING_SET => cmp(a.peak_working_set, b.peak_working_set),
		.SORT_FIELD_VIRTUAL_MEM => cmp(a.virtual_size, b.virtual_size),
		.SORT_FIELD_GDI_OBJECTS => cmp(a.gdi_objects, b.gdi_objects),
		.SORT_FIELD_USER_OBJECTS => cmp(a.user_objects, b.user_objects),
		.SORT_FIELD_INTEGRITY => cmp(a.integrity_level, b.integrity_level),
		.SORT_FIELD_PPID => cmp(a.parent_pid, b.parent_pid),
		.SORT_FIELD_PRIVATE_WS => cmp(a.private_working_set, b.private_working_set),
		.SORT_FIELD_PAGED_POOL => cmp(a.paged_pool, b.paged_pool),
		.SORT_FIELD_NONPAGED_POOL => cmp(a.non_paged_pool, b.non_paged_pool),
		.SORT_FIELD_IO_READ => cmp(a.io_read_rate, b.io_read_rate),
		.SORT_FIELD_IO_WRITE => cmp(a.io_write_rate, b.io_write_rate),
		.SORT_FIELD_IO_OTHER => cmp(a.io_other_rate, b.io_other_rate),
		.SORT_FIELD_DESCRIPTION => win32.StrCmpIW(@ptrCast(&a.description), @ptrCast(&b.description)),
		.SORT_FIELD_COMPANY => win32.StrCmpIW(@ptrCast(&a.company), @ptrCast(&b.company)),
		.SORT_FIELD_DPI => @as(i32, @intFromEnum(a.dpi_awareness)) - @as(i32, @intFromEnum(b.dpi_awareness)),
		.SORT_FIELD_SERVICE => win32.StrCmpIW(@ptrCast(&a.services), @ptrCast(&b.services)),
		.SORT_FIELD_GPU => cmp(a.gpu_percent, b.gpu_percent),
		.SORT_FIELD_GPU_MEMORY => cmp(a.gpu_memory, b.gpu_memory),
		.SORT_FIELD_CPU_TIME => cmp(a.cpu_time, b.cpu_time),
		.SORT_FIELD_ELEVATED => cmp(a.elevated, b.elevated),
		.SORT_FIELD_PATH => win32.StrCmpIW(@ptrCast(&a.path), @ptrCast(&b.path)),
		.SORT_FIELD_WINDOW_TITLE => win32.StrCmpIW(@ptrCast(&a.window_title), @ptrCast(&b.window_title)),
		.SORT_FIELD_FILE_VERSION => win32.StrCmpIW(@ptrCast(&a.file_version), @ptrCast(&b.file_version)),
		.SORT_FIELD_PRODUCT_VERSION => win32.StrCmpIW(@ptrCast(&a.product_version), @ptrCast(&b.product_version)),
		.SORT_FIELD_SESSION_NAME => win32.StrCmpIW(@ptrCast(&a.session_name), @ptrCast(&b.session_name)),
		.SORT_FIELD_PACKAGE_NAME => win32.StrCmpIW(@ptrCast(&a.package_name), @ptrCast(&b.package_name)),
		.SORT_FIELD_PEAK_VIRTUAL_MEM => cmp(a.peak_virtual_size, b.peak_virtual_size),
		.SORT_FIELD_PEAK_PRIVATE_BYTES => cmp(a.peak_private_bytes, b.peak_private_bytes),
		.SORT_FIELD_PEAK_PAGED_POOL => cmp(a.peak_paged_pool, b.peak_paged_pool),
		.SORT_FIELD_PEAK_NONPAGED_POOL => cmp(a.peak_non_paged_pool, b.peak_non_paged_pool),
		.SORT_FIELD_PEAK_THREADS => cmp(a.peak_threads, b.peak_threads),
		.SORT_FIELD_HARD_FAULTS => cmp(a.hard_faults_per_sec, b.hard_faults_per_sec),
		.SORT_FIELD_CYCLES => cmp(a.cycles_per_sec, b.cycles_per_sec),
		.SORT_FIELD_KERNEL_TIME => cmp(a.kernel_time, b.kernel_time),
		.SORT_FIELD_USER_TIME => cmp(a.user_time, b.user_time),
		.SORT_FIELD_TOTAL_PAGE_FAULTS => cmp(a.total_page_faults, b.total_page_faults),
		.SORT_FIELD_IO_READ_OPS => cmp(a.io_read_ops, b.io_read_ops),
		.SORT_FIELD_IO_WRITE_OPS => cmp(a.io_write_ops, b.io_write_ops),
		.SORT_FIELD_IO_OTHER_OPS => cmp(a.io_other_ops, b.io_other_ops),
		.SORT_FIELD_TOTAL_IO => cmp(a.total_io_bytes, b.total_io_bytes),
		.SORT_FIELD_ELAPSED => cmp(a.elapsed_time, b.elapsed_time),
		.SORT_FIELD_SHARED_WS => cmp(a.shared_working_set, b.shared_working_set),
		.SORT_FIELD_PARENT_NAME => win32.StrCmpIW(@ptrCast(&a.parent_name), @ptrCast(&b.parent_name)),
		.SORT_FIELD_PRIVATE_BYTES_DELTA => cmp(a.private_bytes_delta, b.private_bytes_delta),
		.SORT_FIELD_WORKING_SET_DELTA => cmp(a.working_set_delta, b.working_set_delta),
		.SORT_FIELD_HANDLE_DELTA => cmp(a.handle_delta, b.handle_delta),
		.SORT_FIELD_THREAD_DELTA => cmp(a.thread_delta, b.thread_delta),
		.SORT_FIELD_VIRTUALIZATION => cmp(a.virtualization, b.virtualization),
		.SORT_FIELD_APP_CONTAINER => cmp(a.app_container, b.app_container),
		.SORT_FIELD_DOMAIN => win32.StrCmpIW(@ptrCast(&a.domain), @ptrCast(&b.domain)),
		.SORT_FIELD_USER_SID => win32.StrCmpIW(@ptrCast(&a.user_sid), @ptrCast(&b.user_sid)),
		.SORT_FIELD_EFFICIENCY => cmp(a.efficiency_mode, b.efficiency_mode),
		.SORT_FIELD_IO_PRIORITY => cmp(a.io_priority, b.io_priority),
		.SORT_FIELD_PAGE_PRIORITY => cmp(a.page_priority, b.page_priority),
		.SORT_FIELD_PROTECTION => cmp(a.protection, b.protection),
	};
	return if (descending != 0) -res else res;
}

const StackEntry = struct { low: i32, high: i32 };

fn quicksort(entries: [*]pt.ProcessEntry, low: i32, high: i32, field: settings.SortField, descending: win32.BOOL) void {
	if (low >= high) return;
	var stack: [64]StackEntry = undefined;
	const pivot_raw = heapAlloc(@sizeOf(pt.ProcessEntry));
	const swap_tmp_raw = heapAlloc(@sizeOf(pt.ProcessEntry));
	if (pivot_raw == null or swap_tmp_raw == null) {
		heapFree(pivot_raw);
		heapFree(swap_tmp_raw);
		return;
	}
	const pivot: *pt.ProcessEntry = @ptrCast(@alignCast(pivot_raw.?));
	const swap_tmp: *pt.ProcessEntry = @ptrCast(@alignCast(swap_tmp_raw.?));
	var top: i32 = -1;
	var l = low;
	var h = high;
	while (true) {
		@memcpy(std.mem.asBytes(pivot), std.mem.asBytes(&entries[@intCast(l + @divTrunc(h - l, 2))]));
		var i = l;
		var j = h;
		while (i <= j) {
			while (compareEntries(&entries[@intCast(i)], pivot, field, descending) < 0) i += 1;
			while (compareEntries(&entries[@intCast(j)], pivot, field, descending) > 0) j -= 1;
			if (i <= j) {
				swapEntries(&entries[@intCast(i)], &entries[@intCast(j)], swap_tmp);
				i += 1;
				j -= 1;
			}
		}
		const left_smaller = (j - l) < (h - i);
		var next_low: i32 = 0;
		var next_high: i32 = 0;
		var have_next = false;
		if (left_smaller) {
			if (l < j) {
				next_low = l;
				next_high = j;
				have_next = true;
			}
			if (i < h) {
				top += 1;
				stack[@intCast(top)] = .{ .low = i, .high = h };
			}
		} else {
			if (i < h) {
				next_low = i;
				next_high = h;
				have_next = true;
			}
			if (l < j) {
				top += 1;
				stack[@intCast(top)] = .{ .low = l, .high = j };
			}
		}
		if (have_next) {
			l = next_low;
			h = next_high;
		} else if (top >= 0) {
			const range = stack[@intCast(top)];
			top -= 1;
			l = range.low;
			h = range.high;
		} else break;
	}
	heapFree(pivot);
	heapFree(swap_tmp);
}

var g_native_machine: win32.USHORT = 0;

fn getNativeMachine() win32.USHORT {
	if (g_native_machine != 0) return g_native_machine;
	if (asFn(FnIsWow64Process2, win32.GetProcAddress(win32.GetModuleHandleW(L("kernel32.dll")), "IsWow64Process2"))) |f| {
		var proc_machine: win32.USHORT = undefined;
		_ = f(win32.GetCurrentProcess(), &proc_machine, &g_native_machine);
	} else {
		var si: win32.SYSTEM_INFO = undefined;
		win32.GetNativeSystemInfo(&si);
		g_native_machine = switch (si.wProcessorArchitecture) {
			win32.PROCESSOR_ARCHITECTURE_AMD64 => 0x8664,
			win32.PROCESSOR_ARCHITECTURE_ARM64 => 0xAA64,
			else => 0x014c,
		};
	}
	return g_native_machine;
}

var g_wow64_process2_fn: ?FnIsWow64Process2 = null;
var g_wow64_process2_checked: bool = false;

fn getProcessArch(h: win32.HANDLE) win32.USHORT {
	if (!g_wow64_process2_checked) {
		g_wow64_process2_checked = true;
		g_wow64_process2_fn = asFn(FnIsWow64Process2, win32.GetProcAddress(win32.GetModuleHandleW(L("kernel32.dll")), "IsWow64Process2"));
	}
	var arch: win32.USHORT = 0;
	if (g_wow64_process2_fn) |f| {
		var proc_machine: win32.USHORT = undefined;
		var native: win32.USHORT = undefined;
		if (f(h, &proc_machine, &native) != 0) {
			arch = if (proc_machine == win32.IMAGE_FILE_MACHINE_UNKNOWN) native else proc_machine;
		}
	} else {
		var is_wow64: win32.BOOL = 0;
		_ = win32.IsWow64Process(h, &is_wow64);
		arch = if (is_wow64 != 0) 0x014c else getNativeMachine();
	}
	return arch;
}

const TokenInfo = extern struct {
	integrity_level: win32.DWORD,
	elevated: i32,
	virtualization: i32,
	app_container: i32,
	user: [64]u16,
	domain: [64]u16,
	sid: [128]u16,
};

// Everything here comes off one token, so open the process and its token once
// rather than once per attribute. "Unknown" values mean the token was out of
// reach, which is normal for protected processes and other users' processes.
fn getProcessTokenInfo(pid: win32.DWORD, ti: *TokenInfo) void {
	ti.integrity_level = 0;
	ti.elevated = -1;
	ti.virtualization = -1;
	ti.app_container = -1;
	ti.user[0] = 0;
	ti.domain[0] = 0;
	ti.sid[0] = 0;
	if (pid == 0) {
		ti.integrity_level = 0x4000; // SYSTEM
		ti.elevated = 0;
		_ = win32.lstrcpynW(@ptrCast(&ti.user), L("SYSTEM"), 64);
		return;
	}
	const hproc = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
	if (hproc == null) return;
	var htok: win32.HANDLE = null;
	const opened = win32.OpenProcessToken(hproc, win32.TOKEN_QUERY, &htok);
	_ = win32.CloseHandle(hproc);
	if (opened == 0) return;
	var needed: win32.DWORD = 0;
	_ = win32.GetTokenInformation(htok, win32.TokenIntegrityLevel, null, 0, &needed);
	if (heapAlloc(needed)) |buf| {
		if (win32.GetTokenInformation(htok, win32.TokenIntegrityLevel, buf, needed, &needed) != 0) {
			const tml: *win32.TOKEN_MANDATORY_LABEL = @ptrCast(@alignCast(buf));
			const sub_count = win32.GetSidSubAuthorityCount(tml.Label.Sid).*;
			ti.integrity_level = win32.GetSidSubAuthority(tml.Label.Sid, @as(win32.DWORD, sub_count) -% 1).*;
		}
		heapFree(buf);
	}
	var elev: win32.TOKEN_ELEVATION = std.mem.zeroes(win32.TOKEN_ELEVATION);
	if (win32.GetTokenInformation(htok, win32.TokenElevation, &elev, @sizeOf(win32.TOKEN_ELEVATION), &needed) != 0)
		ti.elevated = if (elev.TokenIsElevated != 0) 1 else 0;
	var allowed: win32.DWORD = 0;
	var enabled: win32.DWORD = 0;
	if (win32.GetTokenInformation(htok, win32.TokenVirtualizationAllowed, &allowed, @sizeOf(win32.DWORD), &needed) != 0) {
		if (allowed == 0) {
			ti.virtualization = 0;
		} else if (win32.GetTokenInformation(htok, win32.TokenVirtualizationEnabled, &enabled, @sizeOf(win32.DWORD), &needed) != 0) {
			ti.virtualization = if (enabled != 0) 2 else 1;
		}
	}
	var is_container: win32.DWORD = 0;
	if (win32.GetTokenInformation(htok, win32.TokenIsAppContainer, &is_container, @sizeOf(win32.DWORD), &needed) != 0)
		ti.app_container = if (is_container != 0) 1 else 0;
	needed = 0;
	_ = win32.GetTokenInformation(htok, win32.TokenUser, null, 0, &needed);
	if (heapAlloc(needed)) |ubuf| {
		if (win32.GetTokenInformation(htok, win32.TokenUser, ubuf, needed, &needed) != 0) {
			const tu: *win32.TOKEN_USER = @ptrCast(@alignCast(ubuf));
			var name: [64:0]u16 = std.mem.zeroes([64:0]u16);
			var domain: [64:0]u16 = std.mem.zeroes([64:0]u16);
			var nlen: win32.DWORD = 64;
			var dlen: win32.DWORD = 64;
			var use: i32 = 0;
			if (win32.LookupAccountSidW(null, tu.User.Sid, &name, &nlen, &domain, &dlen, &use) != 0) {
				_ = win32.lstrcpynW(@ptrCast(&ti.user), &name, 64);
				_ = win32.lstrcpynW(@ptrCast(&ti.domain), &domain, 64);
			}
			var sid_str: win32.LPWSTR = null;
			if (win32.ConvertSidToStringSidW(tu.User.Sid, &sid_str) != 0) {
				_ = win32.lstrcpynW(@ptrCast(&ti.sid), sid_str.?, 128);
				_ = win32.LocalFree(sid_str);
			}
		}
		heapFree(ubuf);
	}
	_ = win32.CloseHandle(htok);
}

var g_nt_qip_fn: ?FnNtQIP = null;

fn getNtQueryProcess() ?FnNtQIP {
	if (g_nt_qip_fn == null) {
		g_nt_qip_fn = asFn(FnNtQIP, win32.GetProcAddress(win32.GetModuleHandleW(L("ntdll.dll")), "NtQueryInformationProcess"));
	}
	return g_nt_qip_fn;
}

fn getProcessCmdline(h: win32.HANDLE, buf: [*:0]u16, len: i32) void {
	buf[0] = 0;
	const fn_ptr = getNtQueryProcess() orelse return;
	var needed: win32.ULONG = 0;
	_ = fn_ptr(h, 60, null, 0, &needed);
	if (needed == 0) needed = 1024;
	if (heapAlloc(needed)) |cbuf| {
		const st = fn_ptr(h, 60, cbuf, needed, null);
		if (st >= 0) {
			const us: *UNICODE_STRING = @ptrCast(@alignCast(cbuf));
			if (us.Buffer != null and us.Length > 0) {
				var wlen: i32 = @intCast(us.Length / 2);
				if (wlen >= len) wlen = len - 1;
				const src = us.Buffer.?;
				var k: i32 = 0;
				while (k < wlen) : (k += 1) buf[@intCast(k)] = src[@intCast(k)];
				buf[@intCast(wlen)] = 0;
			}
		}
		heapFree(cbuf);
	}
}

const LangCodepage = extern struct {
	lang: win32.USHORT,
	codepage: win32.USHORT,
};

fn getProcessVersionInfo(path: [*:0]align(1) const u16, desc: [*:0]u16, desc_len: i32, company: [*:0]u16, comp_len: i32, file_ver: [*:0]u16, file_ver_len: i32, product_ver: [*:0]u16, product_ver_len: i32) void {
	desc[0] = 0;
	company[0] = 0;
	file_ver[0] = 0;
	product_ver[0] = 0;
	if (path[0] == 0) return;
	var dummy: win32.DWORD = 0;
	const size = win32.GetFileVersionInfoSizeW(path, &dummy);
	if (size == 0) return;
	if (heapAlloc(size)) |data| {
		if (win32.GetFileVersionInfoW(path, 0, size, data) != 0) {
			var translate: ?*anyopaque = null;
			var tlen: win32.UINT = 0;
			if (win32.VerQueryValueW(data, L("\\VarFileInfo\\Translation"), &translate, &tlen) != 0 and tlen >= @sizeOf(LangCodepage)) {
				const lc: *LangCodepage = @ptrCast(@alignCast(translate.?));
				var subblock: [64:0]u16 = std.mem.zeroes([64:0]u16);
				var value: ?*anyopaque = null;
				var vlen: win32.UINT = 0;
				_ = win32.wnsprintfW(&subblock, 64, L("\\StringFileInfo\\%04x%04x\\FileDescription"), lc.lang, lc.codepage);
				if (win32.VerQueryValueW(data, &subblock, &value, &vlen) != 0) _ = win32.lstrcpynW(desc, @ptrCast(@alignCast(value.?)), desc_len);
				_ = win32.wnsprintfW(&subblock, 64, L("\\StringFileInfo\\%04x%04x\\CompanyName"), lc.lang, lc.codepage);
				if (win32.VerQueryValueW(data, &subblock, &value, &vlen) != 0) _ = win32.lstrcpynW(company, @ptrCast(@alignCast(value.?)), comp_len);
				_ = win32.wnsprintfW(&subblock, 64, L("\\StringFileInfo\\%04x%04x\\FileVersion"), lc.lang, lc.codepage);
				if (win32.VerQueryValueW(data, &subblock, &value, &vlen) != 0) _ = win32.lstrcpynW(file_ver, @ptrCast(@alignCast(value.?)), file_ver_len);
				_ = win32.wnsprintfW(&subblock, 64, L("\\StringFileInfo\\%04x%04x\\ProductVersion"), lc.lang, lc.codepage);
				if (win32.VerQueryValueW(data, &subblock, &value, &vlen) != 0) _ = win32.lstrcpynW(product_ver, @ptrCast(@alignCast(value.?)), product_ver_len);
			}
		}
		heapFree(data);
	}
}

fn getSessionName(session_id: win32.DWORD, buf: [*:0]u16, len: i32) void {
	buf[0] = 0;
	var info: win32.LPWSTR = null;
	var bytes: win32.DWORD = 0;
	if (win32.WTSQuerySessionInformationW(win32.WTS_CURRENT_SERVER_HANDLE, session_id, win32.WTSWinStationName, &info, &bytes) != 0) {
		if (info) |i| {
			if (i[0] != 0) _ = win32.lstrcpynW(buf, i, len);
		}
		win32.WTSFreeMemory(info);
	}
}

fn getPackageName(h: win32.HANDLE, buf: [*:0]u16, len: i32) void {
	buf[0] = 0;
	var length: u32 = 0;
	_ = win32.GetPackageFullName(h, &length, null);
	if (length > 0) {
		if (heapAlloc(@as(usize, length) * 2)) |name_raw| {
			const name: [*:0]u16 = @ptrCast(@alignCast(name_raw));
			if (win32.GetPackageFullName(h, &length, name) == 0) _ = win32.lstrcpynW(buf, name, len);
			heapFree(name_raw);
		}
	}
}

var g_gpda_fn: ?*const fn (win32.HANDLE, *i32) callconv(.c) c_long = null;
var g_gpda_checked: bool = false;

fn getProcessDpiAwareness(h: win32.HANDLE) pt.TmDpiAwareness {
	if (!g_gpda_checked) {
		var module_h = win32.GetModuleHandleW(L("shcore.dll"));
		if (module_h == null) module_h = win32.LoadLibraryW(L("shcore.dll"));
		if (module_h) |mh| g_gpda_fn = asFn(@TypeOf(g_gpda_fn.?), win32.GetProcAddress(mh, "GetProcessDpiAwareness"));
		g_gpda_checked = true;
	}
	const fn_ptr = g_gpda_fn orelse return .TM_DPI_UNAWARE;
	var awareness: i32 = 0;
	_ = fn_ptr(h, &awareness);
	return @enumFromInt(awareness);
}

var g_gpi_fn: ?*const fn (win32.HANDLE, c_int, ?*anyopaque, win32.DWORD) callconv(.c) win32.BOOL = null;
var g_gpi_checked: bool = false;

// EcoQoS: the process is opted into reduced clock speed, which is what Task
// Manager surfaces as "Efficiency mode".
fn getEfficiencyMode(h: win32.HANDLE) i32 {
	if (!g_gpi_checked) {
		g_gpi_checked = true;
		g_gpi_fn = asFn(@TypeOf(g_gpi_fn.?), win32.GetProcAddress(win32.GetModuleHandleW(L("kernel32.dll")), "GetProcessInformation"));
	}
	const fn_ptr = g_gpi_fn orelse return -1;
	var state: win32.PROCESS_POWER_THROTTLING_STATE = std.mem.zeroes(win32.PROCESS_POWER_THROTTLING_STATE);
	state.Version = win32.PROCESS_POWER_THROTTLING_CURRENT_VERSION;
	if (fn_ptr(h, win32.ProcessPowerThrottling, &state, @sizeOf(win32.PROCESS_POWER_THROTTLING_STATE)) == 0) return -1;
	return if ((state.ControlMask & win32.PROCESS_POWER_THROTTLING_EXECUTION_SPEED) != 0 and (state.StateMask & win32.PROCESS_POWER_THROTTLING_EXECUTION_SPEED) != 0) 1 else 0;
}

const ProcessIoPriority: win32.DWORD = 33;
const ProcessPagePriority: win32.DWORD = 39;
const ProcessProtectionInformation: win32.DWORD = 61;

fn getNtProcessUlong(h: win32.HANDLE, info_class: win32.DWORD) i32 {
	const fn_ptr = getNtQueryProcess() orelse return -1;
	var value: win32.ULONG = 0;
	if (fn_ptr(h, info_class, &value, @sizeOf(win32.ULONG), null) < 0) return -1;
	return @intCast(value);
}

// PS_PROTECTION is a single byte: Type in bits 0-2, Signer in bits 4-7.
fn getProcessProtection(h: win32.HANDLE) i32 {
	const fn_ptr = getNtQueryProcess() orelse return -1;
	var level: u8 = 0;
	if (fn_ptr(h, ProcessProtectionInformation, &level, 1, null) < 0) return -1;
	return @intCast(level);
}

const HandleInfo = extern struct {
	arch_machine: win32.USHORT,
	gdi_objects: win32.DWORD,
	user_objects: win32.DWORD,
	dpi_awareness: pt.TmDpiAwareness,
	efficiency_mode: i32,
	io_priority: i32,
	page_priority: i32,
	protection: i32,
	path: [win32.MAX_PATH]u16,
	cmdline: [256]u16,
	package_name: [256]u16,
};

// One handle serves every per-process query below. Opening one per attribute
// cost eight OpenProcess round trips per process on every single refresh.
fn getProcessHandleInfo(pid: win32.DWORD, hi: *HandleInfo) void {
	hi.arch_machine = 0;
	hi.gdi_objects = 0;
	hi.user_objects = 0;
	hi.dpi_awareness = .TM_DPI_UNAWARE;
	hi.efficiency_mode = -1;
	hi.io_priority = -1;
	hi.page_priority = -1;
	hi.protection = -1;
	hi.path[0] = 0;
	hi.cmdline[0] = 0;
	hi.package_name[0] = 0;
	if (pid == 0) {
		hi.arch_machine = getNativeMachine();
		return;
	}
	const h = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
	if (h == null) return;
	hi.arch_machine = getProcessArch(h);
	hi.gdi_objects = win32.GetGuiResources(h, win32.GR_GDIOBJECTS);
	hi.user_objects = win32.GetGuiResources(h, win32.GR_USEROBJECTS);
	hi.dpi_awareness = getProcessDpiAwareness(h);
	hi.efficiency_mode = getEfficiencyMode(h);
	hi.io_priority = getNtProcessUlong(h, ProcessIoPriority);
	hi.page_priority = getNtProcessUlong(h, ProcessPagePriority);
	hi.protection = getProcessProtection(h);
	getProcessCmdline(h, @ptrCast(&hi.cmdline), 256);
	getPackageName(h, @ptrCast(&hi.package_name), 256);
	var path_size: win32.DWORD = @intCast(win32.MAX_PATH);
	if (win32.QueryFullProcessImageNameW(h, 0, @ptrCast(&hi.path), &path_size) == 0) hi.path[0] = 0;
	_ = win32.CloseHandle(h);
}

pub export fn snapshot_processes(snapshots: [*]pt.SnapshotEntry, out_count: *i32, field: settings.SortField, descending: win32.BOOL) callconv(.c) ?[*]pt.ProcessEntry {
	buildServiceMap();
	buildWindowMap();
	refreshGpuStats();
	var sys_idle_ft: win32.FILETIME = undefined;
	var sys_kernel_ft: win32.FILETIME = undefined;
	var sys_user_ft: win32.FILETIME = undefined;
	_ = win32.GetSystemTimes(&sys_idle_ft, &sys_kernel_ft, &sys_user_ft);
	const uli_k: u64 = (@as(u64, sys_kernel_ft.dwHighDateTime) << 32) | sys_kernel_ft.dwLowDateTime;
	const uli_u: u64 = (@as(u64, sys_user_ft.dwHighDateTime) << 32) | sys_user_ft.dwLowDateTime;
	const sys_time: u64 = uli_k + uli_u;
	const tick_ms: u64 = win32.GetTickCount64();
	var now_ft: win32.FILETIME = undefined;
	win32.GetSystemTimeAsFileTime(&now_ft);
	const now_ticks: u64 = (@as(u64, now_ft.dwHighDateTime) << 32) | now_ft.dwLowDateTime;
	var buf_size: win32.ULONG = 0;
	const buf = queryAllProcesses(&buf_size) orelse return null;
	var capacity: i32 = 256;
	var count: i32 = 0;
	const entries_raw = heapAlloc(@as(usize, @intCast(capacity)) * @sizeOf(pt.ProcessEntry));
	const hi_raw = heapAlloc(@sizeOf(HandleInfo));
	if (entries_raw == null or hi_raw == null) {
		heapFree(buf);
		heapFree(entries_raw);
		heapFree(hi_raw);
		return null;
	}
	var entries: [*]pt.ProcessEntry = @ptrCast(@alignCast(entries_raw.?));
	const hi: *HandleInfo = @ptrCast(@alignCast(hi_raw.?));
	const old_snaps_raw = heapAlloc(pt.SNAPSHOT_CAPACITY * @sizeOf(pt.SnapshotEntry));
	const old_snaps: [*]pt.SnapshotEntry = @ptrCast(@alignCast(old_snaps_raw.?));
	@memcpy(std.mem.sliceAsBytes(old_snaps[0..pt.SNAPSHOT_CAPACITY]), std.mem.sliceAsBytes(snapshots[0..pt.SNAPSHOT_CAPACITY]));
	@memset(std.mem.sliceAsBytes(snapshots[0..pt.SNAPSHOT_CAPACITY]), 0);
	var p: [*]u8 = buf;
	while (true) {
		const spi: *const SystemProcessInformation = @ptrCast(@alignCast(p));
		const pid: win32.DWORD = @truncate(@intFromPtr(spi.UniqueProcessId));
		if (count >= capacity) {
			capacity *= 2;
			const new_entries = heapRealloc(@ptrCast(entries), @as(usize, @intCast(capacity)) * @sizeOf(pt.ProcessEntry));
			entries = @ptrCast(@alignCast(new_entries.?));
		}
		const e = &entries[@intCast(count)];
		count += 1;
		e.pid = pid;
		e.parent_pid = @truncate(@intFromPtr(spi.InheritedFromUniqueProcessId));
		e.cpu_percent = 0.0;
		e.working_set = spi.WorkingSetSize;
		e.private_working_set = @intCast(spi.WorkingSetPrivateSize);
		e.shared_working_set = if (e.working_set > e.private_working_set) e.working_set - e.private_working_set else 0;
		e.paged_pool = spi.QuotaPagedPoolUsage;
		e.non_paged_pool = spi.QuotaNonPagedPoolUsage;
		e.threads = spi.NumberOfThreads;
		e.handles = spi.HandleCount;
		e.start_time = if (pid == 0) 0 else @bitCast(spi.CreateTime);
		e.elapsed_time = if (e.start_time != 0 and now_ticks > e.start_time) now_ticks - e.start_time else 0;
		e.base_priority = spi.BasePriority;
		e.suspended = is_process_suspended(pid);
		e.private_bytes = spi.PagefileUsage;
		e.disk_io_rate = 0.0;
		e.io_read_rate = 0.0;
		e.io_write_rate = 0.0;
		e.io_other_rate = 0.0;
		e.page_faults_per_sec = 0.0;
		e.hard_faults_per_sec = 0.0;
		e.cycles_per_sec = 0.0;
		e.private_bytes_delta = 0;
		e.working_set_delta = 0;
		e.handle_delta = 0;
		e.thread_delta = 0;
		e.session_id = spi.SessionId;
		e.peak_working_set = spi.PeakWorkingSetSize;
		e.virtual_size = spi.VirtualSize;
		e.peak_virtual_size = spi.PeakVirtualSize;
		e.peak_private_bytes = spi.PeakPagefileUsage;
		e.peak_paged_pool = spi.QuotaPeakPagedPoolUsage;
		e.peak_non_paged_pool = spi.QuotaPeakNonPagedPoolUsage;
		e.peak_threads = spi.NumberOfThreadsHighWatermark;
		getProcessHandleInfo(pid, hi);
		e.gdi_objects = hi.gdi_objects;
		e.user_objects = hi.user_objects;
		e.arch_machine = hi.arch_machine;
		e.dpi_awareness = hi.dpi_awareness;
		e.efficiency_mode = hi.efficiency_mode;
		e.io_priority = hi.io_priority;
		e.page_priority = hi.page_priority;
		e.protection = hi.protection;
		_ = win32.lstrcpynW(@ptrCast(&e.cmdline), @ptrCast(&hi.cmdline), 256);
		_ = win32.lstrcpynW(@ptrCast(&e.package_name), @ptrCast(&hi.package_name), 256);
		_ = win32.lstrcpynW(@ptrCast(&e.path), @ptrCast(&hi.path), @intCast(win32.MAX_PATH));
		var ti: TokenInfo = undefined;
		getProcessTokenInfo(pid, &ti);
		e.integrity_level = ti.integrity_level;
		e.elevated = ti.elevated;
		e.virtualization = ti.virtualization;
		e.app_container = ti.app_container;
		_ = win32.lstrcpynW(@ptrCast(&e.user), @ptrCast(&ti.user), 64);
		_ = win32.lstrcpynW(@ptrCast(&e.domain), @ptrCast(&ti.domain), 64);
		_ = win32.lstrcpynW(@ptrCast(&e.user_sid), @ptrCast(&ti.sid), 128);
		getProcessVersionInfo(@ptrCast(&hi.path), @ptrCast(&e.description), 128, @ptrCast(&e.company), 128, @ptrCast(&e.file_version), 64, @ptrCast(&e.product_version), 64);
		getServicesForPid(pid, @ptrCast(&e.services), 256);
		getGpuStat(pid, &e.gpu_percent, &e.gpu_memory);
		getSessionName(e.session_id, @ptrCast(&e.session_name), 64);
		getWindowTitleForPid(pid, @ptrCast(&e.window_title), 128);
		if (pid == 0) {
			_ = win32.lstrcpyW(@ptrCast(&e.name), L("System Idle Process"));
		} else if (spi.ImageName.Buffer != null and spi.ImageName.Length > 0) {
			var len: i32 = @intCast(spi.ImageName.Length / 2);
			if (len > 63) len = 63;
			const src = spi.ImageName.Buffer.?;
			var k: i32 = 0;
			while (k < len) : (k += 1) e.name[@intCast(k)] = src[@intCast(k)];
			e.name[@intCast(len)] = 0;
		} else {
			_ = win32.lstrcpyW(@ptrCast(&e.name), L("(unknown)"));
		}
		const proc_time: u64 = @as(u64, @bitCast(spi.KernelTime)) + @as(u64, @bitCast(spi.UserTime));
		e.cpu_time = proc_time;
		e.kernel_time = @bitCast(spi.KernelTime);
		e.user_time = @bitCast(spi.UserTime);
		e.total_page_faults = spi.PageFaultCount;
		const io_read: u64 = @bitCast(spi.ReadTransferCount);
		const io_write: u64 = @bitCast(spi.WriteTransferCount);
		const io_other: u64 = @bitCast(spi.OtherTransferCount);
		const io_bytes: u64 = io_read + io_write + io_other;
		e.io_read_ops = @bitCast(spi.ReadOperationCount);
		e.io_write_ops = @bitCast(spi.WriteOperationCount);
		e.io_other_ops = @bitCast(spi.OtherOperationCount);
		e.total_io_bytes = io_bytes;
		const current_snap = pt.CpuSnapshot{
			.process_time = proc_time,
			.system_time = sys_time,
			.io_bytes = io_bytes,
			.io_read = io_read,
			.io_write = io_write,
			.io_other = io_other,
			.page_fault_count = spi.PageFaultCount,
			.hard_fault_count = spi.HardFaultCount,
			.cycle_time = spi.CycleTime,
			.private_bytes = e.private_bytes,
			.working_set = e.working_set,
			.handles = e.handles,
			.threads = e.threads,
			.tick_ms = tick_ms,
		};
		updateSnapshot(snapshots, pid, current_snap);
		if (findSnapshot(old_snaps, pid)) |prev| {
			e.private_bytes_delta = @as(i64, @intCast(e.private_bytes)) - @as(i64, @intCast(prev.private_bytes));
			e.working_set_delta = @as(i64, @intCast(e.working_set)) - @as(i64, @intCast(prev.working_set));
			e.handle_delta = @as(i32, @intCast(e.handles)) - @as(i32, @intCast(prev.handles));
			e.thread_delta = @as(i32, @intCast(e.threads)) - @as(i32, @intCast(prev.threads));
			const delta_proc = proc_time -% prev.process_time;
			const delta_sys = sys_time -% prev.system_time;
			if (delta_sys > 0) {
				const pctf: f64 = @as(f64, @floatFromInt(delta_proc)) / @as(f64, @floatFromInt(delta_sys)) * 100.0;
				e.cpu_percent = if (pctf < 0.0) 0.0 else if (pctf > 100.0) 100.0 else pctf;
			}
			const delta_ms = tick_ms -% prev.tick_ms;
			if (delta_ms > 0) {
				const delta_io = io_bytes -% prev.io_bytes;
				e.disk_io_rate = @as(f64, @floatFromInt(delta_io)) * 1000.0 / @as(f64, @floatFromInt(delta_ms));
				const delta_read: u64 = if (io_read >= prev.io_read) io_read - prev.io_read else 0;
				e.io_read_rate = @as(f64, @floatFromInt(delta_read)) * 1000.0 / @as(f64, @floatFromInt(delta_ms));
				const delta_write: u64 = if (io_write >= prev.io_write) io_write - prev.io_write else 0;
				e.io_write_rate = @as(f64, @floatFromInt(delta_write)) * 1000.0 / @as(f64, @floatFromInt(delta_ms));
				const delta_other: u64 = if (io_other >= prev.io_other) io_other - prev.io_other else 0;
				e.io_other_rate = @as(f64, @floatFromInt(delta_other)) * 1000.0 / @as(f64, @floatFromInt(delta_ms));
				const delta_pf: u64 = if (spi.PageFaultCount >= prev.page_fault_count) spi.PageFaultCount - prev.page_fault_count else 0;
				e.page_faults_per_sec = @as(f64, @floatFromInt(delta_pf)) * 1000.0 / @as(f64, @floatFromInt(delta_ms));
				const delta_hf: u64 = if (spi.HardFaultCount >= prev.hard_fault_count) spi.HardFaultCount - prev.hard_fault_count else 0;
				e.hard_faults_per_sec = @as(f64, @floatFromInt(delta_hf)) * 1000.0 / @as(f64, @floatFromInt(delta_ms));
				const delta_cycles: u64 = if (spi.CycleTime >= prev.cycle_time) spi.CycleTime - prev.cycle_time else 0;
				e.cycles_per_sec = @as(f64, @floatFromInt(delta_cycles)) * 1000.0 / @as(f64, @floatFromInt(delta_ms));
			}
		}
		if (spi.NextEntryOffset == 0) break;
		p = p + spi.NextEntryOffset;
	}
	heapFree(buf);
	heapFree(old_snaps);
	heapFree(hi);
	// Resolve parent names now that every entry is known. A recycled PID can
	// point at a process that started after its supposed child, in which case
	// the real parent is gone rather than whatever now holds the PID.
	var i: i32 = 0;
	while (i < count) : (i += 1) {
		const ei: usize = @intCast(i);
		entries[ei].parent_name[0] = 0;
		const ppid = entries[ei].parent_pid;
		if (ppid != 0 and ppid != entries[ei].pid) {
			var j: i32 = 0;
			while (j < count) : (j += 1) {
				const ej: usize = @intCast(j);
				if (entries[ej].pid != ppid) continue;
				if (entries[ej].start_time <= entries[ei].start_time)
					_ = win32.lstrcpynW(@ptrCast(&entries[ei].parent_name), @ptrCast(&entries[ej].name), 64);
				break;
			}
		}
		if (entries[ei].parent_name[0] == 0) _ = win32.lstrcpynW(@ptrCast(&entries[ei].parent_name), L("(exited)"), 64);
	}
	quicksort(entries, 0, count - 1, field, descending);
	out_count.* = count;
	return entries;
}

pub export fn free_process_entries(entries: ?[*]pt.ProcessEntry) callconv(.c) void {
	heapFree(@ptrCast(entries));
}

pub export fn get_process_path(pid: win32.DWORD, path: [*:0]u16, size_in: win32.DWORD) callconv(.c) void {
	var size = size_in;
	const h = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
	if (h == null) {
		path[0] = 0;
		return;
	}
	if (win32.QueryFullProcessImageNameW(h, 0, path, &size) == 0) path[0] = 0;
	_ = win32.CloseHandle(h);
}

pub export fn terminate_process(pid: win32.DWORD) callconv(.c) win32.BOOL {
	const h = win32.OpenProcess(win32.PROCESS_TERMINATE, 0, pid);
	if (h == null) return 0;
	const success = win32.TerminateProcess(h, 1);
	_ = win32.CloseHandle(h);
	return success;
}

pub export fn is_process_suspended(pid: win32.DWORD) callconv(.c) win32.BOOL {
	var i: i32 = 0;
	while (i < g_suspended_count) : (i += 1) {
		if (g_suspended_pids[@intCast(i)] == pid) return 1;
	}
	return 0;
}

var g_nt_suspend_fn: ?FnNtProc = null;

pub export fn suspend_process(pid: win32.DWORD) callconv(.c) win32.BOOL {
	if (g_nt_suspend_fn == null) {
		g_nt_suspend_fn = asFn(FnNtProc, win32.GetProcAddress(win32.GetModuleHandleW(L("ntdll.dll")), "NtSuspendProcess"));
	}
	const fn_ptr = g_nt_suspend_fn orelse return 0;
	const h = win32.OpenProcess(win32.PROCESS_SUSPEND_RESUME, 0, pid);
	if (h == null) return 0;
	const ok = fn_ptr(h) >= 0;
	_ = win32.CloseHandle(h);
	if (ok and g_suspended_count < pt.SNAPSHOT_CAPACITY) {
		g_suspended_pids[@intCast(g_suspended_count)] = pid;
		g_suspended_count += 1;
	}
	return if (ok) 1 else 0;
}

var g_nt_resume_fn: ?FnNtProc = null;

pub export fn resume_process(pid: win32.DWORD) callconv(.c) win32.BOOL {
	if (g_nt_resume_fn == null) {
		g_nt_resume_fn = asFn(FnNtProc, win32.GetProcAddress(win32.GetModuleHandleW(L("ntdll.dll")), "NtResumeProcess"));
	}
	const fn_ptr = g_nt_resume_fn orelse return 0;
	const h = win32.OpenProcess(win32.PROCESS_SUSPEND_RESUME, 0, pid);
	if (h == null) return 0;
	const ok = fn_ptr(h) >= 0;
	_ = win32.CloseHandle(h);
	if (ok) {
		var i: i32 = 0;
		while (i < g_suspended_count) : (i += 1) {
			if (g_suspended_pids[@intCast(i)] == pid) {
				g_suspended_count -= 1;
				g_suspended_pids[@intCast(i)] = g_suspended_pids[@intCast(g_suspended_count)];
				break;
			}
		}
	}
	return if (ok) 1 else 0;
}

pub export fn set_process_priority(pid: win32.DWORD, priority_class: win32.DWORD) callconv(.c) win32.BOOL {
	const h = win32.OpenProcess(win32.PROCESS_SET_INFORMATION, 0, pid);
	if (h == null) return 0;
	const success = win32.SetPriorityClass(h, priority_class);
	_ = win32.CloseHandle(h);
	return success;
}
