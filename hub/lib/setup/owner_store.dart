import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Compte propriétaire, créé au premier allumage depuis l'iPhone.
class Owner {
  const Owner({
    required this.firstName,
    required this.lastName,
    required this.nickname,
    this.photoPath,
    this.pinSalt,
    this.pinHash,
  });

  final String firstName;
  final String lastName;
  final String nickname;
  final String? photoPath;

  /// Code à 4 chiffres du propriétaire, jamais stocké en clair : sel + SHA-256.
  final String? pinSalt;
  final String? pinHash;

  bool get hasPin => pinHash != null;

  static String hashPin(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  static bool validPin(String? pin) => pin != null && RegExp(r'^\d{4}$').hasMatch(pin);

  bool checkPin(String pin) => pinSalt != null && pinHash == hashPin(pin, pinSalt!);

  Owner withPin(String pin) {
    final r = Random.secure();
    final salt = base64Url.encode(List.generate(16, (_) => r.nextInt(256)));
    return Owner(
      firstName: firstName,
      lastName: lastName,
      nickname: nickname,
      photoPath: photoPath,
      pinSalt: salt,
      pinHash: hashPin(pin, salt),
    );
  }

  Map<String, Object?> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
    'nickname': nickname,
    'photo': photoPath,
    'pinSalt': pinSalt,
    'pinHash': pinHash,
  };

  static Owner fromJson(Map<String, Object?> j) => Owner(
    firstName: j['firstName'] as String? ?? '',
    lastName: j['lastName'] as String? ?? '',
    nickname: j['nickname'] as String? ?? '',
    photoPath: j['photo'] as String?,
    pinSalt: j['pinSalt'] as String?,
    pinHash: j['pinHash'] as String?,
  );
}

/// Stockage du propriétaire sur la partition /data (ou un dossier local en dev).
class OwnerStore {
  OwnerStore._(this.dir);

  final Directory dir;

  static OwnerStore? _instance;

  /// Dossier de données : DARTOS_DATA, sinon /data/thibsdarts sur le Pi, sinon ~/.dartos en dev.
  static OwnerStore get instance {
    final env = Platform.environment['DARTOS_DATA'];
    final home = Platform.environment['HOME'] ?? '.';
    final path = env ?? (Directory('/data').existsSync() ? '/data/thibsdarts' : '$home/.dartos');
    return _instance ??= OwnerStore._(Directory(path));
  }

  /// Tests et outils : force le dossier de données.
  static void useDirectory(String path) => _instance = OwnerStore._(Directory(path));

  File get _file => File('${dir.path}/owner.json');
  File get photoFile => File('${dir.path}/owner.jpg');

  Owner? load() {
    try {
      if (!_file.existsSync()) return null;
      return Owner.fromJson(jsonDecode(_file.readAsStringSync()) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  Future<void> savePhoto(List<int> bytes) async {
    await dir.create(recursive: true);
    await photoFile.writeAsBytes(bytes, flush: true);
  }

  Future<Owner> save({
    required String firstName,
    required String lastName,
    required String nickname,
    String? pin,
  }) async {
    var owner = Owner(
      firstName: firstName,
      lastName: lastName,
      nickname: nickname,
      photoPath: photoFile.existsSync() ? photoFile.path : null,
    );
    if (pin != null) owner = owner.withPin(pin);
    return write(owner);
  }

  Future<Owner> write(Owner owner) async {
    await dir.create(recursive: true);
    await _file.writeAsString(jsonEncode(owner.toJson()), flush: true);
    return owner;
  }
}
