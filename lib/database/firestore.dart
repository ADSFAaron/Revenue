import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FireStoreDB {
  FireStoreDB({required this.userID});

  late String userID;

  // Stream userStream =
  //     FirebaseFirestore.instance.collection('users').doc(userID).snapshots();

  // void addUser(User user) {
  //   userReference.add(user);
  // }

  // void updateUser(User user) {
  //   userReference.document(user.getId()).set(user);
  // }

  // void deleteUser(String id) {
  //   userReference.document(id).delete();
  // }

  // void getUser(String id) {
  //   userReference.document(id).get();
  // }
}
