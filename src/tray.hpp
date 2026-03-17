#pragma once
#include <windows.h>

void tray_add(HWND hwnd, UINT callback_msg, const wchar_t* app_name);
void tray_remove();
void tray_update_tip(double cpu_pct, SIZE_T mem_bytes);
void tray_restore();
