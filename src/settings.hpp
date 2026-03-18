#pragma once
#include "process.hpp"

inline constexpr int k_sort_count = 4;

struct sort_prefs {
	sort_field field             = sort_field::name;
	bool       desc[k_sort_count] = {};
	UINT       refresh_ms        = 2000;
};

sort_prefs settings_load(const wchar_t** labels, const sort_field* fields);
void       settings_save(const sort_prefs& prefs, const wchar_t** labels, const sort_field* fields);
