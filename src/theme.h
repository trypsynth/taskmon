#pragma once
#include <windows.h>

void   theme_update(void);
BOOL   theme_is_dark(void);
void   theme_apply_titlebar(HWND hwnd);
void   theme_apply_listview(HWND hwnd_list);
void   theme_apply_button(HWND hwnd);
HBRUSH theme_ctl_color(HDC hdc);
HBRUSH theme_bg_brush(void);
