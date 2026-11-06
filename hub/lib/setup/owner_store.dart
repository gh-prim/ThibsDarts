import 'dart:convert';
import 'dart:io';

/// Compte propriétaire, créé au premier allumage depuis l'iPhone.
class Owner {
  const Owner({required this.firstName, required this.lastName, required this.nickname, this.photoPath});

  final String firstName;
  final String lastName;
  final String nickname;
  final String? photoPath;

  Map<String, Object?> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
    'nickname': nickname,
    'photo': photoPath,
  };

  static Owner fromJson(Map<String, Object?> j) => Owner(
    firstName: j['firstName'] as String? ?? '',
    lastName: j['lastName'] as String? ?? '',
    nickname: j['nickname'] as String? ?? '',
    photoPath: j['photo'] as String?,
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

  Future<Owner> save({required String firstName, required String lastName, required String nickname}) async {
    await dir.create(recursive: true);
    final owner = Owner(
      firstName: firstName,
      lastName: lastName,
      nickname: nickname,
      photoPath: photoFile.existsSync() ? photoFile.path : null,
    );
    await _file.writeAsString(jsonEncode(owner.toJson()), flush: true);
    return owner;
  }
}
