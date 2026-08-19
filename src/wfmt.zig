const win32 = @import("win32.zig");

fn putChar(buf: [*]u16, pos: *i32, len: i32, c: u16) void {
	if (pos.* < len - 1) {
		buf[@intCast(pos.*)] = c;
		pos.* += 1;
	}
}

// Takes the one concrete LPCWSTR type rather than anytype: every %s argument
// coerces down to it at the call site, so this loop exists once instead of
// once per distinct pointer type callers happened to pass.
fn putStr(buf: [*]u16, pos: *i32, len: i32, s: win32.LPCWSTR) void {
	var i: usize = 0;
	while (s[i] != 0) : (i += 1) putChar(buf, pos, len, s[i]);
}

// Runtime slice, not a comptime one: this is the one place literal text from
// the format string reaches the output, so every literal run in every format
// call shares this single loop instead of unrolling one putChar per
// character at each call site.
fn putLit(buf: [*]u16, pos: *i32, len: i32, s: []const u8) void {
	for (s) |ch| putChar(buf, pos, len, ch);
}

// %u and %x/%X only differ in base and digit alphabet, so both go through
// this one digit-writing loop rather than two near-identical copies of it.
fn putUintBase(buf: [*]u16, pos: *i32, len: i32, value: u64, base: u8, width: u8, zero_pad: bool, upper: bool) void {
	const letters = if (upper) "0123456789ABCDEF" else "0123456789abcdef";
	var digits: [20]u8 = undefined;
	var n = value;
	var count: usize = 0;
	while (true) {
		digits[count] = letters[n % base];
		count += 1;
		n /= base;
		if (n == 0) break;
	}
	var pad: u8 = if (width > count) width - @as(u8, @intCast(count)) else 0;
	while (pad > 0) : (pad -= 1) putChar(buf, pos, len, if (zero_pad) '0' else ' ');
	while (count > 0) {
		count -= 1;
		putChar(buf, pos, len, digits[count]);
	}
}

fn putInt(buf: [*]u16, pos: *i32, len: i32, value: i64, width: u8, zero_pad: bool) void {
	if (value < 0) {
		putChar(buf, pos, len, '-');
		putUintBase(buf, pos, len, @intCast(-value), 10, if (width > 0) width - 1 else 0, zero_pad, false);
	} else {
		putUintBase(buf, pos, len, @intCast(value), 10, width, zero_pad, false);
	}
}

// A tiny printf subset (%u %d %s %x %X %%, with an optional zero-pad flag and
// width) evaluated entirely at comptime: it walks the format string as an
// inline while loop, so every specifier/argument pairing - including the
// count - is type-checked at compile time instead of trusting a C-style
// variadic call. The actual digit/string writing is done by the small
// runtime helpers above, shared across every call site.
pub fn format(buf: [*:0]u16, len: i32, comptime spec: []const u8, args: anytype) void {
	var pos: i32 = 0;
	comptime var arg_idx: usize = 0;
	comptime var i: usize = 0;
	inline while (i < spec.len) {
		if (spec[i] == '%') {
			i += 1;
			comptime var zero_pad = false;
			comptime var width: u8 = 0;
			if (spec[i] == '0') {
				zero_pad = true;
				i += 1;
			}
			inline while (spec[i] >= '0' and spec[i] <= '9') : (i += 1) {
				width = width * 10 + (spec[i] - '0');
			}
			const c = spec[i];
			i += 1;
			switch (c) {
				'u' => {
					putUintBase(buf, &pos, len, @as(u64, args[arg_idx]), 10, width, zero_pad, false);
					arg_idx += 1;
				},
				'd' => {
					putInt(buf, &pos, len, @as(i64, args[arg_idx]), width, zero_pad);
					arg_idx += 1;
				},
				's' => {
					putStr(buf, &pos, len, args[arg_idx]);
					arg_idx += 1;
				},
				'x', 'X' => {
					putUintBase(buf, &pos, len, @as(u64, args[arg_idx]), 16, width, zero_pad, c == 'X');
					arg_idx += 1;
				},
				'%' => putChar(buf, &pos, len, '%'),
				else => @compileError("wfmt: unsupported specifier"),
			}
		} else {
			const start = i;
			inline while (i < spec.len and spec[i] != '%') : (i += 1) {}
			putLit(buf, &pos, len, spec[start..i]);
		}
	}
	if (arg_idx != args.len) @compileError("wfmt: unused format arguments");
	buf[@intCast(if (pos < len) pos else len - 1)] = 0;
}
