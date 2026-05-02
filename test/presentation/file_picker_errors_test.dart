import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m4b_chapterizer/presentation/util/file_picker_errors.dart';

void main() {
  testWidgets('shows entitlement-fix dialog on ENTITLEMENT_NOT_FOUND',
      (tester) async {
    String? returned = 'sentinel';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              returned = await guardFilePicker<String>(
                context,
                () async => throw PlatformException(
                  code: 'ENTITLEMENT_NOT_FOUND',
                  message: 'Test',
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.textContaining('com.apple.security.files.user-selected.read-write'),
      findsOneWidget,
    );

    // Dismiss and confirm null return.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(returned, isNull);
  });

  testWidgets('shows generic error dialog on a non-entitlement PlatformException',
      (tester) async {
    String? returned = 'sentinel';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              returned = await guardFilePicker<String>(
                context,
                () async => throw PlatformException(
                  code: 'OTHER_ERROR',
                  message: 'something else broke',
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('try again'), findsOneWidget);
    expect(find.textContaining('something else broke'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(returned, isNull);
  });
}
