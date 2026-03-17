#include "wndproc.hpp"
#include <windows.h>

static constexpr wchar_t k_mutex_name[] = L"Local\\TaskmonSingleInstance";

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, LPWSTR, int show) {
	HANDLE mutex = CreateMutex(nullptr, TRUE, k_mutex_name);
	if (GetLastError() == ERROR_ALREADY_EXISTS) {
		HWND existing = FindWindow(k_class_name, nullptr);
		if (existing) { ShowWindow(existing, SW_SHOW); SetForegroundWindow(existing); }
		if (mutex) CloseHandle(mutex);
		return 0;
	}

	WNDCLASSEX wc{};
	wc.cbSize        = sizeof(wc);
	wc.style         = CS_HREDRAW | CS_VREDRAW;
	wc.lpfnWndProc   = wnd_proc;
	wc.hInstance     = instance;
	wc.hIcon         = LoadIcon(nullptr, IDI_APPLICATION);
	wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
	wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
	wc.lpszClassName = k_class_name;
	wc.hIconSm       = LoadIcon(nullptr, IDI_APPLICATION);
	if (!RegisterClassEx(&wc)) { MessageBox(nullptr, L"Failed to register window class.", L"Error", MB_ICONERROR); return 1; }

	RECT rc{ 0, 0, 760, 560 };
	AdjustWindowRect(&rc, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, FALSE);
	HWND hwnd = CreateWindowEx(0, k_class_name, k_window_title, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT, rc.right - rc.left, rc.bottom - rc.top, nullptr, nullptr, instance, nullptr);
	if (!hwnd) { MessageBox(nullptr, L"Failed to create window.", L"Error", MB_ICONERROR); return 1; }

	ShowWindow(hwnd, show);
	UpdateWindow(hwnd);
	MSG msg{};
	while (GetMessage(&msg, nullptr, 0, 0)) {
		if (!IsDialogMessage(hwnd, &msg)) {
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
	}
	CloseHandle(mutex);
	return static_cast<int>(msg.wParam);
}
