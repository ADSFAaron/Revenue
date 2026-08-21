import 'package:flutter/material.dart';

import '../database/repositories.dart';
import '../models/app_user.dart';

/// The store's staff, read by reverse lookup on `users.storeId`.
class StoreStaff extends StatelessWidget {
  const StoreStaff(this.storeId, {super.key});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Store Staff')),
      body: StreamBuilder<List<AppUser>>(
        stream: userRepository.watchStaff(storeId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final staff = snapshot.data!;
          if (staff.isEmpty) {
            return const Center(child: Text('No staff found for this store.'));
          }

          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ListView.builder(
              itemCount: staff.length,
              itemBuilder: (context, index) {
                final user = staff[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: ListTile(
                    title: Text(user.displayName.isEmpty
                        ? user.email
                        : user.displayName),
                    subtitle: Text('${user.email}\n${user.role.label}'),
                    isThreeLine: true,
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).splashColor,
                      child: Text(user.initials),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
