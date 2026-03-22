#include <windows.h>

// CRT stubs required by MSVC
#pragma function(memset)
void* memset(void* dest, int c, size_t count) {
	unsigned char* p = (unsigned char*)dest;
	while (count--) *p++ = (unsigned char)c;
	return dest;
}

#pragma function(memcpy)
void* memcpy(void* dest, const void* src, size_t count) {
	unsigned char* d = (unsigned char*)dest;
	const unsigned char* s = (const unsigned char*)src;
	while (count--) *d++ = *s++;
	return dest;
}

#pragma function(memmove)
void* memmove(void* dest, const void* src, size_t count) {
	unsigned char* d = (unsigned char*)dest;
	const unsigned char* s = (const unsigned char*)src;
	if (d < s) {
		while (count--) *d++ = *s++;
	} else {
		d += count;
		s += count;
		while (count--) *--d = *--s;
	}
	return dest;
}

// Global handle used by other parts
HINSTANCE g_instance;
// Magic symbol required by MSVC when using floating point in CRT-less build
int _fltused = 0x9875;

int WINAPI WinMain(HINSTANCE instance, HINSTANCE prev, LPSTR cmd_line, int show);

void __stdcall WinMainCRTStartup() {
	g_instance = GetModuleHandle(NULL);
	int show = SW_SHOWDEFAULT;
	STARTUPINFOW si;
	GetStartupInfo(&si);
	if (si.dwFlags & STARTF_USESHOWWINDOW) show = si.wShowWindow;
	int exit_code = WinMain(g_instance, NULL, NULL, show);
	ExitProcess(exit_code);
}
