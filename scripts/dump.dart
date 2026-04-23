import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:radio_browser_api/radio_browser_api.dart';

Future<void> dumpStations() async {
  print('[${DateTime.now()}] dump start .....');
  try {
    String? host = 'all.api.radio-browser.info';
    print('host: $host');
    var rb = RadioBrowserApi.fromHost(host);
    print('[${DateTime.now()}] --------- download start ---------');

    List<Map<String, dynamic>> radios = [];
    int offset = 0;
    int k = 0;
    while (true) {
      final rets = await rb.advancedStationSearch(
        parameters: InputParameters(offset: offset, limit: 1000),
      );
      print(
        'The available stations total in downloaded items: ${rets.items.where((e) => e.lastCheckOk).length}',
      );
      var batchRadios = rets.items.map((Station e) {
        if (!e.lastCheckOk) {
          print(
            'notok station: ${e.name},${e.lastCheckOk},${e.lastCheckTime},${e.lastCheckOkTime}, ${e.urlResolved}',
          );
        }
        return {
          "title": e.name,
          "uri": Uri.parse(e.urlResolved ?? e.url).toString(),
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
      }).toList();
      radios.addAll(batchRadios);

      if (rets.items.length < 1000) {
        break;
      }
      k = k + 1;
      offset = 1000 * k;
      Future.delayed(Duration(seconds: 3));
    }

    print('[${DateTime.now()}] --------- download end ---------');
    print(
      '${DateTime.now()} --------- downloaded total : ${radios.length}, available stations: ${radios.where((e) => e["lastCheckOk"]).length}',
    );
    var checked = radios.where((el) => el["lastCheckOk"]).toList();
    print('[${DateTime.now()}] ------------- create json file ------------');
    final f = File("./radiostations.json");
    f.writeAsStringSync(jsonEncode(checked));

    print('------------- zip file -------------');
    var encoder = ZipFileEncoder();
    encoder.create('radiostations.json.zip');
    await encoder.addFile(File('./radiostations.json'));
    encoder.closeSync();

    print('------------- move file -------------');
    try {
      //ensure folder exists
      Directory('assets/radio').createSync(recursive: true);

      File sourceFile = File('radiostations.json.zip');
      if (await sourceFile.exists()) {
        await sourceFile.rename('assets/radio/radiostations.json.zip');
        print('File moved successfully to assets/radio/radiostations.json.zip');
      } else {
        print('Source file does not exist.');
      }
    } catch (e) {
      print('@@@Error@@@ moving file: $e');
    }
  } catch (e) {
    print(e);
  }
  print('------------- Dumpe done! -------------');
}

void main() async {
  Stopwatch stopwatch = Stopwatch()..start();
  await dumpStations();
  stopwatch.stop();
  print('total use time(ms): ${stopwatch.elapsedMilliseconds}');
}
