import "package:bobomusic/core/theme/app_palette.dart";
import "package:bobomusic/core/theme/app_theme.dart";
import "package:bobomusic/core/widgets/app_checkbox_row.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("方框与文字均只切换一次，尾部编辑按钮独立，文字紧邻复选框", (tester) async {
    var selected = false;
    var changes = 0;
    var edits = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(AppThemeColor.natureGreen, Brightness.light),
      home: Scaffold(
          body: StatefulBuilder(
        builder: (context, setState) => AppCheckboxRow(
          value: selected,
          label: const Text("选择歌曲"),
          onChanged: (value) => setState(() {
            selected = value;
            changes++;
          }),
          trailing: IconButton(
              onPressed: () => edits++, icon: const Icon(Icons.edit_outlined)),
        ),
      )),
    ));
    expect(
        tester.getTopLeft(find.text("选择歌曲")).dx -
            tester.getTopRight(find.byType(Checkbox)).dx,
        lessThanOrEqualTo(8));
    expect(tester.getSize(find.byType(AppCheckboxRow)).height,
        greaterThanOrEqualTo(48));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(selected, isTrue);
    expect(changes, 1);
    await tester.tap(find.text("选择歌曲"));
    await tester.pump();
    expect(selected, isFalse);
    expect(changes, 2);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    expect(edits, 1);
    expect(changes, 2);
    expect(tester.takeException(), isNull);
  });
}
