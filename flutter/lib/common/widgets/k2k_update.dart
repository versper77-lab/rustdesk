import 'dart:convert';
import 'dart:io';

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
const String _kK2kChangelog =
    'https://raw.githubusercontent.com/versper77-lab/rustdesk/k2k/k2k-changelog.json';
const String _kK2kWindowsZip =
    'https://github.com/versper77-lab/rustdesk/releases/latest/download/K2K-windows-x64.zip';

/// Windows: downloads the latest zip, then hands over to a small script that
/// waits for K2K to close, puts the new files in place (portable: this
/// folder; installed: a silent re-install, one UAC prompt) and starts K2K again.
Future<String?> _k2kSelfUpdateWindows(void Function(String) progress) async {
  final tmp = await Directory.systemTemp.createTemp('k2k_update');
  final zip = File('${tmp.path}\\K2K-windows-x64.zip');
  final client = http.Client();
  try {
    progress(translate('k2k_update_downloading'));
    final resp = await client.send(http.Request('GET', Uri.parse(_kK2kWindowsZip)));
    if (resp.statusCode != 200) return 'HTTP ${resp.statusCode}';
    final total = resp.contentLength ?? 0;
    var got = 0;
    final sink = zip.openWrite();
    await for (final chunk in resp.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) {
        progress('${translate('k2k_update_downloading')} ${(got * 100 ~/ total)}%');
      }
    }
    await sink.close();
  } catch (e) {
    return e.toString();
  } finally {
    client.close();
  }

  final exe = Platform.resolvedExecutable;
  final dir = File(exe).parent.path;
  // Only treat this copy as the installed one when it actually runs from
  // Program Files; an unzipped copy elsewhere is updated in its own folder
  // even if K2K is also installed on this PC.
  final pf = (Platform.environment['ProgramFiles'] ?? 'C:\\Program Files')
      .toLowerCase();
  final installed =
      bind.mainIsInstalled() && dir.toLowerCase().startsWith(pf);
  final unpacked = '${tmp.path}\\new';
  final script = File('${tmp.path}\\k2k_update.cmd');
  final lines = <String>[
    '@echo off',
    'timeout /t 2 /nobreak >nul',
    'powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "Expand-Archive -Force -LiteralPath \'${zip.path}\' -DestinationPath \'$unpacked\'"',
    if (installed) ...[
      'powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "(Start-Process -FilePath \'$unpacked\\K2K.exe\' -ArgumentList \'--silent-install\' -Verb RunAs -PassThru).WaitForExit()"',
      'start "" "$exe"',
    ]
    else ...[
      'taskkill /f /pid $pid >nul 2>&1',
      // Stop only copies running from this folder, never the installed service.
      'powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "Get-Process K2K,rustdesk -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like \'$dir\\*\' } | Stop-Process -Force"',
      'timeout /t 1 /nobreak >nul',
      'xcopy /e /y /q /i "$unpacked\\*" "$dir\\" >nul',
      'start "" "$dir\\K2K.exe"',
    ],
  ];
  await script.writeAsString(lines.join('\r\n'));
  progress(translate('k2k_update_installing'));
  await Process.start('cmd.exe', ['/c', script.path],
      mode: ProcessStartMode.detached, runInShell: false);
  if (!installed) {
    await Future.delayed(const Duration(milliseconds: 500));
    exit(0);
  }
  return null;
}

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
  String? _status;
  bool _busy = false;

  Future<void> _update() async {
    if (!isWindows) {
      launchUrl(Uri.parse(kK2kDownloadPage),
          mode: LaunchMode.externalApplication);
      return;
    }
    setState(() => _busy = true);
    final err = await _k2kSelfUpdateWindows((m) {
      if (mounted) setState(() => _status = m);
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = err == null
          ? translate('k2k_update_installing')
          : '${translate('k2k_update_failed')} ($err)';
    });
  }

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
      // Always show which K2K build is running.
      if (_current <= 0) return const SizedBox.shrink();
      return InkWell(
        onTap: () => showK2kChangelog(context, _current),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 14, 10),
        child: Text(
          latest != null && latest <= _current
              ? 'K2K b$_current · ${translate('k2k_up_to_date')}'
              : 'K2K b$_current',
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color
                  ?.withOpacity(0.7),
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted),
        ),
        ),
      );
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
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 4),
              child: Text(_status!, style: const TextStyle(fontSize: 12)),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => showK2kChangelog(context, _current),
                child: Text(translate('k2k_changelog')),
              ),
              TextButton.icon(
              icon: const Icon(Icons.download_rounded, size: 16),
              label: Text(translate(isWindows ? 'k2k_update_now' : 'Download')),
              onPressed: _busy ? null : _update,
            ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows what changed in each K2K build (newest first). Builds newer than
/// [current] are marked as not installed yet.
Future<void> showK2kChangelog(BuildContext context, int current) async {
  List<dynamic>? entries;
  try {
    final resp = await http
        .get(Uri.parse(_kK2kChangelog))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode == 200) {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is List) entries = body;
    }
  } catch (e) {
    debugPrint('K2K changelog fetch failed: $e');
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(translate('k2k_changelog')),
      content: SizedBox(
        width: 460,
        height: 420,
        child: entries == null
            ? Center(child: Text(translate('k2k_changelog_failed')))
            : ListView(
                children: [
                  for (final e in entries!)
                    if (e is Map)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text('b${e['b']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(width: 8),
                              Text('${e['date'] ?? ''}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(ctx).hintColor)),
                              const SizedBox(width: 8),
                              if (e['b'] is int && e['b'] == current)
                                _k2kTag(translate('k2k_changelog_current'),
                                    MyTheme.accent),
                              if (e['b'] is int && (e['b'] as int) > current)
                                _k2kTag(translate('k2k_changelog_new'),
                                    Colors.orange),
                            ]),
                            const SizedBox(height: 4),
                            for (final item in (e['items'] as List? ?? []))
                              Padding(
                                padding:
                                    const EdgeInsets.only(left: 6, top: 2),
                                child: Text('• $item',
                                    style: const TextStyle(fontSize: 13)),
                              ),
                          ],
                        ),
                      ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(translate('Close')),
        ),
      ],
    ),
  );
}

Widget _k2kTag(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
