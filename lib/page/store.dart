import 'package:flutter/material.dart';

class StorePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8.0, vertical: 16.0),
                    child: Text(
                      "Store name",
                      style: TextStyle(
                        fontSize: 28.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_outlined),
                    onPressed: () {
                      // Firebase User Logout
                    },
                  ),
                ],
              ),
            ),
            Wrap(
              children: <Widget>[
                Card(
                  color: Color(0xff95eeb3),
                  child: InkWell(
                    splashColor: Colors.blue.withAlpha(30),
                    onTap: () {
                      debugPrint('Card tapped.');
                    },
                    child: SizedBox(
                      width: 150,
                      height: 100,
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          children: [
                            Text(
                              'NTD 0',
                              style: TextStyle(fontSize: 20),
                              textAlign: TextAlign.start,
                            ),
                            Text('Total Income'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Card(
                  color: Color(0xffFDBE90),
                  child: InkWell(
                    splashColor: Colors.blue.withAlpha(30),
                    onTap: () {
                      debugPrint('Card tapped.');
                    },
                    child: const SizedBox(
                      width: 150,
                      height: 100,
                      child: Text('A card that can be tapped'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
