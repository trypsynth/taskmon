#include "treeview.h"
#include "wndproc.h"
#include "process.h"
#include "tray.h"
#include <commctrl.h>

// Use W-suffixed macros explicitly to avoid issues with ANSI fallback
#define TV_GetItem(h, p)    SendMessage((h), TVM_GETITEMW,    0, (LPARAM)(TVITEMW*)(p))
#define TV_InsertItem(h, p) (HTREEITEM)SendMessage((h), TVM_INSERTITEMW, 0, (LPARAM)(TVINSERTSTRUCTW*)(p))
#define TV_GetChild(h, i)   (HTREEITEM)SendMessage((h), TVM_GETNEXTITEM, (WPARAM)TVGN_CHILD,   (LPARAM)(i))
#define TV_GetSibling(h, i) (HTREEITEM)SendMessage((h), TVM_GETNEXTITEM, (WPARAM)TVGN_NEXT,    (LPARAM)(i))
#define TV_GetRoot(h)       (HTREEITEM)SendMessage((h), TVM_GETNEXTITEM, (WPARAM)TVGN_ROOT,    0)
#define TV_GetSel(h)        (HTREEITEM)SendMessage((h), TVM_GETNEXTITEM, (WPARAM)TVGN_CARET,   0)
#define TV_Select(h, i)     SendMessage((h), TVM_SELECTITEM, (WPARAM)TVGN_CARET, (LPARAM)(i))
#define TV_EnsureVis(h, i)  SendMessage((h), TVM_ENSUREVISIBLE, 0, (LPARAM)(i))
#define TV_Expand(h, i, f)  SendMessage((h), TVM_EXPAND, (WPARAM)(f), (LPARAM)(i))
#define TV_DeleteAll(h)     SendMessage((h), TVM_DELETEITEM, 0, (LPARAM)TVI_ROOT)
#define TV_HitTest(h, p)    (HTREEITEM)SendMessage((h), TVM_HITTEST, 0, (LPARAM)(TVHITTESTINFO*)(p))
#define TV_GetItemRect(h,i,rc,code) (BOOL)SendMessage((h), TVM_GETITEMRECT, (WPARAM)(BOOL)(code), (LPARAM)(RECT*)(rc))

#define MAX_EXPANDED 512

static DWORD s_expanded_pids[MAX_EXPANDED];
static int   s_expanded_count;
static DWORD s_selected_pid;

static void collect_state(HTREEITEM item) {
	while (item) {
		TVITEMW tvi = {0};
		tvi.mask      = TVIF_PARAM | TVIF_STATE;
		tvi.hItem     = item;
		tvi.stateMask = TVIS_EXPANDED;
		TV_GetItem(g_hwnd_tree, &tvi);
		if ((tvi.state & TVIS_EXPANDED) && s_expanded_count < MAX_EXPANDED)
			s_expanded_pids[s_expanded_count++] = (DWORD)tvi.lParam;
		collect_state(TV_GetChild(g_hwnd_tree, item));
		item = TV_GetSibling(g_hwnd_tree, item);
	}
}

static HTREEITEM find_by_pid(HTREEITEM item, DWORD pid) {
	while (item) {
		TVITEMW tvi = {0};
		tvi.mask  = TVIF_PARAM;
		tvi.hItem = item;
		TV_GetItem(g_hwnd_tree, &tvi);
		if ((DWORD)tvi.lParam == pid) return item;
		HTREEITEM found = find_by_pid(TV_GetChild(g_hwnd_tree, item), pid);
		if (found) return found;
		item = TV_GetSibling(g_hwnd_tree, item);
	}
	return NULL;
}

static void restore_expanded(HTREEITEM item) {
	while (item) {
		TVITEMW tvi = {0};
		tvi.mask  = TVIF_PARAM;
		tvi.hItem = item;
		TV_GetItem(g_hwnd_tree, &tvi);
		for (int i = 0; i < s_expanded_count; i++) {
			if (s_expanded_pids[i] == (DWORD)tvi.lParam) {
				TV_Expand(g_hwnd_tree, item, TVE_EXPAND);
				break;
			}
		}
		restore_expanded(TV_GetChild(g_hwnd_tree, item));
		item = TV_GetSibling(g_hwnd_tree, item);
	}
}

static BOOL pid_in_list(DWORD pid, const process_entry* entries, int count) {
	for (int i = 0; i < count; i++)
		if (entries[i].pid == pid) return TRUE;
	return FALSE;
}

static void insert_children(HTREEITEM parent, DWORD parent_pid,
                             process_entry* entries, int count, BOOL* done) {
	for (int i = 0; i < count; i++) {
		if (done[i] || entries[i].parent_pid != parent_pid) continue;
		done[i] = TRUE;
		TVINSERTSTRUCTW tvis = {0};
		tvis.hParent          = parent;
		tvis.hInsertAfter     = TVI_SORT;
		tvis.item.mask        = TVIF_TEXT | TVIF_PARAM;
		tvis.item.pszText     = entries[i].name;
		tvis.item.lParam      = (LPARAM)entries[i].pid;
		HTREEITEM hc = TV_InsertItem(g_hwnd_tree, &tvis);
		if (hc) insert_children(hc, entries[i].pid, entries, count, done);
	}
}

