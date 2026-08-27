enum ArchiveColumn {
  name,
  type,
  path,
  size,
  totalSize,
  itemCount,
  packedSize,
  compressionRatio,
  modified,
  method,
  encrypted,
  crc,
  sourcePath,
  attributes,
}

extension ArchiveColumnLabel on ArchiveColumn {
  String get label => switch (this) {
    ArchiveColumn.name => '名称',
    ArchiveColumn.type => '类型',
    ArchiveColumn.path => '相对路径',
    ArchiveColumn.size => '大小',
    ArchiveColumn.totalSize => '文件夹总大小',
    ArchiveColumn.itemCount => '文件夹项目数',
    ArchiveColumn.packedSize => '压缩后',
    ArchiveColumn.compressionRatio => '压缩率',
    ArchiveColumn.modified => '修改时间',
    ArchiveColumn.method => '压缩算法',
    ArchiveColumn.encrypted => '加密状态',
    ArchiveColumn.crc => 'CRC 校验值',
    ArchiveColumn.sourcePath => '来源位置',
    ArchiveColumn.attributes => '文件属性',
  };
}

const defaultCompressionArchiveColumns = [
  ArchiveColumn.name,
  ArchiveColumn.size,
  ArchiveColumn.modified,
];

const defaultExtractionArchiveColumns = [
  ArchiveColumn.name,
  ArchiveColumn.size,
  ArchiveColumn.packedSize,
  ArchiveColumn.modified,
];

const compressionAvailableArchiveColumns = [
  ArchiveColumn.name,
  ArchiveColumn.type,
  ArchiveColumn.path,
  ArchiveColumn.size,
  ArchiveColumn.totalSize,
  ArchiveColumn.itemCount,
  ArchiveColumn.modified,
  ArchiveColumn.sourcePath,
  ArchiveColumn.attributes,
];

const extractionAvailableArchiveColumns = [
  ArchiveColumn.name,
  ArchiveColumn.type,
  ArchiveColumn.path,
  ArchiveColumn.size,
  ArchiveColumn.totalSize,
  ArchiveColumn.itemCount,
  ArchiveColumn.packedSize,
  ArchiveColumn.compressionRatio,
  ArchiveColumn.modified,
  ArchiveColumn.method,
  ArchiveColumn.encrypted,
  ArchiveColumn.crc,
  ArchiveColumn.attributes,
];

class ArchiveColumnPreferences {
  const ArchiveColumnPreferences({
    this.compressionColumns = defaultCompressionArchiveColumns,
    this.extractionColumns = defaultExtractionArchiveColumns,
  });

  final List<ArchiveColumn> compressionColumns;
  final List<ArchiveColumn> extractionColumns;

  ArchiveColumnPreferences copyWith({
    List<ArchiveColumn>? compressionColumns,
    List<ArchiveColumn>? extractionColumns,
  }) => ArchiveColumnPreferences(
    compressionColumns: compressionColumns ?? this.compressionColumns,
    extractionColumns: extractionColumns ?? this.extractionColumns,
  );

  /// Removes invalid duplicates and keeps the identifying name column visible.
  static List<ArchiveColumn> normalize(Iterable<ArchiveColumn> columns) {
    final normalized = <ArchiveColumn>[];
    for (final column in columns) {
      if (!normalized.contains(column)) normalized.add(column);
    }
    if (!normalized.contains(ArchiveColumn.name)) {
      normalized.insert(0, ArchiveColumn.name);
    }
    return List.unmodifiable(normalized);
  }
}
