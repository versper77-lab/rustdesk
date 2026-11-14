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
  ffi.dialogManager.show((setState, close, context) {
    return _PickBody(ffi: ffi, close: close);
  });
}

class _PickBody extends StatefulWidget {
  final FFI ffi;
  final VoidCallback close;
  const _PickBody({required this.ffi, required this.close});

  @override
  State<_PickBody> createState() => _PickBodyState();
}

class _PickBodyState extends State<_PickBody> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await _ask(widget.ffi);
    if (!mounted) return;
    setState(() {
      _data = d;
      _loading = false;
    });
  }

  Future<void> _pick(String exe) async {
    setState(() => _busy = true);
    final d = await _ask(widget.ffi, pick: exe);
    if (!mounted) return;
    setState(() => _busy = false);
    final err = (d?['error'] ?? '').toString();
    if (d == null) {
      showToast(translate('k2k_pick_no_reply'));
    } else if (err.isEmpty) {
      showToast(translate(exe.isEmpty ? 'Whole screen' : 'k2k_pick_done'));
      widget.close();
    } else {
      showToast(translate(err == 'not_allowed'
          ? 'k2k_pick_not_allowed'
          : 'k2k_pick_not_found'));
      setState(() => _data = d);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_data == null) {
      body = Center(child: Text(translate('k2k_pick_no_reply')));
    } else if (_data!['allowed'] != true) {
      body = Center(child: Text(translate('k2k_pick_not_allowed')));
    } else {
      final current = (_data!['current'] ?? '').toString().toLowerCase();
      final seen = <String>{};
      final windows = ((_data!['windows'] as List?) ?? [])
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
            subtitle: sub.isEmpty
                ? null
                : Text(sub, overflow: TextOverflow.ellipsis),
            selected: current == exe.toLowerCase(),
            onTap: _busy ? null : () => _pick(exe),
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
        dialogButton('Refresh', onPressed: () {
          setState(() => _loading = true);
          _load();
        }, isOutline: true),
        dialogButton('Close', onPressed: widget.close),
      ],
      onCancel: widget.close,
    );
  }
}
