#pragma once
#include <windows.h>
#include "settings.h"
#include "process.h"

#define WM_HIDE_TO_TRAY (WM_APP + 2)

extern const wchar_t CLASS_NAME[];
extern const wchar_t WINDOW_TITLE[];

extern HWND g_hwnd;
extern HWND g_hwnd_list;
extern HWND g_hwnd_sort_group;
extern HWND g_hwnd_status;
extern HWND g_sort_btns[COL_COUNT];
extern column_id g_sort_btn_cols[COL_COUNT];
extern int g_sort_btn_count;
extern sort_prefs g_prefs;
extern snapshot_entry g_snapshots[SNAPSHOT_CAPACITY];

LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
