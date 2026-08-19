const std = @import("std");
const win32 = @import("win32.zig");
const pt = @import("process_types.zig");
const settings = @import("settings.zig");
const tray = @import("tray.zig");
const treeview = @import("treeview.zig");
const process = @import("process.zig");
const state = @import("state.zig");
const wfmt = @import("wfmt.zig");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

const WM_HIDE_TO_TRAY: win32.UINT = win32.WM_APP + 2;

/// 100-nanosecond FILETIME ticks to h:mm:ss.
fn formatDuration(ticks: pt.ULONGLONG, buf: [*:0]u16, len: i32) void {
	const total_secs = ticks / 10000000;
	const hours = total_secs / 3600;
	const mins: win32.UINT = @intCast((total_secs % 3600) / 60);
	const secs: win32.UINT = @intCast(total_secs % 60);
	wfmt.format(buf, len, "%u:%02u:%02u", .{ hours, mins, secs });
}

// Deltas read as a change since the previous refresh, so they carry an explicit
// sign and go blank when nothing moved. wfmt has no '+' flag of its own.
fn formatByteDelta(delta: pt.LONGLONG, buf: [*:0]u16, len: i32) void {
	if (delta == 0) {
		buf[0] = 0;
		return;
	}
	var size: [64:0]u16 = std.mem.zeroes([64:0]u16);
	_ = win32.StrFormatByteSizeW(if (delta < 0) -delta else delta, &size, 64);
	wfmt.format(buf, len, "%s%s", .{ if (delta < 0) L("-") else L("+"), @as(win32.LPCWSTR, &size) });
}

fn formatCountDelta(delta: i32, buf: [*:0]u16, len: i32) void {
	if (delta == 0) {
		buf[0] = 0;
	} else {
		wfmt.format(buf, len, "%s%d", .{ if (delta < 0) L("-") else L("+"), if (delta < 0) -delta else delta });
	}
}

// Like formatDuration, but processes routinely run for weeks, so break out days
// rather than letting the hour count grow without bound.
fn formatElapsed(ticks: pt.ULONGLONG, buf: [*:0]u16, len: i32) void {
	if (ticks == 0) {
		buf[0] = 0;
		return;
	}
	const total_secs = ticks / 10000000;
	const days = total_secs / 86400;
	const hours: win32.UINT = @intCast((total_secs % 86400) / 3600);
	const mins: win32.UINT = @intCast((total_secs % 3600) / 60);
	const secs: win32.UINT = @intCast(total_secs % 60);
	if (days != 0) {
		wfmt.format(buf, len, "%ud %02u:%02u:%02u", .{ days, hours, mins, secs });
	} else {
		wfmt.format(buf, len, "%02u:%02u:%02u", .{ hours, mins, secs });
	}
}

// Cycle counts run to billions per second, so scale them down to a K/M/G suffix
// the way StrFormatByteSizeW does for bytes.
fn formatCycleRate(rate: f64, buf: [*:0]u16, len: i32) void {
	if (rate <= 0) {
		buf[0] = 0;
		return;
	}
	var suffix: win32.LPCWSTR = L("");
	var divisor: f64 = 1.0;
	if (rate >= 1000000000.0) {
		suffix = L(" G");
		divisor = 1000000000.0;
	} else if (rate >= 1000000.0) {
		suffix = L(" M");
		divisor = 1000000.0;
	} else if (rate >= 1000.0) {
		suffix = L(" K");
		divisor = 1000.0;
	}
	const scaled = rate / divisor;
	var whole: win32.UINT = @intFromFloat(scaled);
	var frac: win32.UINT = @intFromFloat((scaled - @as(f64, @floatFromInt(whole))) * 100 + 0.5);
	if (frac >= 100) {
		whole += 1;
		frac = 0;
	}
	if (divisor == 1.0) {
		wfmt.format(buf, len, "%u/s", .{whole});
	} else {
		wfmt.format(buf, len, "%u.%02u%s/s", .{ whole, frac, suffix });
	}
}

