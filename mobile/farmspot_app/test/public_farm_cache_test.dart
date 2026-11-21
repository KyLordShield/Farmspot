import 'package:farmspot_app/services/farm_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'public farms retry failures and share successful cached results',
    () async {
      var requestCount = 0;
      await http.runWithClient(
        () async {
          expect(await FarmService.fetchPublicFarms(), isEmpty);
          final results = await Future.wait([
            FarmService.fetchPublicFarms(),
            FarmService.fetchPublicFarms(),
          ]);
          expect(requestCount, 2);
          expect(results.first.single.id, 'FARM01');
          results.first.clear();
          expect(results.last.single.id, 'FARM01');
          expect((await FarmService.fetchPublicFarms()).single.id, 'FARM01');
          expect(requestCount, 2);
          await Future<void>.delayed(const Duration(seconds: 31));
          expect((await FarmService.fetchPublicFarms()).single.id, 'FARM01');
          expect(requestCount, 3);
        },
        () => MockClient((_) async {
          requestCount++;
          return requestCount == 1
              ? http.Response('unavailable', 503)
              : http.Response(
                  '{"farms":[{"id":"FARM01","name":"Test Farm"}]}',
                  200,
                );
        }),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
