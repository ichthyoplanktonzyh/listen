import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/services/capability_file_resolver.dart';
import 'package:llplayer_next/services/capability_request_encoder.dart';
import 'package:llplayer_next/services/document_reference_store.dart';

import 'support/learning_material_fixtures.dart';

/// The Gen input boundary (Slice 4): document renditions resolve to their
/// exact Source Asset bytes — never to a fabricated extracted-text file — and
/// the capability request declares the rendition's digest/size facts in the
/// `sha256:` reference form. Managed copies were verified when copied;
/// referenced locations are re-verified at use.
void main() {
  group('CapabilityRequestEncoder document entries', () {
    test('declare the rendition digest and size in sha256 reference form', () {
      final digest = 'b' * 64;
      final rendition = documentRendition(
        id: 'document-1',
        digest: digest,
        byteSize: 11,
        sourceAssetId: 'source-1',
      );

      final request = CapabilityRequestEncoder.encode(
        materialId: 'material-1',
        materialRevisionId: 'revision-1',
        materialTitle: 'Lesson',
        editionId: 'edition:material-1',
        editionTitle: 'Lesson',
        targetLanguage: 'en',
        supportLanguages: const [],
        requestedCapability: 'listen',
        createdAtMs: 1,
        attemptId: 'attempt-1',
        documentRenditions: [rendition],
        documentSourcePaths: {'document-1': '/library/lesson.txt'},
        documentSourceAssetIds: {'document-1': 'source-1'},
      );

      final entry = (request['available_renditions'] as List<dynamic>).single
          as Map<String, dynamic>;
      expect(entry['kind'], 'document');
      expect(entry['source_asset_id'], 'sha256:source-1');
      final blob = entry['blob'] as Map<String, dynamic>;
      expect(blob['digest'], 'sha256:$digest');
      expect(blob['size_bytes'], 11);
      expect(blob['path'], '/library/lesson.txt');
    });

    test('fall back to the rendition id for a rendition without a binding',
        () {
      final rendition = documentRendition(
        id: 'document-9',
        digest: 'c' * 64,
        byteSize: 5,
        sourceAssetId: null,
      );

      final request = CapabilityRequestEncoder.encode(
        materialId: 'material-1',
        materialRevisionId: 'revision-1',
        materialTitle: 'Lesson',
        editionId: 'edition:material-1',
        editionTitle: 'Lesson',
        targetLanguage: 'en',
        supportLanguages: const [],
        requestedCapability: 'listen',
        createdAtMs: 1,
        documentRenditions: [rendition],
      );

      final entry = (request['available_renditions'] as List<dynamic>).single
          as Map<String, dynamic>;
      expect(entry['source_asset_id'], 'sha256:document-9');
      final blob = entry['blob'] as Map<String, dynamic>;
      expect(blob['digest'], 'sha256:${'c' * 64}');
      expect(blob['path'], isNull);
    });
  });

  group('LocalCapabilityFileResolver document source resolution', () {
    late Directory root;
    late File referenceFile;
    late DocumentReferenceStore referenceStore;

    setUp(() {
      root = Directory.systemTemp.createTempSync('capability-resolver-');
      referenceFile = File('${root.path}/references.json');
      referenceStore = DocumentReferenceStore(file: referenceFile);
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('managed bindings resolve the verified store copy path', () async {
      final resolver = LocalCapabilityFileResolver(
        managedStorePath: (asset) => '/store/${asset.sha256Digest}',
        referenceStore: referenceStore,
      );
      final rendition = documentRendition(digest: 'a' * 64, byteSize: 11);
      final asset = sourceAsset(sha256Digest: 'a' * 64);

      final path = await resolver.documentSourcePath(rendition, asset);

      expect(path, '/store/${'a' * 64}');
    });

    test('a rendition without a Source Asset resolves to nothing', () async {
      final resolver = LocalCapabilityFileResolver(
        managedStorePath: (asset) => '/store/x',
        referenceStore: referenceStore,
      );

      expect(
        await resolver.documentSourcePath(
          documentRendition(),
          null,
        ),
        isNull,
      );
    });

    test('referenced bindings re-verify digest and size at use', () async {
      final bytes = utf8.encode('Original lesson bytes.');
      final digest = sha256.convert(bytes).toString();
      final original = File('${root.path}/original.txt')
        ..writeAsBytesSync(bytes);
      await referenceStore.save(digest, original.path);

      final resolver = LocalCapabilityFileResolver(
        managedStorePath: (asset) => null,
        referenceStore: referenceStore,
      );
      final asset = sourceAsset(
        sha256Digest: digest,
        byteLength: bytes.length,
        binding: SourceAssetBinding(
          type: SourceAssetBindingType.referenced,
          reference: digest,
        ),
      );

      expect(
        await resolver.documentSourcePath(documentRendition(), asset),
        original.path,
      );

      // The original changed: the resolved path disappears, never a stale file.
      original.writeAsStringSync('tampered');
      expect(
        await resolver.documentSourcePath(documentRendition(), asset),
        isNull,
      );
    });

    test('a missing referenced location resolves to nothing', () async {
      final resolver = LocalCapabilityFileResolver(
        managedStorePath: (asset) => null,
        referenceStore: referenceStore,
      );
      final asset = sourceAsset(
        sha256Digest: 'e' * 64,
        byteLength: 4,
        binding: SourceAssetBinding(
          type: SourceAssetBindingType.referenced,
          reference: 'missing-key',
        ),
      );

      expect(
        await resolver.documentSourcePath(documentRendition(), asset),
        isNull,
      );
    });
  });
}
