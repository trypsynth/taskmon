# Taskmon User Manual

Welcome to the Taskmon user manual. Taskmon is designed to be a fast and keyboard-friendly alternative to the standard Windows Task Manager.

## Core Features

* View all running processes and sort them by various resource usage metrics.
* Choose from a large variety of customizable columns to display, including PID, CPU, Memory, Threads, Handles, Command Line, Disk I/O, and many more.
* Minimize to the system tray to keep your taskbar clean.
* Hover over the system tray icon to quickly view CPU and memory usage.
* Suspend, resume, or terminate processes directly from the list.
* Change the priority class of any running process.
* Launch new tasks directly from the application.
* Keep Taskmon Always on Top via the View menu.
* Configurable auto-refresh interval (Off, 5 seconds, 10 seconds, 30 seconds, 1 minute).
* Remembers your window size, position, and column preferences across sessions.
* Option to disable the end task confirmation prompt for faster workflow.

## Column Reordering and Accessible Sorting

Taskmon has robust support for customizing how data is displayed, built specifically with accessibility in mind.

* Drag and drop: You can drag and drop column headers with the mouse to reorder them to your liking.
* Accessible sorting: Screen reader users can press Shift+Tab from the process list to focus a specialized set of hidden radio buttons. From there, use the Left and Right arrow keys to instantly change which column the list is sorted by. Pressing Enter will toggle the sort order between ascending and descending.

## Keyboard Shortcuts

Taskmon supports the following keyboard shortcuts for quick navigation and control:

* Ctrl+Shift+~: Global hotkey to toggle Taskmon visibility from anywhere.
* F5: Refresh the process list manually.
* Ctrl+N: Open the Run dialog to start a new task.
* Ctrl+,: Open the Settings dialog to customize columns and refresh rates.
* Delete: End the currently selected task.

## Context Menu Actions

Bringing up the context menu on a process in the list provides access to several actions:

* Open file location: Opens Windows Explorer to the directory containing the executable.
* Suspend or Resume: Pauses or resumes the execution of the process.
* End task: Forcefully terminates the process.
* Priority: Allows changing the CPU priority class (Idle, Below Normal, Normal, Above Normal, High, Realtime).

## Changelog

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
