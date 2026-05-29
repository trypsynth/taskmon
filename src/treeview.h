#pragma once
#include <windows.h>
#include <commctrl.h>
#include "process.h"

double populate_tree_view(process_entry* entries, int count);
void terminate_tree_from_item(HTREEITEM item);
DWORD tree_get_selected_pid(void);
void tree_get_selected_name(wchar_t* buf, int cch);
HTREEITEM tree_get_selection(void);
LRESULT CALLBACK tree_key_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data);
