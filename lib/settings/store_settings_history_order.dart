import 'package:flutter/material.dart';

class StoreHistoryOrder extends StatelessWidget {
  String storeID;
  StoreHistoryOrder(this.storeID, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History Orders'),
      ),
      body: SafeArea(
          child: Column(
        children: [],
      )),
    );
  }
}
