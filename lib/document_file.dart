import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'native.dart';

/// Thrown when a file cannot be represented as editable text without losing
/// information. Refusing to open is always safer than opening and corrupting.
class UnsupportedDocumentException implements Exception {
  UnsupportedDocumentException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum LineEnding {
  lf('\n'),
  crlf('\r\n');

  const LineEnding(this.sequence);
  final String sequence;
}

/// Everything about the on-disk byte representation that is *not* the text
/// itself. Carried alongside the buffer so a save can reproduce the original
/// encoding exactly instead of imposing the editor's own conventions.
class DocumentEncoding {
  const DocumentEncoding({
    this.hasBom = false,
    this.eol = LineEnding.lf,
    this.mixedEol = false,
    this.isUtf8 = true,
  });

  final bool hasBom;
  final LineEnding eol;

  /// True when the file mixed CRLF and bare LF. Saving normalises to [eol],
  /// which rewrites bytes the user never touched — the one place this codec
  /// is deliberately not byte-faithful. Surfaced so the UI can say so.
  final bool mixedEol;

  /// False when the bytes were not valid UTF-8 and were read as Latin-1.
  final bool isUtf8;

  DocumentEncoding copyWith({bool? isUtf8}) => DocumentEncoding(
        hasBom: hasBom,
        eol: eol,
        mixedEol: mixedEol,
        isUtf8: isUtf8 ?? this.isUtf8,
      );
}

class DecodedDocument {
  const DecodedDocument(this.text, this.encoding);
  final String text;
  final DocumentEncoding encoding;
}

const _utf8Bom = [0xEF, 0xBB, 0xBF];

/// Pure bytes <-> text conversion. No IO, so the fidelity guarantee is
/// exhaustively unit-testable:
///
///     encode(decode(bytes).text, decode(bytes).encoding) == bytes
///
/// holds for every input that does not mix line endings.
class DocumentCodec {
  static DecodedDocument decode(Uint8List bytes) {
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
            (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
      throw UnsupportedDocumentException(
        'UTF-16 编码的文件暂不支持编辑（打开会破坏内容）。请先转换为 UTF-8。',
      );
    }

    var body = bytes;
    var hasBom = false;
    if (bytes.length >= 3 &&
        bytes[0] == _utf8Bom[0] &&
        bytes[1] == _utf8Bom[1] &&
        bytes[2] == _utf8Bom[2]) {
      hasBom = true;
      body = Uint8List.sublistView(bytes, 3);
    }

    String raw;
    var isUtf8 = true;
    try {
      raw = const Utf8Decoder(allowMalformed: false).convert(body);
    } on FormatException {
      // Latin-1 maps every byte to exactly one code point, so the round-trip
      // stays exact as long as the user does not type anything above U+00FF.
      raw = latin1.decode(body);
      isUtf8 = false;
    }

    final crlf = '\r\n'.allMatches(raw).length;
    final totalLf = '\n'.allMatches(raw).length;
    final bareLf = totalLf - crlf;
    final eol = crlf > bareLf ? LineEnding.crlf : LineEnding.lf;

    return DecodedDocument(
      crlf == 0 ? raw : raw.replaceAll('\r\n', '\n'),
      DocumentEncoding(
        hasBom: hasBom,
        eol: eol,
        mixedEol: crlf > 0 && bareLf > 0,
        isUtf8: isUtf8,
      ),
    );
  }

  /// Returns the bytes to write, plus the encoding actually used — which can
  /// differ from [enc] when a Latin-1 document gained characters that Latin-1
  /// cannot represent and had to be promoted to UTF-8.
  static (Uint8List, DocumentEncoding) encode(
    String text,
    DocumentEncoding enc,
  ) {
    final withEol = enc.eol == LineEnding.crlf
        ? text.replaceAll('\n', '\r\n')
        : text;

    List<int> body;
    var used = enc;
    if (enc.isUtf8) {
      body = utf8.encode(withEol);
    } else if (withEol.codeUnits.every((c) => c <= 0xFF)) {
      body = latin1.encode(withEol);
    } else {
      body = utf8.encode(withEol);
      used = enc.copyWith(isUtf8: true);
    }

    return (
      Uint8List.fromList(enc.hasBom ? [..._utf8Bom, ...body] : body),
      used,
    );
  }
}

/// Identity of a file's on-disk state, used to notice edits made by other
/// programs between our read and our write.
class FileStamp {
  const FileStamp(this.modified, this.size);
  final DateTime modified;
  final int size;

  static Future<FileStamp?> of(String path) async {
    try {
      final s = await File(path).stat();
      if (s.type == FileSystemEntityType.notFound) return null;
      return FileStamp(s.modified, s.size);
    } catch (_) {
      return null;
    }
  }

  bool matches(FileStamp? other) =>
      other != null &&
      other.size == size &&
      other.modified.millisecondsSinceEpoch == modified.millisecondsSinceEpoch;
}

class LoadedDocument {
  const LoadedDocument(this.text, this.encoding, this.stamp);
  final String text;
  final DocumentEncoding encoding;
  final FileStamp? stamp;
}

class DocumentFile {
  /// Reads [path] preserving everything needed to write it back byte-for-byte.
  static Future<LoadedDocument> read(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = DocumentCodec.decode(bytes);
    return LoadedDocument(
      decoded.text,
      decoded.encoding,
      await FileStamp.of(path),
    );
  }

  /// Writes atomically: the file on disk is either the old content or the new
  /// content, never a truncated mix. Returns the post-write stamp and the
  /// encoding actually used.
  static Future<(FileStamp?, DocumentEncoding)> write(
    String path,
    String text,
    DocumentEncoding encoding,
  ) async {
    final (bytes, used) = DocumentCodec.encode(text, encoding);

    // Follow symlinks so we replace the target, not the link itself.
    var target = path;
    try {
      if (await FileSystemEntity.isLink(path)) {
        target = await File(path).resolveSymbolicLinks();
      }
    } catch (_) {
      // Broken link — fall through and create a regular file at `path`.
    }

    if (!await Native.writeAtomically(target, bytes)) {
      await _writeAtomicallyDart(target, bytes);
    }
    return (await FileStamp.of(target), used);
  }

  /// Fallback for tests and any host without the native channel. Same
  /// guarantee via temp-file + rename, which is atomic within a filesystem.
  static Future<void> _writeAtomicallyDart(String path, Uint8List bytes) async {
    final file = File(path);
    final dir = file.parent;
    final tmp = File(
      '${dir.path}${Platform.pathSeparator}.${file.uri.pathSegments.last}.typen~',
    );
    int? mode;
    try {
      mode = (await file.stat()).mode & 0xFFF;
    } catch (_) {
      mode = null;
    }
    await tmp.writeAsBytes(bytes, flush: true);
    if (mode != null && mode != 0) {
      try {
        await Process.run('chmod', [mode.toRadixString(8), tmp.path]);
      } catch (_) {
        // Non-fatal: content integrity matters more than the mode bits.
      }
    }
    await tmp.rename(path);
  }
}
