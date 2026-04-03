#include "run.h"
#include "resource.h"
#include "theme.h"
#include <commdlg.h>
#include <shellapi.h>
#include <shlwapi.h>

static void browse_for_file(HWND hdlg) {
	wchar_t path[MAX_PATH] = {0};
	OPENFILENAME ofn = {0};
	ofn.lStructSize = sizeof(ofn);
	ofn.hwndOwner = hdlg;
	ofn.lpstrFilter = L"Programs (*.exe;*.bat;*.cmd)\0*.exe;*.bat;*.cmd\0All Files (*.*)\0*.*\0";
	ofn.lpstrFile = path;
	ofn.nMaxFile = MAX_PATH;
	ofn.Flags = OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;
	if (GetOpenFileName(&ofn))
		SetDlgItemText(hdlg, IDC_RUN_EDIT, path);
}

static void run_command(HWND hdlg) {
	wchar_t cmd[MAX_PATH] = {0};
	GetDlgItemText(hdlg, IDC_RUN_EDIT, cmd, MAX_PATH);
	PathRemoveBlanks(cmd);
	if (!cmd[0]) return;
	SHELLEXECUTEINFO sei = {0};
	sei.cbSize = sizeof(sei);
	sei.fMask = SEE_MASK_DOENVSUBST;
	sei.hwnd = hdlg;
	sei.lpVerb = L"open";
	sei.lpFile = cmd;
	sei.nShow = SW_SHOWNORMAL;
	// ShellExecuteEx shows its own error dialog on failure, just keep ours open
	if (ShellExecuteEx(&sei))
		EndDialog(hdlg, 1);
}

static INT_PTR CALLBACK run_dlg_proc(HWND hdlg, UINT msg, WPARAM wp, LPARAM lp) {
	UNREFERENCED_PARAMETER(lp);
	switch (msg) {
	case WM_INITDIALOG:
		theme_apply_titlebar(hdlg);
		SendDlgItemMessage(hdlg, IDC_RUN_EDIT, EM_SETLIMITTEXT, MAX_PATH - 1, 0);
		EnableWindow(GetDlgItem(hdlg, IDOK), FALSE);
		return TRUE;
	case WM_COMMAND:
		if (LOWORD(wp) == IDC_RUN_EDIT && HIWORD(wp) == EN_CHANGE) {
			BOOL has_text = GetWindowTextLength(GetDlgItem(hdlg, IDC_RUN_EDIT)) > 0;
			EnableWindow(GetDlgItem(hdlg, IDOK), has_text);
			return TRUE;
		}
		if (LOWORD(wp) == IDC_RUN_BROWSE) {
			browse_for_file(hdlg);
			return TRUE;
		}
		if (LOWORD(wp) == IDOK) {
			run_command(hdlg);
			return TRUE;
		}
		if (LOWORD(wp) == IDCANCEL) {
			EndDialog(hdlg, 0);
			return TRUE;
		}
		break;
	case WM_CTLCOLORDLG: {
		HBRUSH br = theme_bg_brush();
		if (br) return (INT_PTR)br;
		break;
	}
	case WM_CTLCOLORSTATIC:
	case WM_CTLCOLORBTN:
	case WM_CTLCOLOREDIT: {
		HBRUSH br = theme_ctl_color((HDC)wp);
		if (br) return (INT_PTR)br;
		break;
	}
	}
	return FALSE;
}

void open_run_dialog(HWND parent) {
	DialogBoxParam(GetModuleHandle(NULL), MAKEINTRESOURCE(IDD_RUN), parent, run_dlg_proc, 0);
}