fn formatColumn(e: *const pt.ProcessEntry, cid: i32, buf: [*:0]u16, len: i32) void {
	@setEvalBranchQuota(100_000);
	switch (@as(settings.SortField, @enumFromInt(cid))) {
		.pid => wfmt.format(buf, len, "%u", .{e.pid}),
		.cpu => {
			var whole: i32 = @intFromFloat(e.cpu_percent);
			var frac: i32 = @intFromFloat((e.cpu_percent - @as(f64, @floatFromInt(whole))) * 100 + 0.5);
			if (frac >= 100) {
				whole += 1;
				frac = 0;
			}
			wfmt.format(buf, len, "%d.%02d", .{ whole, frac });
		},
		.memory => _ = win32.StrFormatByteSizeW(@intCast(e.working_set), buf, @intCast(len)),
		.threads => wfmt.format(buf, len, "%u", .{e.threads}),
		.handles => wfmt.format(buf, len, "%u", .{e.handles}),
		.priority => {
			const label: win32.LPCWSTR = switch (e.base_priority) {
				4 => L("Idle"),
				6 => L("Below Normal"),
				8 => L("Normal"),
				10 => L("Above Normal"),
				13 => L("High"),
				24 => L("Realtime"),
				else => {
					wfmt.format(buf, len, "%d", .{e.base_priority});
					return;
				},
			};
			_ = win32.lstrcpynW(buf, label, len);
		},
		.starttime => {
			if (e.start_time == 0) {
				buf[0] = 0;
				return;
			}
			var ft: win32.FILETIME = undefined;
			ft.dwLowDateTime = @truncate(e.start_time);
			ft.dwHighDateTime = @truncate(e.start_time >> 32);
			var lft: win32.FILETIME = undefined;
			_ = win32.FileTimeToLocalFileTime(&ft, &lft);
			var st: win32.SYSTEMTIME = undefined;
			var now: win32.SYSTEMTIME = undefined;
			_ = win32.FileTimeToSystemTime(&lft, &st);
			win32.GetLocalTime(&now);
			if (st.wYear == now.wYear and st.wMonth == now.wMonth and st.wDay == now.wDay)
				wfmt.format(buf, len, "%02d:%02d:%02d", .{ st.wHour, st.wMinute, st.wSecond })
			else if (st.wYear == now.wYear)
				wfmt.format(buf, len, "%02d/%02d %02d:%02d", .{ st.wMonth, st.wDay, st.wHour, st.wMinute })
			else
				wfmt.format(buf, len, "%02d/%02d/%04d %02d:%02d", .{ st.wMonth, st.wDay, st.wYear, st.wHour, st.wMinute });
		},
		.disk_io => {
			if (e.disk_io_rate > 0) {
				_ = win32.StrFormatByteSizeW(@intFromFloat(e.disk_io_rate), buf, @intCast(len));
				_ = win32.lstrcatW(buf, L("/s"));
			} else buf[0] = 0;
		},
		.private_bytes => _ = win32.StrFormatByteSizeW(@intCast(e.private_bytes), buf, @intCast(len)),
		.page_faults => {
			const pf: win32.UINT = @intFromFloat(e.page_faults_per_sec + 0.5);
			if (pf > 0) wfmt.format(buf, len, "%u /s", .{pf}) else buf[0] = 0;
		},
		.user => _ = win32.lstrcpynW(buf, @ptrCast(&e.user), len),
		.cmdline => _ = win32.lstrcpynW(buf, @ptrCast(&e.cmdline), len),
		.arch => {
			const label: win32.LPCWSTR = switch (e.arch_machine) {
				0x014c => L("x86"),
				0x8664 => L("x64"),
				0xAA64 => L("ARM64"),
				else => {
					buf[0] = 0;
					return;
				},
			};
			_ = win32.lstrcpynW(buf, label, len);
		},
		.session => wfmt.format(buf, len, "%u", .{e.session_id}),
		.peak_working_set => _ = win32.StrFormatByteSizeW(@intCast(e.peak_working_set), buf, @intCast(len)),
		.virtual_mem => _ = win32.StrFormatByteSizeW(@intCast(e.virtual_size), buf, @intCast(len)),
		.gdi_objects => {
			if (e.gdi_objects != 0) wfmt.format(buf, len, "%u", .{e.gdi_objects}) else buf[0] = 0;
		},
		.user_objects => {
			if (e.user_objects != 0) wfmt.format(buf, len, "%u", .{e.user_objects}) else buf[0] = 0;
		},
		.integrity => {
			const label: ?win32.LPCWSTR = switch (e.integrity_level) {
				0x0000 => L("Untrusted"),
				0x1000 => L("Low"),
				0x2000 => L("Medium"),
				0x2100 => L("Medium+"),
				0x3000 => L("High"),
				0x4000 => L("System"),
				0x5000 => L("Protected"),
				else => null,
			};
			if (label) |l| _ = win32.lstrcpynW(buf, l, len) else wfmt.format(buf, len, "0x%04X", .{e.integrity_level});
		},
		.ppid => {
			if (e.parent_pid != 0) wfmt.format(buf, len, "%u", .{e.parent_pid}) else buf[0] = 0;
		},
		.private_ws => _ = win32.StrFormatByteSizeW(@intCast(e.private_working_set), buf, @intCast(len)),
		.paged_pool => _ = win32.StrFormatByteSizeW(@intCast(e.paged_pool), buf, @intCast(len)),
		.nonpaged_pool => _ = win32.StrFormatByteSizeW(@intCast(e.non_paged_pool), buf, @intCast(len)),
		.io_read => {
			if (e.io_read_rate > 0) {
				_ = win32.StrFormatByteSizeW(@intFromFloat(e.io_read_rate), buf, @intCast(len));
				_ = win32.lstrcatW(buf, L("/s"));
			} else buf[0] = 0;
		},
		.io_write => {
			if (e.io_write_rate > 0) {
				_ = win32.StrFormatByteSizeW(@intFromFloat(e.io_write_rate), buf, @intCast(len));
				_ = win32.lstrcatW(buf, L("/s"));
			} else buf[0] = 0;
		},
		.io_other => {
			if (e.io_other_rate > 0) {
				_ = win32.StrFormatByteSizeW(@intFromFloat(e.io_other_rate), buf, @intCast(len));
				_ = win32.lstrcatW(buf, L("/s"));
			} else buf[0] = 0;
		},
		.description => _ = win32.lstrcpynW(buf, @ptrCast(&e.description), len),
		.company => _ = win32.lstrcpynW(buf, @ptrCast(&e.company), len),
		.dpi => {
			const label: win32.LPCWSTR = switch (e.dpi_awareness) {
				.unaware => L("Unaware"),
				.system_aware => L("System"),
				.per_monitor_aware => L("Per-Monitor"),
			};
			_ = win32.lstrcpynW(buf, label, len);
		},
		.service => _ = win32.lstrcpynW(buf, @ptrCast(&e.services), len),
		.gpu => {
			var whole: i32 = @intFromFloat(e.gpu_percent);
			var frac: i32 = @intFromFloat((e.gpu_percent - @as(f64, @floatFromInt(whole))) * 100 + 0.5);
			if (frac >= 100) {
				whole += 1;
				frac = 0;
			}
			wfmt.format(buf, len, "%d.%02d", .{ whole, frac });
		},
		.gpu_memory => _ = win32.StrFormatByteSizeW(@intCast(e.gpu_memory), buf, @intCast(len)),
		.cpu_time => formatDuration(e.cpu_time, buf, len),
		.elevated => {
			if (e.elevated < 0) buf[0] = 0 else _ = win32.lstrcpynW(buf, if (e.elevated != 0) L("Yes") else L("No"), len);
		},
		.path => _ = win32.lstrcpynW(buf, @ptrCast(&e.path), len),
		.window_title => _ = win32.lstrcpynW(buf, @ptrCast(&e.window_title), len),
		.file_version => _ = win32.lstrcpynW(buf, @ptrCast(&e.file_version), len),
		.product_version => _ = win32.lstrcpynW(buf, @ptrCast(&e.product_version), len),
		.session_name => _ = win32.lstrcpynW(buf, @ptrCast(&e.session_name), len),
		.package_name => _ = win32.lstrcpynW(buf, @ptrCast(&e.package_name), len),
		.peak_virtual_mem => _ = win32.StrFormatByteSizeW(@intCast(e.peak_virtual_size), buf, @intCast(len)),
		.peak_private_bytes => _ = win32.StrFormatByteSizeW(@intCast(e.peak_private_bytes), buf, @intCast(len)),
		.peak_paged_pool => _ = win32.StrFormatByteSizeW(@intCast(e.peak_paged_pool), buf, @intCast(len)),
		.peak_nonpaged_pool => _ = win32.StrFormatByteSizeW(@intCast(e.peak_non_paged_pool), buf, @intCast(len)),
		.peak_threads => wfmt.format(buf, len, "%u", .{e.peak_threads}),
		.hard_faults => {
			const hf: win32.UINT = @intFromFloat(e.hard_faults_per_sec + 0.5);
			if (hf > 0) wfmt.format(buf, len, "%u /s", .{hf}) else buf[0] = 0;
		},
		.cycles => formatCycleRate(e.cycles_per_sec, buf, len),
		.kernel_time => formatDuration(e.kernel_time, buf, len),
		.user_time => formatDuration(e.user_time, buf, len),
		.total_page_faults => wfmt.format(buf, len, "%u", .{e.total_page_faults}),
		.io_read_ops => wfmt.format(buf, len, "%u", .{e.io_read_ops}),
		.io_write_ops => wfmt.format(buf, len, "%u", .{e.io_write_ops}),
		.io_other_ops => wfmt.format(buf, len, "%u", .{e.io_other_ops}),
		.total_io => _ = win32.StrFormatByteSizeW(@intCast(e.total_io_bytes), buf, @intCast(len)),
		.elapsed => formatElapsed(e.elapsed_time, buf, len),
		.shared_ws => _ = win32.StrFormatByteSizeW(@intCast(e.shared_working_set), buf, @intCast(len)),
		.parent_name => _ = win32.lstrcpynW(buf, @ptrCast(&e.parent_name), len),
		.private_bytes_delta => formatByteDelta(e.private_bytes_delta, buf, len),
		.working_set_delta => formatByteDelta(e.working_set_delta, buf, len),
		.handle_delta => formatCountDelta(e.handle_delta, buf, len),
		.thread_delta => formatCountDelta(e.thread_delta, buf, len),
		.virtualization => {
			const label: win32.LPCWSTR = switch (e.virtualization) {
				0 => L("Not allowed"),
				1 => L("Disabled"),
				2 => L("Enabled"),
				else => L(""),
			};
			_ = win32.lstrcpynW(buf, label, len);
		},
		.app_container => {
			if (e.app_container < 0) buf[0] = 0 else _ = win32.lstrcpynW(buf, if (e.app_container != 0) L("Yes") else L("No"), len);
		},
		.domain => _ = win32.lstrcpynW(buf, @ptrCast(&e.domain), len),
		.user_sid => _ = win32.lstrcpynW(buf, @ptrCast(&e.user_sid), len),
		.efficiency => {
			if (e.efficiency_mode < 0) buf[0] = 0 else _ = win32.lstrcpynW(buf, if (e.efficiency_mode != 0) L("On") else L("Off"), len);
		},
		.io_priority => {
			const names = [_]win32.LPCWSTR{ L("Very Low"), L("Low"), L("Normal"), L("High"), L("Critical") };
			if (e.io_priority < 0 or e.io_priority > 4) buf[0] = 0 else _ = win32.lstrcpynW(buf, names[@intCast(e.io_priority)], len);
		},
		.page_priority => {
			const names = [_]win32.LPCWSTR{ L("Idle"), L("Very Low"), L("Low"), L("Medium"), L("Below Normal"), L("Normal") };
			if (e.page_priority < 0 or e.page_priority > 5) buf[0] = 0 else _ = win32.lstrcpynW(buf, names[@intCast(e.page_priority)], len);
		},
		.protection => {
			// PS_PROTECTION: type in bits 0-2, signer in bits 4-7. Type 0 means the
			// process is not protected at all, which is the common case.
			const signers = [_]win32.LPCWSTR{ L("None"), L("Authenticode"), L("CodeGen"), L("Antimalware"), L("Lsa"), L("Windows"), L("WinTcb"), L("WinSystem"), L("App") };
			const ptype: i32 = e.protection & 0x07;
			const signer: i32 = (e.protection >> 4) & 0x0F;
			if (e.protection <= 0 or ptype == 0 or signer >= signers.len)
				buf[0] = 0
			else if (ptype == 1)
				wfmt.format(buf, len, "%s-Light", .{signers[@intCast(signer)]})
			else
				_ = win32.lstrcpynW(buf, signers[@intCast(signer)], len);
		},
		else => buf[0] = 0,
	}
}

