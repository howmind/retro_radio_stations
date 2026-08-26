import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:radio_browser_api/radio_browser_api.dart';

Future<void> dumpStations() async {
  print('[${DateTime.now()}] dump start .....');
  try {
    const host = 'all.api.radio-browser.info';
    print('host: $host');
    final rb = RadioBrowserApi.fromHost(host);
    print('[${DateTime.now()}] --------- download start ---------');

    const pageSize = 1000;
    const maxRetriesPerPage = 5;

    // Keep only ok + valid-url stations as we go, to save memory.
    final List<Map<String, dynamic>> checked = [];
    int offset = 0;
    int total = 0;
    int skippedUrls = 0;

    while (true) {
      RadioBrowserListResponse<Station>? rets;

      // Bounded retry for this page.
      for (int attempt = 1; attempt <= maxRetriesPerPage; attempt++) {
        try {
          rets = await rb.advancedStationSearch(
            parameters: InputParameters(offset: offset, limit: pageSize),
          );
          break; // success
        } on FormatException catch (err) {
          print(
            'decode failed at offset $offset '
            '(attempt $attempt/$maxRetriesPerPage): $err',
          );
          await Future.delayed(
            Duration(seconds: 5 * attempt),
          ); // linear backoff
        } catch (err) {
          // Network / socket / timeout etc. — treat the same way.
          print(
            'request failed at offset $offset '
            '(attempt $attempt/$maxRetriesPerPage): $err',
          );
          await Future.delayed(Duration(seconds: 5 * attempt));
        }
      }

      // All retries exhausted for this page — stop the whole download.
      if (rets == null) {
        print('aborting download: could not fetch offset $offset');
        break;
      }

      total += rets.items.length;
      final okThisBatch = rets.items.where((e) => e.lastCheckOk == true).length;
      print(
        'batch@$offset: ${rets.items.length} items, '
        '$okThisBatch ok (running total: $total)',
      );

      for (final e in rets.items) {
        if (e.lastCheckOk != true) continue; // skip dead stations
        if (!_hasUsableUrl(e)) {
          skippedUrls++; // skip unavailable / malformed URLs
          continue;
        }
        checked.add(_stationToMap(e)); // never null now
      }

      if (rets.items.length < pageSize) break; // last page
      offset += pageSize;
      await Future.delayed(const Duration(seconds: 3));
    }

    print('[${DateTime.now()}] --------- download end ---------');
    print(
      '[${DateTime.now()}] downloaded total: $total, '
      'kept: ${checked.length}, skipped unusable urls: $skippedUrls',
    );

    print('[${DateTime.now()}] ------------- create json file ------------');
    final jsonFile = File('radiostations.json');
    await jsonFile.writeAsString(jsonEncode(checked));

    print('------------- zip file -------------');
    const zipPath = 'radiostations.json.zip';
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await encoder.addFile(jsonFile);
    encoder.closeSync();

    print('------------- move file -------------');
    Directory('assets/radio').createSync(recursive: true);
    final source = File(zipPath);
    if (await source.exists()) {
      await source.rename('assets/radio/radiostations.json.zip');
      print('File moved to assets/radio/radiostations.json.zip');
    } else {
      print('Source zip does not exist.');
    }
  } catch (e, st) {
    print('@@@ dumpStations failed: $e');
    print(st);
  }
  print('------------- Dump done! -------------');
}

/// Returns true only if the station has a usable http(s) stream URL.
bool _hasUsableUrl(Station e) {
  final raw = (e.urlResolved ?? e.url)?.trim();
  if (raw == null || raw.isEmpty) return false;
  final uri = Uri.tryParse(raw);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// Maps a Station to the output map. Always returns a valid map with an
/// available URI — call only after _hasUsableUrl(e) returned true.
Map<String, dynamic> _stationToMap(Station e) {
  final uri = Uri.parse((e.urlResolved ?? e.url)!); // safe: guarded above
  return {
    "title": e.name,
    "uri": uri.toString(),
    "description": '',
    "uuid": e.stationUUID,
    "country": e.country,
    "countryCode": e.countryCode,
    "state": e.state,
    "favicon": e.favicon,
    "tags": e.tags,
    "language": e.language,
    "languageCodes": e.languageCodes,
    "votes": e.votes,
    "clickCount": e.clickCount,
    "clickTrend": e.clickTrend,
    "homepage": e.homepage,
    "lastCheckOk": e.lastCheckOk,
  };
}

void main() async {
  Stopwatch stopwatch = Stopwatch()..start();
  await dumpStations();
  stopwatch.stop();
  print('total use time(ms): ${stopwatch.elapsedMilliseconds}');
}
