import 'package:flutter/material.dart';

import 'join_store.dart';
import 'open_store.dart';
import 'entry_ui.dart';
import '../widgets/page_body.dart';


/// The first thing registration asks: are you opening a store, or joining one?
///
/// It used to be inferred — six fields on one page, and whether you joined or
/// created depended on whether the store ID you pasted happened to exist
/// already. The only thing telling anyone which one they were doing was a line
/// of helper text under the last field.
class ChoosePathScreen extends StatelessWidget {
  const ChoosePathScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildEntryAppBar(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
          child: PageBody(
            maxWidth: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const StepTitle('Get started'),
                const SizedBox(height: 8),
                const StepSubtitle('Which of these are you doing?'),
                const SizedBox(height: 32),
                PathCard(
                  icon: Icons.storefront_outlined,
                  title: 'Open a new store',
                  description:
                      'You run the place. This creates the store and makes you '
                      'its owner.',
                  onTap: () => _push(context, const OpenStoreRegistration()),
                ),
                const SizedBox(height: 16),
                PathCard(
                  icon: Icons.group_add_outlined,
                  title: 'Join an existing store',
                  description:
                      'Somebody at the store gave you a 6-character invite '
                      'code.',
                  onTap: () => _push(context, const JoinStoreRegistration()),
                ),
                const SizedBox(height: 32),
                // Wrap rather than Row: on a 400pt phone the sentence and the
                // button together overflowed by more than a hundred points,
                // and a Row has nowhere to put the excess.
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Already have an account? '),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Sign in',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}
