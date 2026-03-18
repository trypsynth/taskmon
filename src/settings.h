#pragma once
#include "process.h"

#define SORT_COUNT 4

typedef struct {
	sort_field field;
	BOOL desc[SORT_COUNT];
	UINT refresh_ms;
} sort_prefs;

void settings_load(sort_prefs* prefs, const wchar_t** labels, const sort_field* fields);
void settings_save(const sort_prefs* prefs, const wchar_t** labels, const sort_field* fields);
