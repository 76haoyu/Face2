import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/identity_model.dart';

/// 把身份模型持久化到应用私有目录。
/// 保证"本地执行、离线可用、人脸数据不出端"的隐私诉求。
class LocalIdentityStorage {
  static const _fileName = 'face_identity.json';

  Future<Directory> get _dir async => await getApplicationDocumentsDirectory();

  Future<File> get _file async => File('${(await _dir).path}/$_fileName');

  Future<void> save(FaceIdentity identity) async {
    final file = await _file;
    await file.writeAsString(jsonEncode(identity.toJson()));
  }

  Future<FaceIdentity?> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return FaceIdentity.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final file = await _file;
    if (await file.exists()) await file.delete();
  }
}
