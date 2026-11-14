import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

// Host option read by src/server/k2k_local_priority.rs ("N" turns it off).
const String kK2kLocalPriorityOption = 'k2k-local-priority';

const _kRadius = 14.0;

LinearGradient _k2kGradient() => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF5B3DF5), Color(0xFF8A5CFA)],
    );

void _copy(String text) {
  if (text.isEmpty) return;
  Clipboard.setData(ClipboardData(text: text));
  showToast(translate('Copied'));
}

/// K2K: "My device" card with the ID and password, replacing the plain boards.
class K2kMyDeviceCard extends StatelessWidget {
  final VoidCallback? onEditPassword;
  const K2kMyDeviceCard({Key? key, this.onEditPassword}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(builder: (context, model, _) {
        final showOneTime = model.approveMode != 'click' &&
            model.verificationMethod != kUsePermanentPassword;
        const white70 = TextStyle(color: Colors.white70, fontSize: 12);
        Widget iconBtn(IconData icon, String tip, VoidCallback onTap) {
          return Tooltip(
            message: translate(tip),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: BoxDecoration(
            gradient: _k2kGradient(),
            borderRadius: BorderRadius.circular(_kRadius),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5B3DF5).withOpacity(0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate('Your Desktop'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text(translate('ID'), style: white70),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      model.serverId.text,
                      maxLines: 1,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1),
                    ),
                  ),
                  iconBtn(Icons.copy_rounded, 'Copy',
                      () => _copy(model.serverId.text)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                  translate(
                      showOneTime ? 'One-time Password' : 'Password'),
                  style: white70),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      model.serverPasswd.text,
                      maxLines: 1,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (showOneTime)
                    iconBtn(Icons.copy_rounded, 'Copy',
                        () => _copy(model.serverPasswd.text)),
                  if (showOneTime)
                    iconBtn(Icons.refresh_rounded, 'Refresh Password',
                        () => bind.mainUpdateTemporaryPassword()),
                  if (onEditPassword != null && !bind.isDisableSettings())
                    iconBtn(Icons.edit_rounded, 'Change Password',
                        onEditPassword!),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// K2K: switch for "the person at this PC wins when both use the mouse".
class K2kLocalPrioritySwitch extends StatefulWidget {
  const K2kLocalPrioritySwitch({Key? key}) : super(key: key);

  @override
  State<K2kLocalPrioritySwitch> createState() => _K2kLocalPrioritySwitchState();
}

class _K2kLocalPrioritySwitchState extends State<K2kLocalPrioritySwitch> {
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _on = bind.mainGetOptionSync(key: kK2kLocalPriorityOption) != 'N';
  }

  Future<void> _set(bool v) async {
    await bind.mainSetOption(key: kK2kLocalPriorityOption, value: v ? '' : 'N');
    if (mounted) setState(() => _on = v);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 14, right: 8, bottom: 6),
      child: Row(
        children: [
          Icon(Icons.mouse_rounded, size: 16, color: MyTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(translate('Local input first'),
                style: const TextStyle(fontSize: 13)),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(value: _on, onChanged: _set),
          ),
        ],
      ),
    );
  }
}

// Host option read by src/server/k2k_remote_pick.rs ("N" forbids it).
const String kK2kRemotePickOption = 'k2k-remote-pick';

/// K2K: switch for "the controller may choose which program is shared".
class K2kRemotePickSwitch extends StatefulWidget {
  const K2kRemotePickSwitch({Key? key}) : super(key: key);

  @override
  State<K2kRemotePickSwitch> createState() => _K2kRemotePickSwitchState();
}

class _K2kRemotePickSwitchState extends State<K2kRemotePickSwitch> {
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _on = bind.mainGetOptionSync(key: kK2kRemotePickOption) != 'N';
  }

  Future<void> _set(bool v) async {
    await bind.mainSetOption(key: kK2kRemotePickOption, value: v ? '' : 'N');
    if (mounted) setState(() => _on = v);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 14, right: 8, bottom: 6),
      child: Row(
        children: [
          Icon(Icons.ads_click_rounded, size: 16, color: MyTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(translate('k2k_allow_remote_pick'),
                style: const TextStyle(fontSize: 13)),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(value: _on, onChanged: _set),
          ),
        ],
      ),
    );
  }
}

IconData _platformIcon(String platform) {
  final p = platform.toLowerCase();
  if (p.contains('android')) return Icons.phone_android_rounded;
  if (p.contains('ios')) return Icons.phone_iphone_rounded;
  if (p.contains('mac')) return Icons.laptop_mac_rounded;
  if (p.contains('linux')) return Icons.computer_rounded;
  return Icons.desktop_windows_rounded;
}

/// K2K: favorites shown as large one-click cards at the top of the home page.
class K2kFavoritesStrip extends StatefulWidget {
  const K2kFavoritesStrip({Key? key}) : super(key: key);

  @override
  State<K2kFavoritesStrip> createState() => _K2kFavoritesStripState();
}

class _K2kFavoritesStripState extends State<K2kFavoritesStrip> {
  @override
  void initState() {
    super.initState();
    bind.mainLoadFavPeers();
  }

