import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

String _kindLabel(String kind) {
  switch (kind) {
    case 'file_transfer':
      return translate('Transfer file');
    case 'view_camera':
      return translate('View camera');
    case 'terminal':
      return translate('Terminal');
    case 'port_forward':
      return translate('TCP tunneling');
    default:
      return translate('Remote desktop');
  }
}

Future<void> showK2kConnectionLog() async {
  final raw = await bind.mainGetConnectionLog();
  var items = <Map<String, dynamic>>[];
  try {
    items = (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  } catch (e) {
    debugPrint('failed to parse connection log: $e');
  }
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('Connection log')),
      content: SizedBox(
        width: 520,
        height: 380,
        child: items.isEmpty
            ? Center(child: Text(translate('No connections yet')))
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = items[i];
                  final name = (e['peer_name'] ?? '').toString();
                  final id = (e['peer_id'] ?? '').toString();
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.login, color: MyTheme.accent),
                    title: Text(name.isEmpty ? id : '$name ($id)',
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${e['time'] ?? ''} · ${_kindLabel((e['kind'] ?? '').toString())} · ${e['ip'] ?? ''} · ${e['peer_platform'] ?? ''}',
                        overflow: TextOverflow.ellipsis),
                  );
                },
              ),
      ),
      actions: [dialogButton('Close', onPressed: close)],
      onCancel: close,
    );
  });
}

/// Small link on the home page that opens the incoming connection log.
class K2kConnectionLogLink extends StatelessWidget {
  const K2kConnectionLogLink({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 16, bottom: 10),
      child: InkWell(
        onTap: showK2kConnectionLog,
        child: Row(
          children: [
            Icon(Icons.history, size: 16, color: MyTheme.accent),
            const SizedBox(width: 6),
            Text(translate('Connection log'),
                style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
