import 'package:cloud_firestore/cloud_firestore.dart';

/// Who a user is inside their store. Managers and owners may edit the menu,
/// store settings and prices; staff may only take orders.
enum UserRole {
  owner('owner'),
  manager('manager'),
  staff('staff');

  const UserRole(this.id);

  final String id;

  static UserRole fromId(String? id) =>
      UserRole.values.firstWhere((r) => r.id == id, orElse: () => UserRole.staff);

  bool get canManage => this == UserRole.owner || this == UserRole.manager;

  String get label => switch (this) {
        UserRole.owner => 'Owner',
        UserRole.manager => 'Manager',
        UserRole.staff => 'Staff',
      };
}

/// `users/{uid}` — keyed by the Firebase Auth uid, never by email. An email can
/// be changed; the uid cannot, and keying on it is what keeps a user's data
/// reachable after a change.
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.storeId,
    this.role = UserRole.staff,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final String storeId;
  final UserRole role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AppUser(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      storeId: data['storeId'] as String? ?? '',
      role: UserRole.fromId(data['role'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// `createdAt` / `updatedAt` are left to the repository so it can stamp them
  /// with the server clock.
  Map<String, dynamic> toMap() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'storeId': storeId,
        'role': role.id,
      };

  /// Initials for the avatar circles. Falls back to the email so a user who
  /// never set a name still gets something readable.
  String get initials {
    final source = displayName.trim().isNotEmpty ? displayName.trim() : email.trim();
    if (source.isEmpty) return '??';
    final parts = source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return source.length >= 2
        ? source.substring(0, 2).toUpperCase()
        : source.toUpperCase();
  }

  AppUser copyWith({String? displayName, UserRole? role}) => AppUser(
        uid: uid,
        email: email,
        displayName: displayName ?? this.displayName,
        storeId: storeId,
        role: role ?? this.role,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
