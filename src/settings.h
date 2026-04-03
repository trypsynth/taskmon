#pragma once
#include "process.h"

typedef enum {
	COL_NAME = 0,
	COL_PID,
	COL_CPU,
	COL_MEMORY,
	COL_THREADS,
	COL_HANDLES,
	COL_STARTTIME,
	COL_PRIORITY,
	COL_DISK_IO,
	COL_PRIVATE_BYTES,
	COL_PAGE_FAULTS,
	COL_USER,
	COL_CMDLINE,
	COL_ARCH,
	COL_SESSION,
	COL_PEAK_WORKING_SET,
	COL_VIRTUAL_MEM,
	COL_GDI_OBJECTS,
	COL_USER_OBJECTS,
	COL_INTEGRITY,
	COL_COUNT,
} column_id;

typedef struct {
	const wchar_t* label;
	const wchar_t* header;
	int width;
	sort_field field;
	BOOL always_visible;
	BOOL default_visible;
} column_def;

extern const column_def COLUMNS[COL_COUNT];

typedef struct {
	sort_field field;
	BOOL desc[COL_COUNT];
	UINT refresh_ms;
	BOOL visible[COL_COUNT];
	BOOL skip_kill_confirm;
	BOOL always_on_top;
	int window_left, window_top, window_width, window_height;
} sort_prefs;

#define REFRESH_OPTION_COUNT 5
extern const UINT REFRESH_MS[REFRESH_OPTION_COUNT];
extern const wchar_t* const REFRESH_LABELS[REFRESH_OPTION_COUNT];

void settings_load(sort_prefs* prefs);
void settings_save(const sort_prefs* prefs);
BOOL open_settings(HWND parent, UINT current_ms, const BOOL* current_visible, BOOL current_skip_confirm, UINT* out_ms, BOOL* out_visible, BOOL* out_skip_confirm);
