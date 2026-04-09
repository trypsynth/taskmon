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
