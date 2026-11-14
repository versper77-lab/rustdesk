import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';

// K2K mobile remote screen: labeled bottom bar, shortcut sheet, "more" sheet
// with risky actions kept apart, and screen rotation.

const String _kOrientationOption = 'k2k-remote-orientation';
const String _kCustomShortcutsOption = 'k2k-custom-shortcuts';
const Color _kDanger = Color(0xFFE5484D);

// ---------------------------------------------------------------- rotation

List<DeviceOrientation> _orientationsFor(String mode) {
  switch (mode) {
    case 'landscape':
      return [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight
      ];
    case 'portrait':
      return [DeviceOrientation.portraitUp];
    default:
      return DeviceOrientation.values;
  }
}

String k2kOrientationMode() {
  final v = bind.mainGetLocalOption(key: _kOrientationOption);
  return (v == 'landscape' || v == 'portrait') ? v : 'auto';
}

void k2kApplyRemoteOrientation() {
  SystemChrome.setPreferredOrientations(_orientationsFor(k2kOrientationMode()));
}

void k2kResetOrientation() {
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
}

Future<void> _setOrientationMode(String mode) async {
  await bind.mainSetLocalOption(key: _kOrientationOption, value: mode);
  k2kApplyRemoteOrientation();
}

// ---------------------------------------------------------------- bottom bar

class K2kRemoteBar extends StatelessWidget {
  final bool showInput;
  final bool touchMode;
  final bool isPeerAndroid;
  final VoidCallback onKeyboard;
  final VoidCallback onMouse;
  final VoidCallback onShortcuts;
  final VoidCallback onDisplay;
  final VoidCallback onMore;
  final VoidCallback? onCollapse;

  const K2kRemoteBar({
    Key? key,
    required this.showInput,
    required this.touchMode,
    required this.isPeerAndroid,
    required this.onKeyboard,
    required this.onMouse,
    required this.onShortcuts,
    required this.onDisplay,
    required this.onMore,
    required this.onCollapse,
  }) : super(key: key);

