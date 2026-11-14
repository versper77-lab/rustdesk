import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// K2K builds are published as GitHub releases tagged `k2k-b<build number>`.
const String _kK2kLatestApi =
    'https://api.github.com/repos/versper77-lab/rustdesk/releases/latest';
const String kK2kDownloadPage =
    'https://github.com/versper77-lab/rustdesk/releases/latest';

int? _parseBuild(String tag) {
  final m = RegExp(r'^k2k-b(\d+)$').firstMatch(tag.trim());
  return m == null ? null : int.tryParse(m.group(1)!);
}

Future<int?> _fetchLatestBuild() async {
  try {
    final resp = await http
        .get(Uri.parse(_kK2kLatestApi),
            headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final body = jsonDecode(resp.body);
    if (body is! Map) return null;
    return _parseBuild((body['tag_name'] ?? '').toString());
  } catch (e) {
    debugPrint('K2K update check failed: $e');
    return null;
  }
}

/// Shows a small "new K2K version" banner when a newer release exists.
class K2kUpdateCard extends StatefulWidget {
  const K2kUpdateCard({Key? key}) : super(key: key);

  @override
  State<K2kUpdateCard> createState() => _K2kUpdateCardState();
}

class _K2kUpdateCardState extends State<K2kUpdateCard> {
  int? _latest;
  bool _closed = false;

  int get _current => int.tryParse(bind.mainGetCustomBuildNo()) ?? 0;

  @override
  void initState() {
    super.initState();
    if (_current > 0) {
      _fetchLatestBuild().then((v) {
        if (mounted && v != null) setState(() => _latest = v);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = _latest;
    if (_closed || latest == null || latest <= _current) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: MyTheme.accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MyTheme.accent.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.system_update, color: MyTheme.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${translate('New K2K version available')} (b$_current → b$latest)',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => launchUrl(Uri.parse(kK2kDownloadPage),
                mode: LaunchMode.externalApplication),
            child: Text(translate('Download')),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() => _closed = true),
          ),
        ],
      ),
    );
  }
}
