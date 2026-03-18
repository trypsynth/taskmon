#include "wndproc.h"
#include <windows.h>
#include <objbase.h>

static const wchar_t MUTEX_NAME[] = L"Local\\TaskmonSingleInstance";

int WINAPI WinMain(HINSTANCE instance, HINSTANCE prev, LPSTR cmd_line, int show) {
	UNREFERENCED_PARAMETER(prev);
	UNREFERENCED_PARAMETER(cmd_line);
	HRESULT com_init = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
	HANDLE mutex = CreateMutex(NULL, TRUE, MUTEX_NAME);
	if (GetLastError() == ERROR_ALREADY_EXISTS) {
		HWND existing = FindWindow(CLASS_NAME, NULL);
		if (existing) {
			ShowWindow(existing, SW_SHOW);
			SetForegroundWindow(existing);
		}
		if (mutex) CloseHandle(mutex);
		if (SUCCEEDED(com_init)) CoUninitialize();
		return 0;
	}
	WNDCLASSEXW wc = {0};
	wc.cbSize = sizeof(wc);
	wc.style = CS_HREDRAW | CS_VREDRAW;
	wc.lpfnWndProc = wnd_proc;
	wc.hInstance = instance;
	wc.hIcon = LoadIcon(NULL, (LPCWSTR)IDI_APPLICATION);
	wc.hCursor = LoadCursor(NULL, (LPCWSTR)IDC_ARROW);
	wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
	wc.lpszClassName = CLASS_NAME;
	wc.hIconSm = LoadIcon(NULL, (LPCWSTR)IDI_APPLICATION);
	if (!RegisterClassEx(&wc)) {
		MessageBox(NULL, L"Failed to register window class.", L"Error", MB_ICONERROR);
		return 1;
	}
	RECT rc = { 0, 0, 760, 560 };
	AdjustWindowRect(&rc, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, FALSE);
	HWND hwnd = CreateWindowEx(0, CLASS_NAME, WINDOW_TITLE, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT, rc.right - rc.left, rc.bottom - rc.top, NULL, NULL, instance, NULL);
	if (!hwnd) {
		MessageBox(NULL, L"Failed to create window.", L"Error", MB_ICONERROR);
		return 1;
	}
	ShowWindow(hwnd, show);
	UpdateWindow(hwnd);
	MSG msg = {0};
	while (GetMessage(&msg, NULL, 0, 0)) {
		if (!IsDialogMessage(hwnd, &msg)) {
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
	}
	CloseHandle(mutex);
	if (SUCCEEDED(com_init)) CoUninitialize();
	return (int)msg.wParam;
}
