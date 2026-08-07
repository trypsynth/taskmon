# Taskmon

Taskmon is a lightweight and fast task manager alternative for Windows. It provides a clean interface for monitoring system resources, managing running processes, viewing active tasks, and controlling system performance without unnecessary overhead.

## Documentation

For a comprehensive user guide, including a full list of features and hotkeys, please see the [User Manual](doc/readme.md).

## Prerequisites

To compile Taskmon from source, you need [Zig](https://ziglang.org/) installed and on your system path. No Visual Studio or Windows SDK install is required — Zig brings its own Windows headers and import libraries.

Optionally, install [Pandoc](https://pandoc.org/) and [Inno Setup](https://jrsoftware.org/isinfo.php) to also build the HTML user manual and the Windows installer; both are auto-detected and skipped if not found.

## Building

From the repository root:

```batch
zig build
```

When the build is finished, the executable will be located in zig-out\bin.

## License

This project is licensed under the MIT License.
