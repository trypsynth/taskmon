# Taskmon User Manual

Welcome to the Taskmon user manual. Taskmon is designed to be a fast and keyboard-friendly alternative to the standard Windows Task Manager.

## Core Features

* View all running processes and sort them by various resource usage metrics.
* Choose from over 45 customizable columns to display; see Available Columns below for the full list.
* Switch to a hierarchical Process Tree view to see which processes launched which; see Process Tree View below.
* Available as a portable executable or via a Windows installer. Portable copies keep their settings alongside the executable so you can carry them on a USB drive; installed copies store settings per-user automatically, since Program Files isn't writable without administrator rights.
* Optionally replace the system Task Manager during installation, so Ctrl+Shift+Esc and the taskbar's "Task Manager" entry open Taskmon instead.
* Minimize to the system tray to keep your taskbar clean.
* Optionally launch Taskmon already minimized to the tray, with no window shown on startup.
* Hover over the system tray icon to quickly view CPU and memory usage.
* Suspend, resume, or terminate processes directly from the list.
* Change the priority class of any running process.
* Launch new tasks directly from the application.
* Restart Taskmon as administrator from the File menu to manage processes you don't otherwise have access to.
* Keep Taskmon Always on Top via the View menu.
* Configurable auto-refresh interval (Off, 5 seconds, 10 seconds, 30 seconds, 1 minute).
* Remembers your window size, position, and column preferences across sessions.
* Option to disable the end task confirmation prompt for faster workflow.

## Process Tree View

Taskmon can display processes as a hierarchical tree instead of a flat list, grouping each process under the parent that launched it.

* Press Ctrl+T, or choose View > Process Tree, to toggle between the list and tree views.
* Expand or collapse a process's children using the tree's disclosure triangles or the keyboard.
* Right-click a process in tree view for an additional End process tree action, which terminates that process and all of its descendants, ending the children before their parents.

## Available Columns

All columns are optional except Name, which is always shown. Enable the ones you want from Settings (Ctrl+,); Name, PID, CPU %, and Memory are shown by default.

* Name: The process's executable name.
* PID: The unique numeric process ID assigned by Windows.
* CPU %: The percentage of total system CPU capacity the process is currently using.
* Memory: The process's current physical working set (RAM) usage.
* Threads: The number of threads currently running within the process.
* Handles: The number of open kernel object handles, such as files and registry keys, held by the process.
* Started: The date and time the process was launched.
* Priority: The process's CPU scheduling priority class.
* Disk I/O: The combined rate of disk read, write, and other I/O activity.
* Private Bytes: The amount of memory committed exclusively to the process.
* Page Faults: The rate of page faults per second, showing how often the process accesses memory outside its working set.
* User: The account under which the process is running.
* Command Line: The full command line, including arguments, the process was launched with.
* Architecture: Whether the process is running as x86, x64, or ARM64 code.
* Session: The Windows session ID the process belongs to.
* Peak Memory: The highest physical memory (working set) usage the process has reached.
* Virtual Memory: The total virtual address space reserved by the process.
* GDI Objects: The number of GDI graphics objects, such as brushes and pens, currently allocated by the process.
* USER Objects: The number of USER objects, such as windows and menus, currently allocated by the process.
* Integrity: The process's Windows integrity level, such as Low, Medium, High, or System.
* Parent PID: The process ID of the parent process that launched it.
* Private Working Set: The portion of physical memory used exclusively by this process, excluding memory shared with other processes.
* Paged Pool: The amount of pageable kernel memory allocated on the process's behalf.
* Non-paged Pool: The amount of non-pageable kernel memory allocated on the process's behalf.
* I/O Read: The rate of bytes read from disk or other I/O devices.
* I/O Write: The rate of bytes written to disk or other I/O devices.
* I/O Other: The rate of bytes transferred by I/O operations that are neither reads nor writes.
* Description: The file description recorded in the executable's version information.
* Company: The company name recorded in the executable's version information.
* DPI Awareness: How the process handles high-DPI displays: Unaware, System, or Per-Monitor.
* Service: The name of any Windows service or services hosted inside the process.
* GPU: The percentage of total GPU capacity the process is currently using, summed across all GPU engines.
* GPU Memory: The combined dedicated and shared GPU memory currently committed to the process.
* CPU Time: The total accumulated CPU time the process has consumed since it started.
* Elevated: Whether the process is running with administrator privileges.
* Path: The full file system path to the process's executable.
* Window Title: The title of the process's main visible window, if it has one.
* File Version: The file version recorded in the executable's version information.
* Product Version: The product version recorded in the executable's version information.
* Session Name: The friendly name of the Windows session the process belongs to, such as Console or Services.
* Package Name: The full package name for processes installed as a UWP or Store app, blank for regular Win32 processes.
* Peak Virtual Memory: The largest amount of virtual address space the process has reserved at any point since it started.
* Peak Private Bytes: The highest amount of memory the process has ever committed exclusively to itself.
* Peak Paged Pool: The highest amount of pageable kernel memory ever allocated on the process's behalf.
* Peak Non-paged Pool: The highest amount of non-pageable kernel memory ever allocated on the process's behalf.
* Peak Threads: The largest number of threads the process has had running at once since it started.

