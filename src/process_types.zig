// These stay extern struct so process.zig's quicksort can swap/copy entries
// with raw memcpy - a stable, declaration-order byte layout is required for
// that, not just a convenient one.
const win32 = @import("win32.zig");

pub const SIZE_T = usize;
pub const ULONGLONG = u64;
pub const LONGLONG = i64;
pub const ULONG = u32;
pub const USHORT = u16;

pub const TmDpiAwareness = enum(i32) {
	unaware = 0,
	system_aware = 1,
	per_monitor_aware = 2,
};

pub const ProcessEntry = extern struct {
	pid: win32.DWORD,
	parent_pid: win32.DWORD,
	name: [64]u16,
	description: [128]u16,
	company: [128]u16,
	dpi_awareness: TmDpiAwareness,
	cpu_percent: f64,
	working_set: SIZE_T,
	private_working_set: SIZE_T,
	paged_pool: SIZE_T,
	non_paged_pool: SIZE_T,
	threads: win32.DWORD,
	handles: win32.DWORD,
	start_time: ULONGLONG,
	base_priority: i32,
	suspended: win32.BOOL,
	disk_io_rate: f64,
	io_read_rate: f64,
	io_write_rate: f64,
	io_other_rate: f64,
	private_bytes: SIZE_T,
	page_faults_per_sec: f64,
	user: [64]u16,
	cmdline: [256]u16,
	services: [256]u16,
	arch_machine: USHORT,
	session_id: win32.DWORD,
	peak_working_set: SIZE_T,
	virtual_size: SIZE_T,
	gdi_objects: win32.DWORD,
	user_objects: win32.DWORD,
	integrity_level: win32.DWORD,
	gpu_percent: f64,
	gpu_memory: ULONGLONG,
	cpu_time: ULONGLONG,
	elevated: i32,
	path: [win32.MAX_PATH]u16,
	window_title: [128]u16,
	file_version: [64]u16,
	product_version: [64]u16,
	session_name: [64]u16,
	package_name: [256]u16,
	peak_virtual_size: SIZE_T,
	peak_private_bytes: SIZE_T,
	peak_paged_pool: SIZE_T,
	peak_non_paged_pool: SIZE_T,
	peak_threads: win32.DWORD,
	hard_faults_per_sec: f64,
	cycles_per_sec: f64,
	kernel_time: ULONGLONG,
	user_time: ULONGLONG,
	total_page_faults: ULONG,
	io_read_ops: ULONGLONG,
	io_write_ops: ULONGLONG,
	io_other_ops: ULONGLONG,
	total_io_bytes: ULONGLONG,
	elapsed_time: ULONGLONG,
	shared_working_set: SIZE_T,
	parent_name: [64]u16,
	private_bytes_delta: LONGLONG,
	working_set_delta: LONGLONG,
	handle_delta: i32,
	thread_delta: i32,
	virtualization: i32,
	app_container: i32,
	domain: [64]u16,
	user_sid: [128]u16,
	efficiency_mode: i32,
	io_priority: i32,
	page_priority: i32,
	protection: i32,
};

pub const CpuSnapshot = extern struct {
	process_time: ULONGLONG,
	system_time: ULONGLONG,
	io_bytes: ULONGLONG,
	io_read: ULONGLONG,
	io_write: ULONGLONG,
	io_other: ULONGLONG,
	page_fault_count: ULONG,
	hard_fault_count: ULONG,
	cycle_time: ULONGLONG,
	private_bytes: SIZE_T,
	working_set: SIZE_T,
	handles: win32.DWORD,
	threads: win32.DWORD,
	tick_ms: ULONGLONG,
};

pub const SnapshotEntry = extern struct {
	pid: win32.DWORD,
	snapshot: CpuSnapshot,
	active: win32.BOOL,
};

pub const SNAPSHOT_CAPACITY: usize = 1024;
