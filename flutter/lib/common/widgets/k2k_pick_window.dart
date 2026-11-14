import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

// K2K: the controller chooses which program window a Windows host shares.
// The host answers with its window list (see src/server/k2k_remote_pick.rs).

Future<Map<String, dynamic>?> _ask(FFI ffi, {String? pick}) async {
  final sid = ffi.sessionId;
  bind.sessionTakeShareableWindows(sessionId: sid); // drop a stale reply
  if (pick == null) {
    await bind.sessionRequestShareableWindows(sessionId: sid);
  } else {
    await bind.sessionPickSharedWindow(sessionId: sid, exe: pick);
  }
  for (var i = 0; i < 25; i++) {
    await Future.delayed(const Duration(milliseconds: 200));
    final raw = bind.sessionTakeShareableWindows(sessionId: sid);
    if (raw.isEmpty) continue;
    try {
      final v = jsonDecode(raw);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (e) {
      debugPrint('K2K window list unreadable: $e');
    }
    return null;
  }
  return null;
}

void showK2kPickWindowDialog(FFI ffi) {
  Map<String, dynamic>? data;
  var loading = true;
  var busy = false;
  var started = false;
  var open = true;
  ffi.dialogManager.show((setState, close, context) {
    void refresh() {
      if (open) setState(() {});
    }

    void done() {
      open = false;
      close();
    }

    Future<void> load() async {
      loading = true;
      refresh();
      data = await _ask(ffi);
      loading = false;
      refresh();
    }

    Future<void> pick(String exe) async {
      busy = true;
      refresh();
      final d = await _ask(ffi, pick: exe);
      busy = false;
      final err = (d?['error'] ?? '').toString();
      if (d == null) {
        showToast(translate('k2k_pick_no_reply'));
        refresh();
      } else if (err.isEmpty) {
        showToast(translate(exe.isEmpty ? 'Whole screen' : 'k2k_pick_done'));
        done();
      } else {
        showToast(translate(err == 'not_allowed'
            ? 'k2k_pick_not_allowed'
            : 'k2k_pick_not_found'));
        data = d;
        refresh();
      }
    }

    if (!started) {
      started = true;
      Future.microtask(load);
    }

    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (data == null) {
      body = Center(child: Text(translate('k2k_pick_no_reply')));
    } else if (data!['allowed'] != true) {
      body = Center(child: Text(translate('k2k_pick_not_allowed')));
    } else {
      final current = (data!['current'] ?? '').toString().toLowerCase();
      final seen = <String>{};
      final windows = ((data!['windows'] as List?) ?? [])
          .whereType<Map>()
          .where((w) => seen.add((w['exe'] ?? '').toString().toLowerCase()))
          .toList();
      Widget tile(String title, String sub, String exe) => ListTile(
            dense: true,
            leading: Icon(
                exe.isEmpty
                    ? Icons.desktop_windows_rounded
                    : Icons.web_asset_rounded,
                color: MyTheme.accent),
            title: Text(title, overflow: TextOverflow.ellipsis),
            subtitle:
                sub.isEmpty ? null : Text(sub, overflow: TextOverflow.ellipsis),
            selected: current == exe.toLowerCase(),
            onTap: busy ? null : () => pick(exe),
          );
      body = ListView(children: [
        tile(translate('Whole screen'), '', ''),
        const Divider(),
        ...windows.map((w) => tile((w['title'] ?? '').toString(),
            (w['exe'] ?? '').toString(), (w['exe'] ?? '').toString())),
      ]);
    }
    return CustomAlertDialog(
      title: Text(translate('k2k_pick_program')),
      content: SizedBox(width: 420, height: 360, child: body),
      actions: [
        dialogButton('Refresh', onPressed: load, isOutline: true),
        dialogButton('Close', onPressed: done),
      ],
      onCancel: done,
    );
  });
}
