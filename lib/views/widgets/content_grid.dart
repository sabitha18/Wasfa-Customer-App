import 'package:flutter/material.dart';

/// Grids whose rows are exactly as tall as their tallest item.
///
/// Replaces `GridView` + `childAspectRatio` / fixed `mainAxisExtent` in the
/// app. A ratio ties the cell HEIGHT to the screen WIDTH, so wide phones
/// (e.g. iPhone 15 Pro Max, 430pt) got big empty space inside cells and
/// narrow phones / large text / Arabic risked overflow. Here each row sizes
/// to its content (IntrinsicHeight + stretch), so every cell in a row has
/// the same height, nothing is cut off, and nothing is left empty — on any
/// screen width or text size.
///
/// Items must not contain a LayoutBuilder (not intrinsic-measurable).

/// Builds one row of [columns] cells for row index [row]. Shared by
/// [ContentGrid] (non-scrolling, inside a Column/sliver adapter) and by
/// scrolling lists that build rows lazily (`itemCount: contentGridRowCount`).
Widget contentGridRow({
  required BuildContext context,
  required int row,
  required int itemCount,
  required int columns,
  required IndexedWidgetBuilder itemBuilder,
  double spacing = 12,
  double runSpacing = 12,
}) {
  final start = row * columns;
  final isLastRow = start + columns >= itemCount;
  return Padding(
    padding: EdgeInsets.only(bottom: isLastRow ? 0 : runSpacing),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var c = 0; c < columns; c++) ...[
            if (c > 0) SizedBox(width: spacing),
            Expanded(
              child: start + c < itemCount ? itemBuilder(context, start + c) : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    ),
  );
}

int contentGridRowCount(int itemCount, int columns) => (itemCount + columns - 1) ~/ columns;

/// Non-scrolling content-sized grid (for use inside another scroll view).
class ContentGrid extends StatelessWidget {
  final int itemCount;
  final int columns;
  final double spacing;
  final double runSpacing;
  final EdgeInsetsGeometry padding;
  final IndexedWidgetBuilder itemBuilder;

  const ContentGrid({
    super.key,
    required this.itemCount,
    required this.columns,
    required this.itemBuilder,
    this.spacing = 12,
    this.runSpacing = 12,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var r = 0; r < contentGridRowCount(itemCount, columns); r++)
            contentGridRow(
              context: context,
              row: r,
              itemCount: itemCount,
              columns: columns,
              itemBuilder: itemBuilder,
              spacing: spacing,
              runSpacing: runSpacing,
            ),
        ],
      ),
    );
  }
}

/// Horizontal rail whose height is the tallest item's height (instead of a
/// fixed `SizedBox(height: …)` around a horizontal ListView, which left
/// empty space under short content and clipped long names / large text).
/// Builds all items up front — use for short rails (nearest stores,
/// a store's product rails), not endless lists.
class ContentRail extends StatelessWidget {
  final int itemCount;
  final double itemWidth;
  final double spacing;
  final EdgeInsetsGeometry padding;
  final IndexedWidgetBuilder itemBuilder;

  const ContentRail({
    super.key,
    required this.itemCount,
    required this.itemWidth,
    required this.itemBuilder,
    this.spacing = 12,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < itemCount; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              SizedBox(width: itemWidth, child: itemBuilder(context, i)),
            ],
          ],
        ),
      ),
    );
  }
}
