#include "settings.h"
#include <shlwapi.h>

static void get_ini_path(wchar_t* buf) {
	GetModuleFileName(NULL, buf, MAX_PATH);
	PathRemoveFileSpec(buf);
	PathAppend(buf, L"taskmon.ini");
}

void settings_load(sort_prefs* prefs, const wchar_t** labels, const sort_field* fields) {
	wchar_t path[MAX_PATH];
	get_ini_path(path);
	prefs->field = fields[0];
	prefs->refresh_ms = 0;
	for (int i = 0; i < SORT_COUNT; i++) prefs->desc[i] = FALSE;
	wchar_t field_buf[32];
	GetPrivateProfileString(L"sort", L"field", labels[0], field_buf, 32, path);
	for (int i = 0; i < SORT_COUNT; i++) {
		if (StrCmpI(field_buf, labels[i]) == 0) {
			prefs->field = fields[i];
			break;
		}
	}
	for (int i = 0; i < SORT_COUNT; i++) {
		wchar_t key[32], val[4];
		wnsprintf(key, 32, L"%s_desc", labels[i]);
		GetPrivateProfileString(L"sort", key, L"0", val, 4, path);
		prefs->desc[i] = (val[0] == L'1');
	}
	wchar_t ms_buf[16];
	GetPrivateProfileString(L"refresh", L"interval_ms", L"2000", ms_buf, 16, path);
	prefs->refresh_ms = (UINT)StrToInt(ms_buf);
}

void settings_save(const sort_prefs* prefs, const wchar_t** labels, const sort_field* fields) {
	wchar_t path[MAX_PATH];
	get_ini_path(path);
	for (int i = 0; i < SORT_COUNT; i++) {
		if (fields[i] == prefs->field) WritePrivateProfileString(L"sort", L"field", labels[i], path);
		wchar_t key[32];
		wnsprintf(key, 32, L"%s_desc", labels[i]);
		WritePrivateProfileString(L"sort", key, prefs->desc[i] ? L"1" : L"0", path);
	}
	wchar_t ms_str[16];
	wnsprintf(ms_str, 16, L"%u", prefs->refresh_ms);
	WritePrivateProfileString(L"refresh", L"interval_ms", ms_str, path);
}