fn populateList(entries: [*]pt.ProcessEntry, count: i32) f64 {
	var selected_pid: win32.DWORD = 0;
	const selected: i32 = @intCast(win32.SendMessageW(state.hwnd_list, win32.LVM_GETNEXTITEM, @bitCast(@as(isize, -1)), win32.LVNI_SELECTED));
	if (selected != -1) {
		var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
		lvi.mask = win32.LVIF_PARAM;
		lvi.iItem = selected;
		if (win32.SendMessageW(state.hwnd_list, win32.LVM_GETITEMW, 0, @bitCast(@intFromPtr(&lvi))) != 0) selected_pid = @intCast(lvi.lParam);
	}
	var top_pid: win32.DWORD = 0;
	const top_idx: i32 = @intCast(win32.SendMessageW(state.hwnd_list, win32.LVM_GETTOPINDEX, 0, 0));
	const item_count: i32 = @intCast(win32.SendMessageW(state.hwnd_list, win32.LVM_GETITEMCOUNT, 0, 0));
	if (top_idx != -1 and item_count > 0) {
		var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
		lvi.mask = win32.LVIF_PARAM;
		lvi.iItem = top_idx;
		if (win32.SendMessageW(state.hwnd_list, win32.LVM_GETITEMW, 0, @bitCast(@intFromPtr(&lvi))) != 0) top_pid = @intCast(lvi.lParam);
	}
	_ = win32.SendMessageW(state.hwnd_list, win32.WM_SETREDRAW, 0, 0);
	_ = win32.SendMessageW(state.hwnd_list, win32.LVM_DELETEALLITEMS, 0, 0);
	var total_cpu: f64 = 0;
	var new_selected_idx: i32 = -1;
	var new_top_idx: i32 = -1;
	for (0..@intCast(count)) |i| {
		const e = &entries[i];
		if (e.pid != 0) total_cpu += e.cpu_percent;
		var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
		lvi.mask = win32.LVIF_TEXT | win32.LVIF_PARAM;
		lvi.iItem = @intCast(i);
		lvi.pszText = @ptrCast(&e.name);
		lvi.lParam = @intCast(e.pid);
		_ = win32.SendMessageW(state.hwnd_list, win32.LVM_INSERTITEMW, 0, @bitCast(@intFromPtr(&lvi)));
		if (e.pid == selected_pid) new_selected_idx = @intCast(i);
		if (e.pid == top_pid) new_top_idx = @intCast(i);
		var buf: [300:0]u16 = std.mem.zeroes([300:0]u16);
		for (1..@intCast(state.sort_btn_count)) |col| {
			formatColumn(e, state.sort_btn_cols[col], &buf, 300);
			var set_lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
			set_lvi.iSubItem = @intCast(col);
			set_lvi.pszText = &buf;
			_ = win32.SendMessageW(state.hwnd_list, win32.LVM_SETITEMTEXTW, @intCast(i), @bitCast(@intFromPtr(&set_lvi)));
		}
	}
	if (new_selected_idx != -1) {
		var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
		lvi.stateMask = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
		lvi.state = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
		_ = win32.SendMessageW(state.hwnd_list, win32.LVM_SETITEMSTATE, @intCast(new_selected_idx), @bitCast(@intFromPtr(&lvi)));
	} else if (win32.SendMessageW(state.hwnd_list, win32.LVM_GETITEMCOUNT, 0, 0) > 0) {
		var lvi: win32.LVITEMW = std.mem.zeroes(win32.LVITEMW);
		lvi.stateMask = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
		lvi.state = win32.LVIS_SELECTED | win32.LVIS_FOCUSED;
		_ = win32.SendMessageW(state.hwnd_list, win32.LVM_SETITEMSTATE, 0, @bitCast(@intFromPtr(&lvi)));
	}
	if (new_top_idx != -1) {
		var rc: win32.RECT = std.mem.zeroes(win32.RECT);
		rc.left = win32.LVIR_BOUNDS;
		if (win32.SendMessageW(state.hwnd_list, win32.LVM_GETITEMRECT, 0, @bitCast(@intFromPtr(&rc))) != 0) {
			const item_height = rc.bottom - rc.top;
			_ = win32.SendMessageW(state.hwnd_list, win32.LVM_SCROLL, 0, @intCast(new_top_idx * item_height));
		}
	}
	_ = win32.SendMessageW(state.hwnd_list, win32.WM_SETREDRAW, 1, 0);
	_ = win32.InvalidateRect(state.hwnd_list, null, 0);
	tray.updateTip(total_cpu);
	return total_cpu;
}

