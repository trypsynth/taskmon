# Taskmon

Taskmon is a lightweight and fast task manager alternative for Windows. It provides a clean interface for monitoring system resources, managing running processes, viewing active tasks, and controlling system performance without unnecessary overhead.

## Documentation

For a comprehensive user guide, including a full list of features and hotkeys, please see the [User Manual](doc/readme.md).

## Prerequisites

To compile Taskmon from source, you need to have the following tools installed on your system:

* Visual Studio Build Tools with C support.
* Windows SDK.
* CMake, version 3.20 or higher. Make sure CMake is in your system path.

## Building

Once the dependencies are installed, you can build the application by running the following commands in the repository root:

```batch
mkdir build
cd build
cmake ..
cmake --build . --config Release
```

When the build is finished, the executable will be located in the build\Release directory.

## License

This project is licensed under the MIT License.