  Widget _item(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 2),
              Text(translate(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      elevation: 10,
      color: MyTheme.accent,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            if (showInput)
              _item(Icons.keyboard_rounded, 'Keyboard', onKeyboard),
            if (showInput)
              isPeerAndroid
                  ? _item(Icons.smartphone_rounded, 'Phone keys', onMouse)
                  : _item(
                      touchMode ? Icons.touch_app_rounded : Icons.mouse_rounded,
                      touchMode ? 'Touch' : 'Mouse',
                      onMouse),
            if (showInput && !isPeerAndroid)
              _item(Icons.keyboard_command_key_rounded, 'Shortcuts',
                  onShortcuts),
            _item(Icons.desktop_windows_rounded, 'Display', onDisplay),
            _item(Icons.more_horiz_rounded, 'More', onMore),
            if (onCollapse != null)
              SizedBox(
                width: 40,
                child: IconButton(
                  icon: const Icon(Icons.expand_more, color: Colors.white),
                  tooltip: translate('Hide'),
                  onPressed: onCollapse,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- shortcuts

class _Shortcut {
  final String label;
  final String key; // input key name, or 'CtrlAltDel' / 'LockScreen'
  final bool ctrl, alt, shift, win;
  final bool custom;
  const _Shortcut(this.label, this.key,
      {this.ctrl = false,
      this.alt = false,
      this.shift = false,
      this.win = false,
      this.custom = false});

  bool get usesSystemKeys => win || (alt && key == 'VK_TAB') || key == 'CtrlAltDel';

  String combo(bool isMac) {
    final parts = <String>[
      if (ctrl) isMac ? 'Cmd' : 'Ctrl',
      if (alt) isMac ? 'Option' : 'Alt',
      if (shift) 'Shift',
      if (win) isMac ? 'Ctrl' : 'Win',
    ];
    if (key == 'CtrlAltDel') return 'Ctrl+Alt+Del';
    if (key == 'LockScreen') return isMac ? 'Ctrl+Cmd+Q' : 'Win+L';
    parts.add(_keyLabel(key));
    return parts.join('+');
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'key': key,
        'ctrl': ctrl,
        'alt': alt,
        'shift': shift,
        'win': win,
      };

  static _Shortcut? fromJson(dynamic j) {
    if (j is! Map) return null;
    final key = (j['key'] ?? '').toString();
    if (key.isEmpty) return null;
    return _Shortcut((j['label'] ?? '').toString(), key,
        ctrl: j['ctrl'] == true,
        alt: j['alt'] == true,
        shift: j['shift'] == true,
        win: j['win'] == true,
        custom: true);
  }
}

String _keyLabel(String key) {
  const names = {
    'VK_ESCAPE': 'Esc',
    'VK_TAB': 'Tab',
    'VK_ENTER': 'Enter',
    'VK_DELETE': 'Del',
    'VK_BACK': 'Backspace',
    'VK_HOME': 'Home',
    'VK_END': 'End',
    'VK_PRIOR': 'PgUp',
    'VK_NEXT': 'PgDn',
    'VK_LEFT': '←',
    'VK_RIGHT': '→',
    'VK_UP': '↑',
    'VK_DOWN': '↓',
    'VK_SPACE': 'Space',
    'VK_SNAPSHOT': 'PrtScr',
  };
  if (names.containsKey(key)) return names[key]!;
  return key.startsWith('VK_') ? key.substring(3) : key;
}

const _editShortcuts = [
  _Shortcut('Copy', 'VK_C', ctrl: true),
  _Shortcut('Paste', 'VK_V', ctrl: true),
  _Shortcut('Cut', 'VK_X', ctrl: true),
  _Shortcut('Undo', 'VK_Z', ctrl: true),
  _Shortcut('Select all', 'VK_A', ctrl: true),
  _Shortcut('Save', 'VK_S', ctrl: true),
  _Shortcut('Find', 'VK_F', ctrl: true),
];

const _windowShortcuts = [
  _Shortcut('Switch window', 'VK_TAB', alt: true),
  _Shortcut('Show desktop', 'VK_D', win: true),
  _Shortcut('Close window', 'VK_F4', alt: true),
  _Shortcut('File explorer', 'VK_E', win: true),
  _Shortcut('Screen capture', 'VK_S', win: true, shift: true),
];

const _systemShortcuts = [
  _Shortcut('Task manager', 'VK_ESCAPE', ctrl: true, shift: true),
  _Shortcut('Lock screen', 'LockScreen'),
  _Shortcut('Ctrl+Alt+Del', 'CtrlAltDel'),
];

const _pickKeys = [
  'VK_A', 'VK_B', 'VK_C', 'VK_D', 'VK_E', 'VK_F', 'VK_G', 'VK_H', 'VK_I', //
  'VK_J', 'VK_K', 'VK_L', 'VK_M', 'VK_N', 'VK_O', 'VK_P', 'VK_Q', 'VK_R',
  'VK_S', 'VK_T', 'VK_U', 'VK_V', 'VK_W', 'VK_X', 'VK_Y', 'VK_Z',
  'VK_0', 'VK_1', 'VK_2', 'VK_3', 'VK_4', 'VK_5', 'VK_6', 'VK_7', 'VK_8',
  'VK_9', 'VK_F1', 'VK_F2', 'VK_F3', 'VK_F4', 'VK_F5', 'VK_F6', 'VK_F7',
  'VK_F8', 'VK_F9', 'VK_F10', 'VK_F11', 'VK_F12', 'VK_ESCAPE', 'VK_TAB',
  'VK_ENTER', 'VK_SPACE', 'VK_BACK', 'VK_DELETE', 'VK_HOME', 'VK_END',
  'VK_PRIOR', 'VK_NEXT', 'VK_LEFT', 'VK_RIGHT', 'VK_UP', 'VK_DOWN',
  'VK_SNAPSHOT',
];

List<_Shortcut> _loadCustom() {
  try {
    final raw = bind.mainGetLocalOption(key: _kCustomShortcutsOption);
    if (raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map(_Shortcut.fromJson)
        .whereType<_Shortcut>()
        .toList();
  } catch (e) {
    debugPrint('K2K custom shortcuts unreadable: $e');
    return [];
  }
}

Future<void> _saveCustom(List<_Shortcut> list) => bind.mainSetLocalOption(
    key: _kCustomShortcutsOption,
    value: jsonEncode(list.map((e) => e.toJson()).toList()));

void _send(_Shortcut s, bool isMac) {
  final im = gFFI.inputModel;
  final sid = gFFI.sessionId;
  if (s.key == 'CtrlAltDel') {
    bind.sessionCtrlAltDel(sessionId: sid);
    return;
  }
  if (s.key == 'LockScreen') {
    bind.sessionLockScreen(sessionId: sid);
    return;
  }
  final old = [im.ctrl, im.alt, im.shift, im.command];
  // On a Mac peer the "Ctrl" shortcuts mean Cmd, and "Win" means Ctrl.
  im.ctrl = isMac ? s.win : s.ctrl;
  im.command = isMac ? s.ctrl : s.win;
  im.alt = s.alt;
  im.shift = s.shift;
  im.inputKey(s.key);
  im.ctrl = old[0];
  im.alt = old[1];
  im.shift = old[2];
  im.command = old[3];
}

void showK2kShortcutSheet(BuildContext context) {
  final pi = gFFI.ffiModel.pi;
  final isMac = pi.platform == kPeerPlatformMacOS;
  final appMode = pi.platformAdditions['k2k_app_mode'] == true;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final custom = _loadCustom();
      Widget chip(_Shortcut s) {
        final blocked = appMode && s.usesSystemKeys;
        return Opacity(
          opacity: blocked ? 0.4 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: blocked
                ? () => showToast(translate('k2k_shortcut_blocked'))
                : () => _send(s, isMac),
            onLongPress: !s.custom
                ? null
                : () async {
                    final ok = await _confirm(ctx, translate('Delete'),
                        '${translate(s.label)} (${s.combo(isMac)})');
                    if (ok) {
                      final next = _loadCustom()
                        ..removeWhere((e) =>
                            e.label == s.label && e.combo(isMac) == s.combo(isMac));
                      await _saveCustom(next);
                      setState(() {});
                    }
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: MyTheme.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.custom ? s.label : translate(s.label),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(s.combo(isMac),
                      style: TextStyle(
                          fontSize: 10, color: Theme.of(ctx).hintColor)),
                ],
              ),
            ),
          ),
        );
      }

      Widget group(String title, List<_Shortcut> list, {Widget? trailing}) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(translate(title),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (trailing != null) trailing,
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: list.map(chip).toList()),
            ],
          ),
        );
      }

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: Theme.of(ctx).hintColor.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              group('k2k_my_shortcuts', custom,
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(translate('Add')),
                    onPressed: () async {
                      final s = await _editShortcut(ctx, isMac);
                      if (s != null) {
                        await _saveCustom(_loadCustom()..add(s));
                        setState(() {});
                      }
                    },
                  )),
              group('Edit', _editShortcuts),
              group('Window', _windowShortcuts),
              group('System', _systemShortcuts),
              if (appMode)
                Text(translate('k2k_shortcut_blocked'),
                    style:
                        TextStyle(fontSize: 11, color: Theme.of(ctx).hintColor)),
            ],
          ),
        ),
      );
    }),
  );
}

