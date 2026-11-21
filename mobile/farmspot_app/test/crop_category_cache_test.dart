import 'package:farmspot_app/services/listing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'category failures retry and concurrent callers share a cached response',
    () async {
      var requests = 0;
      await http.runWithClient(
        () async {
          await expectLater(
            ListingService.fetchCropCategories(),
            throwsException,
          );
          final results = await Future.wait([
            ListingService.fetchCropCategories(),
            ListingService.fetchCropCategories(),
          ]);
          expect(requests, 2);
          expect(results.first.single.id, 'LEAFVG');
          results.first.clear();
          expect(results.last.single.id, 'LEAFVG');
          expect(
            (await ListingService.fetchCropCategories()).single.id,
            'LEAFVG',
          );
          expect(requests, 2);
        },
        () => MockClient((_) async {
          requests++;
          return requests == 1
              ? http.Response('unavailable', 503)
              : http.Response(
                  '{"categories":[{"id":"LEAFVG","name":"Leafy Vegetables"}]}',
                  200,
                );
        }),
      );
    },
  );
}
