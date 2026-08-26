import 'dart:typed_data';
import 'dart:convert';

/// 由多张人脸照建立的"数字身份"。
///
/// - 真实引擎下 [embedding] 为 ArcFace 的 512 维特征向量，由 20 张照检测/对齐后取平均得到；
/// - 演示引擎下 [embedding] 为占位向量，[representativeFacePath] 取一张代表脸用于合成。
class FaceIdentity {
  final String id;
  final DateTime createdAt;
  final List<String> sourcePhotoPaths; // 用户上传的 20 张照路径
  final String representativeFacePath; // 用于演示合成的代表脸
  final Float32List embedding; // 身份特征向量（真实引擎核心）
  final bool isDemo;

  const FaceIdentity({
    required this.id,
    required this.createdAt,
    required this.sourcePhotoPaths,
    required this.representativeFacePath,
    required this.embedding,
    this.isDemo = false,
  });

  FaceIdentity copyWith({String? representativeFacePath, Float32List? embedding}) {
    return FaceIdentity(
      id: id,
      createdAt: createdAt,
      sourcePhotoPaths: sourcePhotoPaths,
      representativeFacePath: representativeFacePath ?? this.representativeFacePath,
      embedding: embedding ?? this.embedding,
      isDemo: isDemo,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'sourcePhotoPaths': sourcePhotoPaths,
        'representativeFacePath': representativeFacePath,
        'embedding': embedding.toList(),
        'isDemo': isDemo,
      };

  factory FaceIdentity.fromJson(Map<String, dynamic> json) => FaceIdentity(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        sourcePhotoPaths: List<String>.from(json['sourcePhotoPaths'] as List),
        representativeFacePath: json['representativeFacePath'] as String,
        embedding: Float32List.fromList(
          List<double>.from(json['embedding'] as List),
        ),
        isDemo: json['isDemo'] as bool? ?? false,
      );
}

/// 把身份序列化为可经 MethodChannel 传递给原生引擎的 Map（JSON 字符串）。
String faceIdentityToJson(FaceIdentity identity) => jsonEncode(identity.toJson());
