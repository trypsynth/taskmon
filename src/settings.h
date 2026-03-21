#pragma once
#include "process.h"

#define SORT_COUNT 4

typedef struct {
	sort_field field;
	BOOL desc[SORT_COUNT];
	UINT refresh_ms;
} sort_prefs;

#define REFRESH_OPTION_COUNT 5
extern const UINT REFRESH_MS[REFRESH_OPTION_COUNT];
extern const wchar_t* const REFRESH_LABELS[REFRESH_OPTION_COUNT];

void settings_load(sort_prefs* prefs, const wchar_t** labels, const sort_field* fields);
void settings_save(const sort_prefs* prefs, const wchar_t** labels, const sort_field* fields);

// Opens the settings dialog. Returns the selected refresh_ms, or (UINT)-1 if cancelled.
UINT open_settings(HWND parent, UINT current_ms);