// The last snapshot doRefresh fetched, kept alive (instead of freed right
// after populating) so resort() below can redisplay it - re-sorted, in the
// other view mode, or against a different visible-column set - without
// paying for another full process enumeration.
var cached_entries: ?[*]pt.ProcessEntry = null;
var cached_count: i32 = 0;

fn updateStatusBar(total_cpu: f64, count: i32) void {
	if (state.hwnd_status == null) return;
	var cpu_w: i32 = @intFromFloat(total_cpu);
	var cpu_f: i32 = @intFromFloat((total_cpu - @as(f64, @floatFromInt(cpu_w))) * 100 + 0.5);
	if (cpu_f >= 100) {
		cpu_w += 1;
		cpu_f = 0;
	}
	var ms: win32.MEMORYSTATUSEX = std.mem.zeroes(win32.MEMORYSTATUSEX);
	ms.dwLength = @sizeOf(win32.MEMORYSTATUSEX);
	_ = win32.GlobalMemoryStatusEx(&ms);
	const in_use = ms.ullTotalPhys - ms.ullAvailPhys;
	const total = ms.ullTotalPhys;
	const gib: u64 = 1024 * 1024 * 1024;
	const iu_w: i32 = @intCast(in_use / gib);
	const iu_f: i32 = @intCast((in_use % gib) * 10 / gib);
	const t_w: i32 = @intCast(total / gib);
	const t_f: i32 = @intCast((total % gib) * 10 / gib);
	var status: [128:0]u16 = std.mem.zeroes([128:0]u16);
	wfmt.format(&status, 128, "  %d processes  |  CPU: %d.%02d%%  |  Memory: %d.%d / %d.%d GB", .{ count, cpu_w, cpu_f, iu_w, iu_f, t_w, t_f });
	_ = win32.SendMessageW(state.hwnd_status, win32.SB_SETTEXTW, 0, @bitCast(@intFromPtr(&status)));
}

