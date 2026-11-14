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
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
      decoration: BoxDecoration(
        color: MyTheme.accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyTheme.accent.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.system_update, color: MyTheme.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  translate('New K2K version available'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _closed = true),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text('b$_current → b$latest',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.download_rounded, size: 16),
              label: Text(translate('Download')),
              onPressed: () => launchUrl(Uri.parse(kK2kDownloadPage),
                  mode: LaunchMode.externalApplication),
            ),
          ),
        ],
      ),
    );
  }
}
