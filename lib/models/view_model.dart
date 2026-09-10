enum GridSize {
  one(1, 1),
  four(4, 2),
  nine(9, 3),
  sixteen(16, 4);

  const GridSize(this.count, this.columns);
  final int count;
  final int columns;

  static GridSize fromCount(int count) => switch (count) {
        1 => GridSize.one,
        9 => GridSize.nine,
        16 => GridSize.sixteen,
        _ => GridSize.four,
      };
}

extension GridSizeX on GridSize {
  bool get useMainStream => this == GridSize.one;
}

class SurveillanceView {
  final String id;
  String name;
  GridSize gridSize;
  final List<String?> cells;
  final DateTime updatedAt;

  SurveillanceView({
    required this.id,
    required this.name,
    required this.gridSize,
    required this.cells,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'gridSize': gridSize.count,
        'cells': cells,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SurveillanceView.fromJson(Map<String, dynamic> json) {
    final gridSize = GridSize.fromCount((json['gridSize'] as num?)?.toInt() ?? 4);
    final rawCells = (json['cells'] as List?) ?? const [];
    final cells = List<String?>.generate(
      gridSize.count,
      (i) => i < rawCells.length ? rawCells[i] as String? : null,
    );
    return SurveillanceView(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      gridSize: gridSize,
      cells: cells,
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
              DateTime.now(),
    );
  }
}