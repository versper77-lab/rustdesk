import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

// Host option read by src/server/k2k_app_mode.rs. Empty means the whole screen.
const String kK2kAppTargetOption = 'k2k-app-target';

/// K2K: choose whether a peer sees the whole screen or a single program window.
class K2kAppShareCard extends StatefulWidget {
  const K2kAppShareCard({Key? key}) : super(key: key);

  @override
  State<K2kAppShareCard> createState() => _K2kAppShareCardState();
}

class _K2kAppShareCardState extends State<K2kAppShareCard> {
  String _target = '';

  @override
  void initState() {
    super.initState();
    _target = bind.mainGetOptionSync(key: kK2kAppTargetOption);
  }

  Future<void> _setTarget(String exe) async {
    await bind.mainSetOption(key: kK2kAppTargetOption, value: exe);
    if (mounted) {
      setState(() => _target = exe);
    }
  }

  Future<void> _pick() async {
    final raw = await bind.mainGetShareableWindows();
    var items = <Map<String, dynamic>>[];
    try {
      items = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('failed to parse shareable windows: $e');
    }
    final seen = <String>{};
    items = items
        .where((e) => seen.add((e['exe'] ?? '').toString().toLowerCase()))
        .toList();
    gFFI.dialogManager.show((setState, close, context) {
      Widget tile(String title, String subtitle, String value) {
        return ListTile(
          dense: true,
          leading: Icon(
              value.isEmpty ? Icons.desktop_windows : Icons.web_asset,
              color: MyTheme.accent),
          title: Text(title, overflow: TextOverflow.ellipsis),
          subtitle: subtitle.isEmpty
              ? null
              : Text(subtitle, overflow: TextOverflow.ellipsis),
          selected: _target.toLowerCase() == value.toLowerCase(),
          onTap: () {
            close();
            _setTarget(value);
          },
        );
      }

      return CustomAlertDialog(
        title: Text(translate('Share scope')),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView(
            children: [
              tile(translate('Whole screen'), '', ''),
              const Divider(),
              ...items.map((e) => tile(
                    (e['title'] ?? '').toString(),
                    (e['exe'] ?? '').toString(),
                    (e['exe'] ?? '').toString(),
                  )),
            ],
          ),
        ),
        actions: [dialogButton('Cancel', onPressed: close, isOutline: true)],
        onCancel: close,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = _target.isEmpty ? translate('Whole screen') : _target;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 16, bottom: 10),
      child: InkWell(
        onTap: _pick,
        child: Row(
          children: [
            Icon(_target.isEmpty ? Icons.desktop_windows : Icons.web_asset,
                size: 16, color: MyTheme.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    translate('Share scope'),
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color),
                  ),
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}
