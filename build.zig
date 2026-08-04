const std = @import("std");

const libs = [_][]const u8{
	"kernel32", "user32", "gdi32",    "shell32", "comctl32", "ole32",
	"shlwapi",  "ntdll",  "advapi32", "dwmapi",  "uxtheme",  "comdlg32",
	"version",  "pdh",    "wtsapi32",
};

const sources = [_][]const u8{
	"src/listview.c",
	"src/main.c",
	"src/process.c",
	"src/run.c",
	"src/settings.c",
	"src/sortbar.c",
	"src/theme.c",
	"src/tray.c",
	"src/treeview.c",
	"src/wndproc.c",
};

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize: std.builtin.OptimizeMode = .ReleaseSmall;

	const exe_mod = b.createModule(.{
		.target = target,
		.optimize = optimize,
		.link_libc = false,
		.stack_protector = false,
		.omit_frame_pointer = true,
	});

	// Zig only adds its bundled mingw-w64 Win32/CRT headers when link_libc is
	// true, but link_libc also pulls in CRT startup objects we don't want.
	// Add the header path by hand so windows.h etc. resolve without linking libc.
	const win32_headers = b.graph.cwdRelativePath(b.pathJoin(&.{
		std.fs.path.dirname(b.graph.zig_exe) orelse ".",
		"lib",
		"libc",
		"include",
		"any-windows-any",
	}));
	exe_mod.addSystemIncludePath(win32_headers);

	exe_mod.addCMacro("UNICODE", "1");
	exe_mod.addCMacro("_UNICODE", "1");
	exe_mod.addCMacro("WIN32_LEAN_AND_MEAN", "1");
	exe_mod.addCMacro("NOMINMAX", "1");

	exe_mod.addCSourceFiles(.{
		.files = &sources,
		.flags = &.{ "-std=c17", "-Wall", "-Wextra" },
	});
	// entry.c defines its own memset/memcpy/memmove; without -fno-builtin, LLVM's
	// idiom recognizer can rewrite their copy loops into calls to themselves.
	exe_mod.addCSourceFile(.{
		.file = b.path("src/entry.c"),
		.flags = &.{ "-std=c17", "-Wall", "-Wextra", "-fno-builtin" },
	});
	exe_mod.addWin32ResourceFile(.{
		.file = b.path("src/taskmon.rc"),
		.include_paths = &.{win32_headers},
	});

	for (libs) |lib| exe_mod.linkSystemLibrary(lib, .{ .use_pkg_config = .no });

	const exe = b.addExecutable(.{
		.name = "taskmon",
		.root_module = exe_mod,
	});
	exe.subsystem = .windows;
	exe.entry = .{ .symbol_name = "WinMainCRTStartup" };
	exe.link_gc_sections = true;

	b.installArtifact(exe);
}
