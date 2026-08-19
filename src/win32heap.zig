const std = @import("std");
const win32 = @import("win32.zig");

// Windows guarantees every HeapAlloc/HeapReAlloc block is aligned to
// MEMORY_ALLOCATION_ALIGNMENT (16 bytes on x64), which covers every type
// this app allocates through here - none of it is SIMD-vector-aligned.
fn rawAlloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
	_ = ctx;
	_ = ret_addr;
	std.debug.assert(alignment.toByteUnits() <= 16);
	const ptr = win32.HeapAlloc(win32.GetProcessHeap(), 0, len) orelse return null;
	return @ptrCast(ptr);
}

fn rawRemap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
	_ = ctx;
	_ = alignment;
	_ = ret_addr;
	const ptr = win32.HeapReAlloc(win32.GetProcessHeap(), 0, memory.ptr, new_len) orelse return null;
	return @ptrCast(ptr);
}

fn rawFree(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
	_ = ctx;
	_ = alignment;
	_ = ret_addr;
	_ = win32.HeapFree(win32.GetProcessHeap(), 0, memory.ptr);
}

// No in-place resize path: HeapReAlloc (via remap below) already handles
// both the in-place and move-required cases, so there's nothing a separate
// resize implementation would win here.
pub const allocator: std.mem.Allocator = .{
	.ptr = undefined,
	.vtable = &.{
		.alloc = rawAlloc,
		.resize = std.mem.Allocator.noResize,
		.remap = rawRemap,
		.free = rawFree,
	},
};
