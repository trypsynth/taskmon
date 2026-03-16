#include <windows.h>
#include "wndproc.hpp"

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, LPWSTR, int show) {
	WNDCLASSEX wc{};
	wc.cbSize = sizeof(wc);
	wc.style = CS_HREDRAW | CS_VREDRAW;
	wc.lpfnWndProc = wnd_proc;
	wc.hInstance = instance;
	wc.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
	wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
	wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
	wc.lpszClassName = L"TaskmonWndClass";
	wc.hIconSm = LoadIconW(nullptr, IDI_APPLICATION);
	if (!RegisterClassEx(&wc)) {
		MessageBox(nullptr, L"Failed to register window class.", L"Error", MB_ICONERROR);
		return 1;
	}
	RECT rc{0, 0, 760, 560};
	AdjustWindowRect(&rc, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, FALSE);
	HWND hwnd = CreateWindowEx(0, L"TaskmonWndClass", L"Taskmon", WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT, rc.right - rc.left, rc.bottom - rc.top, nullptr, nullptr, instance, nullptr);
	if (!hwnd) {
		MessageBox(nullptr, L"Failed to create window.", L"Error", MB_ICONERROR);
		return 1;
	}
	ShowWindow(hwnd, show);
	UpdateWindow(hwnd);
	MSG msg{};
	while (GetMessageW(&msg, nullptr, 0, 0)) {
		if (!IsDialogMessageW(hwnd, &msg)) {
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
		}
	}
	return static_cast<int>(msg.wParam);
}