  Widget _card(BuildContext context, Peer peer) {
    final name = peer.alias.isNotEmpty
        ? peer.alias
        : (peer.hostname.isNotEmpty ? peer.hostname : peer.id);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: theme.cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kRadius),
          side: BorderSide(color: MyTheme.accent.withOpacity(0.25)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(_kRadius),
          onTap: () => connect(context, peer.id),
          child: SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          gradient: _k2kGradient(),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_platformIcon(peer.platform),
                            size: 18, color: Colors.white),
                      ),
                      const Spacer(),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: peer.online
                              ? const Color(0xFF2FBF71)
                              : Colors.grey.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(peer.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: theme.hintColor)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.favoritePeersModel,
      child: Consumer<Peers>(builder: (context, model, _) {
        final peers = model.peers;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star_rounded,
                    size: 18, color: Color(0xFFFFB400)),
                const SizedBox(width: 4),
                Text(translate('Favorites'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            if (peers.isEmpty)
              Text(translate('k2k_fav_empty_tip'),
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).hintColor))
            else
              SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: peers.map((p) => _card(context, p)).toList(),
                ),
              ),
          ],
        );
      }),
    );
  }
}

// K2K key service on the K2K server (see k2k-server/k2k-keys.py).
const String kK2kKeyService = 'https://217-142-143-66.sslip.io';
const String kK2kLicenseKeyOption = 'k2k-license-key';

enum _KeyState { unknown, ok, missing, disabled }

/// K2K: asks for a K2K key until this device is activated on the server.
/// Only activated devices can receive connections once the server lock is on.
class K2kKeyCard extends StatefulWidget {
  const K2kKeyCard({Key? key}) : super(key: key);

  @override
  State<K2kKeyCard> createState() => _K2kKeyCardState();
}

class _K2kKeyCardState extends State<K2kKeyCard> {
  _KeyState _state = _KeyState.unknown;
  bool _busy = false;
  String _error = '';
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.text = bind.mainGetOptionSync(key: kK2kLicenseKeyOption);
    _check();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final id = await bind.mainGetMyId();
      if (id.isEmpty) return;
      final resp = await http
          .get(Uri.parse('$kK2kKeyService/api/status?id=${Uri.encodeQueryComponent(id)}'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body);
      if (body is! Map) return;
      final next = body['registered'] != true
          ? _KeyState.missing
          : (body['active'] == true ? _KeyState.ok : _KeyState.disabled);
      if (mounted) setState(() => _state = next);
    } catch (e) {
      debugPrint('K2K key status check failed: $e');
    }
  }

  String _platformName() {
    if (isWindows) return 'Windows';
    if (isAndroid) return 'Android';
    if (isMacOS) return 'macOS';
    if (isLinux) return 'Linux';
    if (isIOS) return 'iOS';
    return '';
  }

  Future<void> _activate() async {
    final key = _ctrl.text.trim();
    if (key.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final id = await bind.mainGetMyId();
      String host = '';
      try {
        host = Platform.localHostname;
      } catch (_) {}
      final resp = await http
          .post(Uri.parse('$kK2kKeyService/api/activate'),
              headers: {'Content-Type': 'application/json', 'X-K2K': '1'},
              body: jsonEncode({
                'key': key,
                'id': id,
                'name': host,
                'platform': _platformName(),
              }))
          .timeout(const Duration(seconds: 15));
      Map body = {};
      try {
        final b = jsonDecode(resp.body);
        if (b is Map) body = b;
      } catch (_) {}
      if (resp.statusCode == 200 && body['ok'] == true) {
        await bind.mainSetOption(key: kK2kLicenseKeyOption, value: key);
        if (mounted) setState(() => _state = _KeyState.ok);
        showToast(translate('k2k_key_activated'));
        return;
      }
      final err = (body['error'] ?? '').toString();
      final msg = {
            'invalid_key': 'k2k_key_invalid',
            'disabled': 'k2k_key_disabled',
            'limit': 'k2k_key_limit',
            'too_many': 'k2k_key_too_many',
          }[err] ??
          'k2k_key_failed';
      if (mounted) setState(() => _error = translate(msg));
    } catch (e) {
      if (mounted) setState(() => _error = translate('k2k_key_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _KeyState.unknown || _state == _KeyState.ok) {
      return const SizedBox.shrink();
    }
    final disabled = _state == _KeyState.disabled;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(_kRadius),
        border: Border.all(
            color: disabled
                ? const Color(0xFFE5484D)
                : MyTheme.accent.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(disabled ? Icons.block_rounded : Icons.vpn_key_rounded,
                  size: 18,
                  color: disabled ? const Color(0xFFE5484D) : MyTheme.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    translate(disabled ? 'k2k_key_disabled' : 'Enter K2K key'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(translate('k2k_key_tip'),
              style: TextStyle(fontSize: 12, color: theme.hintColor)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'K2K-XXXX-XXXX-XXXX',
              isDense: true,
            ),
            onSubmitted: (_) => _activate(),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFFE5484D))),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _activate,
              child: Text(translate(_busy ? 'Waiting' : 'Register')),
            ),
          ),
        ],
      ),
    );
  }
}
