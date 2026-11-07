import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../game_config.dart';
import '../setup/owner_store.dart';

/// Un joueur connu de la cible : identifiant fixe, surnom, photo, code à 4 chiffres.
///
/// Le propriétaire est un profil comme les autres (id "owner") avec en plus les droits sur la cible.
/// Un pote sans appli a un profil sans code : il pourra le réclamer depuis l'appli.
class Profile {
  Profile({
    required this.id,
    required this.nickname,
    this.owner = false,
    this.pinSalt,
    this.pinHash,
    List<String>? tokens,
  }) : tokens = tokens ?? [];

  final String id;
  String nickname;
  final bool owner;
  String? pinSalt;
  String? pinHash;

  /// Empreintes des clés données aux iPhone connectés à ce profil.
  final List<String> tokens;

  bool get hasPin => pinHash != null;

  static String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

  static bool validPin(String? pin) => pin != null && RegExp(r'^\d{4}$').hasMatch(pin);

  bool checkPin(String pin) => pinSalt != null && pinHash == _hash('$pinSalt:$pin');

  void setPin(String pin) {
    pinSalt = _random(16);
    pinHash = _hash('$pinSalt:$pin');
  }

  /// Nouvelle clé pour un iPhone. Seule son empreinte est gardée.
  String issueToken() {
    final t = _random(24);
    tokens.add(_hash(t));
    while (tokens.length > 10) {
      tokens.removeAt(0);
    }
    return t;
  }

  bool checkToken(String? t) => t != null && t.isNotEmpty && tokens.contains(_hash(t));

  static String _random(int n) {
    final r = Random.secure();
    return base64Url.encode(List.generate(n, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'nickname': nickname,
    'owner': owner,
    'pinSalt': pinSalt,
    'pinHash': pinHash,
    'tokens': tokens,
  };

  static Profile fromJson(Map<String, Object?> j) => Profile(
    id: j['id'] as String,
    nickname: j['nickname'] as String? ?? '',
    owner: j['owner'] == true,
    pinSalt: j['pinSalt'] as String?,
    pinHash: j['pinHash'] as String?,
    tokens: [for (final t in j['tokens'] as List? ?? const []) t as String],
  );
}

/// Les profils de la cible, dans players.json (partition /data sur le Pi), photos dans players/.
class PlayerStore {
  PlayerStore._();

  static final PlayerStore instance = PlayerStore._();

  Directory get _dir => OwnerStore.instance.dir;
  File get _file => File('${_dir.path}/players.json');
  Directory get photos => Directory('${_dir.path}/players');

  String? _loadedFrom;
  final List<Profile> _all = [];

  /// Profils, le propriétaire d'abord.
  List<Profile> get all {
    _ensure();
    return List.unmodifiable(_all);
  }

  Profile? byId(String? id) => id == null ? null : all.where((p) => p.id == id).firstOrNull;

  Profile? byName(String name) {
    final n = name.trim().toLowerCase();
    return all.where((p) => p.nickname.toLowerCase() == n).firstOrNull;
  }

  Profile? get owner => byId('owner');

  File photoFile(String id) {
    if (id == 'owner') return OwnerStore.instance.photoFile;
    return File('${photos.path}/${id.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '')}.jpg');
  }

  String? photoPath(String id) {
    final f = photoFile(id);
    return f.existsSync() ? f.path : null;
  }

  /// Charge players.json (une fois par dossier de données) et y place le propriétaire du setup.
  void _ensure() {
    if (_loadedFrom == _dir.path) return;
    _loadedFrom = _dir.path;
    _all.clear();
    try {
      if (_file.existsSync()) {
        final j = jsonDecode(_file.readAsStringSync()) as Map<String, Object?>;
        for (final p in j['players'] as List? ?? const []) {
          _all.add(Profile.fromJson(p as Map<String, Object?>));
        }
      }
    } catch (_) {}
    final o = AppState.ownerProfile;
    if (o != null && owner == null) {
      // Cible installée avant les profils : le propriétaire garde son code s'il en avait un.
      _all.insert(
        0,
        Profile(id: 'owner', nickname: AppState.owner, owner: true, pinSalt: o.pinSalt, pinHash: o.pinHash),
      );
      _saveSync();
    }
  }

  /// Setup terminé : le profil du propriétaire reprend le surnom et le code choisis.
  Future<Profile> syncOwner(Owner o) async {
    _ensure();
    var p = owner;
    if (p == null) {
      p = Profile(id: 'owner', nickname: AppState.owner, owner: true);
      _all.insert(0, p);
    }
    p
      ..nickname = AppState.owner
      ..pinSalt = o.pinSalt
      ..pinHash = o.pinHash
      ..tokens.clear();
    await save();
    return p;
  }

  /// Nouveau profil. [id] reprend l'identifiant d'un ancien iPhone pour garder ses parties.
  Future<Profile> create(String nickname, {String? pin, String? id}) async {
    _ensure();
    final wanted = id != null && RegExp(r'^[A-Za-z0-9-]{8,64}$').hasMatch(id) && byId(id) == null;
    final p = Profile(id: wanted ? id : _newId(), nickname: nickname.trim());
    if (pin != null) p.setPin(pin);
    _all.add(p);
    await save();
    return p;
  }

  String _newId() {
    final r = Random.secure();
    String id;
    do {
      id = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
    } while (byId(id) != null);
    return id;
  }

  Future<void> save() async {
    await _dir.create(recursive: true);
    await _file.writeAsString(jsonEncode({'players': _all.map((p) => p.toJson()).toList()}), flush: true);
  }

  void _saveSync() {
    try {
      _dir.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode({'players': _all.map((p) => p.toJson()).toList()}), flush: true);
    } catch (_) {}
  }

  /// Fiche publique d'un profil (jamais le code ni les clés).
  Map<String, Object?> public(Profile p) => {
    'id': p.id,
    'nickname': p.nickname,
    'owner': p.owner,
    'pin': p.hasPin,
    'photo': photoPath(p.id) != null,
  };
}