Future<_Shortcut?> _editShortcut(BuildContext context, bool isMac) {
  final name = TextEditingController();
  var ctrl = true, alt = false, shift = false, win = false;
  var key = 'VK_A';
  return showDialog<_Shortcut>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      Widget mod(String label, bool v, ValueChanged<bool> on) => FilterChip(
            label: Text(label),
            selected: v,
            onSelected: (x) => setState(() => on(x)),
          );
      final preview = _Shortcut('', key,
          ctrl: ctrl, alt: alt, shift: shift, win: win, custom: true);
      return AlertDialog(
        title: Text(translate('k2k_add_shortcut')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(
                    labelText: translate('Name'), hintText: 'Excel 합계'),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                mod(isMac ? 'Cmd' : 'Ctrl', ctrl, (x) => ctrl = x),
                mod(isMac ? 'Option' : 'Alt', alt, (x) => alt = x),
                mod('Shift', shift, (x) => shift = x),
                mod(isMac ? 'Ctrl' : 'Win', win, (x) => win = x),
              ]),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: key,
                isExpanded: true,
                items: _pickKeys
                    .map((k) => DropdownMenuItem(
                        value: k, child: Text(_keyLabel(k))))
                    .toList(),
                onChanged: (v) => setState(() => key = v ?? key),
              ),
              const SizedBox(height: 8),
              Text(preview.combo(isMac),
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: MyTheme.accent)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(translate('Cancel'))),
          TextButton(
              onPressed: () {
                final label = name.text.trim().isEmpty
                    ? preview.combo(isMac)
                    : name.text.trim();
                Navigator.of(ctx).pop(_Shortcut(label, key,
                    ctrl: ctrl, alt: alt, shift: shift, win: win, custom: true));
              },
              child: Text(translate('OK'))),
        ],
      );
    }),
  );
}

