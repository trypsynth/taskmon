const std = @import("std");

const libs = [_][]const u8{
	"kernel32", "user32", "gdi32",    "shell32", "comctl32", "ole32",
	"shlwapi",  "ntdll",  "advapi32", "dwmapi",  "uxtheme",  "comdlg32",
	"version",  "pdh",    "wtsapi32",
};

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize: std.builtin.OptimizeMode = .ReleaseSmall;
	const exe_mod = b.createModule(.{
		.root_source_file = b.path("src/main.zig"),
		.target = target,
		.optimize = optimize,
		.link_libc = false,
		.stack_protector = false,
		.omit_frame_pointer = true,
	});
	// The .rc file still #includes windows.h/commctrl.h for the resource
	// compiler, even though no C source remains; point it at Zig's bundled
	// mingw-w64 headers the same way the old C build did.
	const win32_headers = b.graph.cwdRelativePath(b.pathJoin(&.{
		std.fs.path.dirname(b.graph.zig_exe) orelse ".",
		"lib",
		"libc",
		"include",
		"any-windows-any",
	}));
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
	exe.link_gc_sections = true;
	b.installArtifact(exe);
	if (b.findProgram(.{ .names = &.{"pandoc"} })) |pandoc| {
		const doc_run = b.addSystemCommand(&.{ pandoc, "-s" });
		doc_run.addFileArg(b.path("doc/readme.md"));
		doc_run.addArg("-o");
		const readme_html = doc_run.addOutputFileArg("readme.html");
		b.getInstallStep().dependOn(&b.addInstallBinFile(readme_html, "readme.html").step);
	}
	if (b.findProgram(.{ .names = &.{"makensis"} })) |makensis| {
		const arch = if (target.result.cpu.arch == .aarch64) "arm64" else "x64";
		const version = b.graph.environ_map.get("TASKMON_VERSION") orelse "0.2.1";
		const installer_run = b.addSystemCommand(&.{makensis});
		installer_run.setCwd(b.path("installer"));
		installer_run.addArg(b.fmt("/DMyAppArch={s}", .{arch}));
		installer_run.addArg(b.fmt("/DMyAppVersion={s}", .{version}));
		installer_run.addPrefixedDirectoryArg("/DSourceExeDir=", exe.getEmittedBinDirectory());
		const installer_dir = installer_run.addPrefixedOutputDirectoryArg("/DMyOutputDir=", "installer");
		installer_run.addFileArg(b.path("installer/taskmon.nsi"));
		b.getInstallStep().dependOn(&b.addInstallDirectory(.{
			.source_dir = installer_dir,
			.install_dir = .bin,
			.install_subdir = "",
		}).step);
	}
}
