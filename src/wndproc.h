#pragma once
#include <windows.h>

extern const wchar_t CLASS_NAME[];
extern const wchar_t WINDOW_TITLE[];

LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
