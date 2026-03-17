#include "settings.hpp"
#include <windows.h>
#include <string>

static std::wstring ini_path() {
	wchar_t buf[MAX_PATH];
	GetModuleFileName(nullptr, buf, MAX_PATH);
	std::wstring p(buf);
	auto slash = p.find_last_of(L"\\/");
	if (slash != std::wstring::npos) p.resize(slash + 1);
	return p + L"taskmon.ini";
}

sort_prefs settings_load(const wchar_t** labels, const sort_field* fields) {
	auto path = ini_path();
	sort_prefs prefs;
	wchar_t field_buf[32];
	GetPrivateProfileString(L"sort", L"field", labels[0], field_buf, 32, path.c_str());
	for (int i = 0; i < k_sort_count; ++i)
		if (_wcsicmp(field_buf, labels[i]) == 0) { prefs.field = fields[i]; break; }
	for (int i = 0; i < k_sort_count; ++i) {
		wchar_t key[32], val[4];
		swprintf_s(key, L"%s_desc", labels[i]);
		GetPrivateProfileString(L"sort", key, L"0", val, 4, path.c_str());
		prefs.desc[i] = (val[0] == L'1');
	}
	return prefs;
}

void settings_save(const sort_prefs& prefs, const wchar_t** labels, const sort_field* fields) {
	auto path = ini_path();
	for (int i = 0; i < k_sort_count; ++i) {
		if (fields[i] == prefs.field) WritePrivateProfileString(L"sort", L"field", labels[i], path.c_str());
		wchar_t key[32];
		swprintf_s(key, L"%s_desc", labels[i]);
		WritePrivateProfileString(L"sort", key, prefs.desc[i] ? L"1" : L"0", path.c_str());
	}
}