static void insert_root(process_entry* e, process_entry* entries, int count, BOOL* done) {
	TVINSERTSTRUCTW tvis = {0};
	tvis.hParent      = TVI_ROOT;
	tvis.hInsertAfter = TVI_SORT;
	tvis.item.mask    = TVIF_TEXT | TVIF_PARAM;
	tvis.item.pszText = e->name;
	tvis.item.lParam  = (LPARAM)e->pid;
	HTREEITEM hr = TV_InsertItem(g_hwnd_tree, &tvis);
	if (hr) insert_children(hr, e->pid, entries, count, done);
}

double populate_tree_view(process_entry* entries, int count) {
	// Save current UI state
	HTREEITEM old_sel = TV_GetSel(g_hwnd_tree);
	s_selected_pid = 0;
	if (old_sel) {
		TVITEMW tvi = {0};
		tvi.mask  = TVIF_PARAM;
		tvi.hItem = old_sel;
		TV_GetItem(g_hwnd_tree, &tvi);
		s_selected_pid = (DWORD)tvi.lParam;
	}
	s_expanded_count = 0;
	collect_state(TV_GetRoot(g_hwnd_tree));

	SendMessage(g_hwnd_tree, WM_SETREDRAW, FALSE, 0);
	TV_DeleteAll(g_hwnd_tree);

	BOOL* done = (BOOL*)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, count * sizeof(BOOL));
	if (done) {
		// Roots: parent is zero, self-referential, or not present in list
		for (int i = 0; i < count; i++) {
			if (done[i]) continue;
			DWORD ppid = entries[i].parent_pid;
			if (ppid == 0 || ppid == entries[i].pid || !pid_in_list(ppid, entries, count)) {
				done[i] = TRUE;
				insert_root(&entries[i], entries, count, done);
			}
		}
		// Orphaned/cycle entries become roots too
		for (int i = 0; i < count; i++) {
			if (!done[i]) {
				done[i] = TRUE;
				insert_root(&entries[i], entries, count, done);
			}
		}
		HeapFree(GetProcessHeap(), 0, done);
	}

	restore_expanded(TV_GetRoot(g_hwnd_tree));

	HTREEITEM sel_item = s_selected_pid
		? find_by_pid(TV_GetRoot(g_hwnd_tree), s_selected_pid)
		: NULL;
	if (sel_item) {
		TV_Select(g_hwnd_tree, sel_item);
		TV_EnsureVis(g_hwnd_tree, sel_item);
	} else {
		HTREEITEM root = TV_GetRoot(g_hwnd_tree);
		if (root) TV_Select(g_hwnd_tree, root);
	}

	SendMessage(g_hwnd_tree, WM_SETREDRAW, TRUE, 0);
	InvalidateRect(g_hwnd_tree, NULL, FALSE);

	double total = 0;
	for (int i = 0; i < count; i++)
		if (entries[i].pid != 0) total += entries[i].cpu_percent;
	tray_update_tip(total);
	return total;
}

// Terminates children bottom-up so parents outlive their children as briefly as possible
void terminate_tree_from_item(HTREEITEM item) {
	if (!item) return;
	HTREEITEM child = TV_GetChild(g_hwnd_tree, item);
	while (child) {
		HTREEITEM next = TV_GetSibling(g_hwnd_tree, child);
		terminate_tree_from_item(child);
		child = next;
	}
	TVITEMW tvi = {0};
	tvi.mask  = TVIF_PARAM;
	tvi.hItem = item;
	TV_GetItem(g_hwnd_tree, &tvi);
	terminate_process((DWORD)tvi.lParam);
}

LRESULT CALLBACK tree_key_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR data) {
	UNREFERENCED_PARAMETER(id); UNREFERENCED_PARAMETER(data);
	if (msg == WM_KEYDOWN && wp == VK_ESCAPE) {
		PostMessage(GetParent(hwnd), WM_HIDE_TO_TRAY, 0, 0);
		return 0;
	}
	return DefSubclassProc(hwnd, msg, wp, lp);
}

// Returns the PID from the tree item currently selected, 0 if none
DWORD tree_get_selected_pid(void) {
	HTREEITEM sel = TV_GetSel(g_hwnd_tree);
	if (!sel) return 0;
	TVITEMW tvi = {0};
	tvi.mask  = TVIF_PARAM;
	tvi.hItem = sel;
	TV_GetItem(g_hwnd_tree, &tvi);
	return (DWORD)tvi.lParam;
}

// Writes the text label of the selected tree item into buf (the process name)
void tree_get_selected_name(wchar_t* buf, int cch) {
	buf[0] = L'\0';
	HTREEITEM sel = TV_GetSel(g_hwnd_tree);
	if (!sel) return;
	TVITEMW tvi = {0};
	tvi.mask       = TVIF_TEXT;
	tvi.hItem      = sel;
	tvi.pszText    = buf;
	tvi.cchTextMax = cch;
	TV_GetItem(g_hwnd_tree, &tvi);
}

HTREEITEM tree_get_selection(void) {
	return TV_GetSel(g_hwnd_tree);
}