// ---------------------------------------------------------------- more sheet

Future<bool> _confirm(BuildContext context, String title, String body,
    {bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(translate('Cancel'))),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(translate('OK'),
                style: TextStyle(color: danger ? _kDanger : null))),
      ],
    ),
  );
  return ok == true;
}

/// "More" sheet: everyday items first, then disconnect / restart / power off
/// grouped at the bottom in red, each behind a confirmation.
void showK2kMoreSheet(
  BuildContext context, {
  required String id,
  required VoidCallback? onChat,
  required VoidCallback onDisconnect,
}) {
  final ffi = gFFI;
  final pi = ffi.ffiModel.pi;
  final perms = ffi.ffiModel.permissions;
  final controls = toolbarControls(context, id, ffi);
  final canPower = ffi.ffiModel.keyboard &&
      perms['restart'] != false &&
      (pi.platform == kPeerPlatformWindows || pi.platform == kPeerPlatformLinux);
  final canRestart = perms['restart'] != false &&
      (pi.platform == kPeerPlatformLinux ||
          pi.platform == kPeerPlatformWindows ||
          pi.platform == kPeerPlatformMacOS);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) {
      void close() => Navigator.of(ctx).pop();
      Widget tile(IconData icon, String label, VoidCallback onTap,
          {Color? color, String? sub}) {
        return ListTile(
          dense: true,
          leading: Icon(icon, color: color ?? MyTheme.accent),
          title: Text(translate(label), style: TextStyle(color: color)),
          subtitle: sub == null ? null : Text(sub),
          onTap: () {
            close();
            onTap();
          },
        );
      }

      final mode = k2kOrientationMode();
      Widget orientChip(String value, String label, IconData icon) => ChoiceChip(
            avatar: Icon(icon, size: 16),
            label: Text(translate(label)),
            selected: mode == value,
            onSelected: (_) {
              _setOrientationMode(value);
              close();
            },
          );

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(translate('Screen rotation'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(spacing: 8, children: [
                  orientChip('auto', 'Auto', Icons.screen_rotation_rounded),
                  orientChip(
                      'landscape', 'Landscape', Icons.stay_current_landscape),
                  orientChip(
                      'portrait', 'Portrait', Icons.stay_current_portrait),
                ]),
              ),
              const Divider(),
              if (onChat != null)
                tile(Icons.chat_bubble_outline_rounded, 'Chat', onChat),
              ...controls
                  .where((m) => !m.divider && m.onPressed != null)
                  .where((m) {
                    final child = m.child;
                    return !(child is Text &&
                        child.data == translate('Restart remote device'));
                  })
                  .map((m) => ListTile(
                        dense: true,
                        title: m.child,
                        onTap: () {
                          close();
                          m.onPressed?.call();
                        },
                      )),
              const Divider(),
              tile(Icons.link_off_rounded, 'Disconnect', () async {
                if (await _confirm(context, translate('Disconnect'),
                    translate('k2k_confirm_disconnect'),
                    danger: true)) {
                  onDisconnect();
                }
              }, color: _kDanger),
              if (canRestart)
                tile(Icons.restart_alt_rounded, 'Restart remote device',
                    () async {
                  if (await _confirm(context, translate('Restart remote device'),
                      translate('k2k_confirm_restart'),
                      danger: true)) {
                    bind.sessionRestartRemoteDevice(sessionId: ffi.sessionId);
                  }
                }, color: _kDanger),
              if (canPower)
                tile(Icons.power_settings_new_rounded, 'k2k_power_off',
                    () async {
                  if (await _confirm(context, translate('k2k_power_off'),
                      translate('k2k_confirm_power_off'),
                      danger: true)) {
                    bind.sessionPowerOffRemoteDevice(sessionId: ffi.sessionId);
                  }
                }, color: _kDanger),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