pub fn doRefresh() void {
	var count: i32 = 0;
	const field: settings.SortField = if (state.prefs.tree_mode) .name else state.prefs.field;
	const desc: bool = if (state.prefs.tree_mode) false else state.prefs.desc[@intCast(@intFromEnum(state.prefs.field))];
	const entries = process.snapshotProcesses(&state.snapshots, &count, field, desc);
	if (entries) |es| {
		if (cached_entries) |old| process.freeProcessEntries(old);
		cached_entries = es;
		cached_count = count;
		const total_cpu = if (state.prefs.tree_mode) treeview.populate(es, count) else populateList(es, count);
		updateStatusBar(total_cpu, count);
	}
}

// Redisplays the last fetched snapshot - re-sorted, in the other view mode,
// or against a newly-changed visible-column set - without re-querying the
// OS. Falls back to a full doRefresh() if nothing has been fetched yet.
pub fn resort() void {
	const es = cached_entries orelse return doRefresh();
	const field: settings.SortField = if (state.prefs.tree_mode) .name else state.prefs.field;
	const desc: bool = if (state.prefs.tree_mode) false else state.prefs.desc[@intCast(@intFromEnum(state.prefs.field))];
	process.sortEntries(es, cached_count, field, desc);
	const total_cpu = if (state.prefs.tree_mode) treeview.populate(es, cached_count) else populateList(es, cached_count);
	updateStatusBar(total_cpu, cached_count);
}

pub fn listKeyProc(hwnd: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM, id: win32.UINT_PTR, data: win32.DWORD_PTR) callconv(.c) win32.LRESULT {
	_ = id;
	_ = data;
	if (msg == win32.WM_KEYDOWN and wp == win32.VK_ESCAPE) {
		_ = win32.PostMessageW(win32.GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0);
		return 0;
	}
	return win32.DefSubclassProc(hwnd, msg, wp, lp);
}