## Column Reordering and Accessible Sorting

Taskmon has robust support for customizing how data is displayed, built specifically with accessibility in mind.

* Drag and drop: You can drag and drop column headers with the mouse to reorder them to your liking.
* Accessible sorting: Screen reader users can press Shift+Tab from the process list to focus a specialized set of hidden radio buttons. From there, use the Left and Right arrow keys to instantly change which column the list is sorted by. Pressing Enter will toggle the sort order between ascending and descending.

## Keyboard Shortcuts

Taskmon supports the following keyboard shortcuts for quick navigation and control:

* Ctrl+Shift+~: Global hotkey to toggle Taskmon visibility from anywhere.
* F5: Refresh the process list manually.
* Ctrl+N: Open the Run dialog to start a new task.
* Ctrl+T: Toggle between the list and process tree views.
* Ctrl+,: Open the Settings dialog to customize columns and refresh rates.
* Delete: End the currently selected task.
* Escape: Hide Taskmon to the system tray.
* Ctrl+Q: Exit Taskmon completely.

## Context Menu Actions

Bringing up the context menu on a process in the list or tree view provides access to several actions:

* Open file location: Opens Windows Explorer to the directory containing the executable.
* Suspend or Resume: Pauses or resumes the execution of the process.
* End task: Forcefully terminates the process.
* End process tree: In the tree view only, terminates the selected process and all of its descendants, ending the children before their parents.
* Priority: Allows changing the CPU priority class (Idle, Below Normal, Normal, Above Normal, High, Realtime).

## Changelog

### Version 0.3.0
* Added Ctrl+Q as a shortcut to exit Taskmon completely.
* Added 11 new columns: Service, GPU, GPU Memory, CPU Time, Elevated, Path, Window Title, File Version, Product Version, Session Name, and Package Name.
* Added File > Restart as administrator to relaunch Taskmon elevated.
* Added a hierarchical Process Tree view (Ctrl+T) that groups processes under the parent that launched them, with an End process tree action that terminates a process and all of its descendants.
* Added an option to start Taskmon already minimized to the tray.
* Added a Windows installer alongside the existing portable version, with an option to replace the system Task Manager with Taskmon.
* Fixed a stack overflow that could occur when sorting by CPU usage.
* Fixed Ctrl+A not selecting all text in the Run dialog's edit box.

### Version 0.2.1
* Added support for ARM64 architecture.
* Releases are now packaged as ZIP files containing a standalone HTML user manual.
* Added 10 new columns: DPI Awareness, Company, Description, Parent PID, Private Working Set, Paged Pool, Nonpaged Pool, I/O Read, I/O Write, and I/O Other.
* Improved memory and I/O column formatting using standard Windows byte size strings.

### Version 0.2.0
* Added a basic status bar.
* Added a run dialog for launching new tasks.
* Added Always on Top and Remember Window Position options.
* Added 14 new columns: GDI objects, User objects, Integrity, Peak working set, Virtual memory size, Session, Architecture, User, Command line, Disk I/O, Private bytes, Page faults, Priority, and Process start time.
* Added the ability to suspend and resume processes.
* Added an option to change process priority.
* Fixed an issue where CPU usage showed 0% on first run.
* Fixed beep when pressing space after letter navigation in the settings column list.
* Removed duplicate error message when launching a program fails.
* Taskmon will now respect your system dark mode setting.

### Version 0.1.1
* Added an option to turn off the end task confirmation dialog.
* Added Ctrl+Shift+` as a global hotkey to toggle Taskmon's window from anywhere on your system.
* Column customization in the options dialog is now a proper list of checkboxes.
* Fixed the system tray icon showing incorrect memory usage statistics.
* Switched the end task key to Delete.
* The CPU percentage column now has a more human-friendly label.
* Various other small improvements, such as smartly selecting a process after one is killed and improved wording.

### Version 0.1.0
* Initial release.
