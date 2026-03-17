#pragma once
#include <windows.h>

inline constexpr wchar_t k_class_name[]   = L"TaskmonWndClass";
inline constexpr wchar_t k_window_title[] = L"Taskmon";

LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
