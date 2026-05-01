List<String> probeArguments(String inputPath) => [
      '-show_format',
      '-show_chapters',
      '-show_streams',
      '-of',
      'json',
      '-i',
      inputPath,
    ];

List<String> extractCoverArguments(String inputPath) => [
      '-loglevel',
      'error',
      '-i',
      inputPath,
      '-map',
      '0:v',
      '-frames:v',
      '1',
      '-c',
      'copy',
      '-f',
      'image2',
      '-',
    ];

List<String> writeArguments({
  required String sourcePath,
  required String metadataPath,
  required String? coverPath,
  required String outputPath,
}) {
  final args = <String>[
    '-y',
    '-loglevel',
    'error',
    '-i',
    sourcePath,
    '-i',
    metadataPath,
    if (coverPath != null) ...['-i', coverPath],
    '-map',
    '0:a',
    if (coverPath != null) ...['-map', '2:v'],
    '-map_metadata',
    '1',
    '-map_chapters',
    '1',
    if (coverPath != null) ...['-disposition:v:0', 'attached_pic'],
    '-c',
    'copy',
    '-f',
    'mp4',
    outputPath,
  ];
  return args;
}
