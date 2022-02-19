import 'package:flutter/material.dart';

class StoreEditMenu extends StatefulWidget {
  @override
  State<StoreEditMenu> createState() => _StoreEditMenuState();
}

class _StoreEditMenuState extends State<StoreEditMenu> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Menu'),
      ),
      body: SafeArea(
        child: Column(
          children: [],
        ),
      ),
    );
  }
}
