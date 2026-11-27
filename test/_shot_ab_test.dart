// 临时脚本：用真实 Flutter 渲染管线导出应用商店素材用的整屏截图。
// 不参与常规测试，跑完即可删除。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fqapp/models/home_cell.dart';
import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/pages/home_page.dart';
import 'package:fqapp/pages/home_provider.dart';
import 'package:fqapp/pages/library_page.dart';
import 'package:fqapp/pages/mine_page.dart';
import 'package:fqapp/pages/reader_page.dart';
import 'package:fqapp/services/api_client.dart';
import 'package:fqapp/services/app_theme.dart';
import 'package:fqapp/services/library_store.dart';
import 'package:fqapp/services/shelf_group_store.dart';
import 'package:fqapp/services/shelf_store.dart';
import 'package:fqapp/widgets/shell_dock.dart';

import 'support/fakes.dart';

Future<void> _load(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  await _load('Roboto', [
    '/tmp/shotfonts/NotoSansSC-Regular.otf',
    '/tmp/shotfonts/NotoSansSC-Bold.otf',
  ]);
  await _load('Home Serif', [
    '/tmp/fqapp-175/assets/fonts/NotoSerifSC-Regular.otf',
    '/tmp/fqapp-175/assets/fonts/NotoSerifSC-Bold.otf',
  ]);
  await _load('Home Mono', ['/tmp/fqapp-175/assets/fonts/RobotoMono-Medium.ttf']);
  // 通用族名（monospace / serif）在无系统字体的测试环境里没有字形，会画成方块。
  await _load('monospace', ['/tmp/shotfonts/NotoSansSC-Regular.otf']);
  await _load('serif', ['/tmp/fqapp-175/assets/fonts/NotoSerifSC-Regular.otf']);
  await _load('sans-serif', ['/tmp/shotfonts/NotoSansSC-Regular.otf']);
  await _load('MaterialIcons', [
    '/opt/flutter-3.47.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  const lucide = '/root/.pub-cache/hosted/pub.dev/flutter_lucide-1.59.0/lib/fonts/lucide.ttf';
  await _load('lucide', [lucide]);
  await _load('packages/flutter_lucide/lucide', [lucide]);
  const cupertino =
      '/root/.pub-cache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf';
  await _load('CupertinoIcons', [cupertino]);
  await _load('packages/cupertino_icons/CupertinoIcons', [cupertino]);
}

MediaItem _book(String id, String title, String author) => MediaItem(
  id: id,
  title: title,
  cover: '',
  author: author,
  badge: '',
  ep: '全 12 章',
  kind: 'book',
);

// topInset / bottomInset 模拟真机状态栏与 Home Indicator 的避让区，
// 否则贴进设备帧后灵动岛会盖住标题。
Widget _shell({
  required int index,
  required Widget body,
  double topInset = 59,
  double bottomInset = 12,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.createTheme(Brightness.light),
  home: Scaffold(
    body: Padding(
      padding: EdgeInsets.only(top: topInset),
      child: body,
    ),
    bottomNavigationBar: Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ShellDock(
      selectedIndex: index,
      onSelected: (_) {},
      overVideo: false,
        staticMaterial: shellDockStaticMaterial(overVideo: false),
      ),
    ),
  ),
);

const String _taoHuaYuan =
    '晋太元中，武陵人捕鱼为业。缘溪行，忘路之远近。忽逢桃花林，夹岸数百步，中无杂树，芳草鲜美，落英缤纷。渔人甚异之，复前行，欲穷其林。\n\n'
    '林尽水源，便得一山，山有小口，仿佛若有光。便舍船，从口入。初极狭，才通人。复行数十步，豁然开朗。土地平旷，屋舍俨然，有良田美池桑竹之属。阡陌交通，鸡犬相闻。其中往来种作，男女衣着，悉如外人。黄发垂髫，并怡然自乐。\n\n'
    '见渔人，乃大惊，问所从来。具答之。便要还家，设酒杀鸡作食。村中闻有此人，咸来问讯。自云先世避秦时乱，率妻子邑人来此绝境，不复出焉，遂与外人间隔。问今是何世，乃不知有汉，无论魏晋。此人一一为具言所闻，皆叹惋。余人各复延至其家，皆出酒食。停数日，辞去。此中人语云：不足为外人道也。\n\n'
    '既出，得其船，便扶向路，处处志之。及郡下，诣太守，说如此。太守即遣人随其往，寻向所志，遂迷，不复得路。南阳刘子骥，高尚士也，闻之，欣然规往。未果，寻病终。后遂无问津者。';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp/golden-cache',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('fqapp-shot-');
    Hive.init(tmp.path);
    await LibraryStore.instance.init();
    await ShelfStore.instance.init();
    await ShelfGroupStore.instance.init();
  });

  tearDown(() async {
    await ShelfGroupStore.instance.whenIdle();
    await Hive.close().timeout(const Duration(seconds: 5), onTimeout: () => []);
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('home', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _loadFonts();

    final items = [
      _book('1', '山茶文具店', '小川糸'),
      _book('2', '长安的荔枝', '马伯庸'),
      _book('3', '人间草木', '汪曾祺'),
      _book('4', '夜间图书馆', '卡洛斯·鲁依斯'),
      _book('5', '雪国', '川端康成'),
      _book('6', '云边有个小卖部', '张嘉佳'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeProvider.overrideWith(
            () => HomeNotifier(
              homepageLoader:
                  ({
                    int tabType = 2,
                    int offset = 0,
                    String? sessionId,
                  }) async => HomepagePage(
                    items: items,
                    nextOffset: null,
                    sessionId: null,
                  ),
              searchLoader: (query, {int page = 1}) async => const [],
            ),
          ),
        ],
        child: _shell(index: 0, body: const HomePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('/tmp/shots/app-home.png'),
    );
  });

  testWidgets('library', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _loadFonts();

    await tester.runAsync(() async {
      final books = [
        _book('b1', '山茶文具店', '小川糸'),
        _book('b2', '长安的荔枝', '马伯庸'),
        _book('b3', '人间草木', '汪曾祺'),
        _book('b4', '夜间图书馆', '卡洛斯·鲁依斯'),
        _book('b5', '雪国', '川端康成'),
        _book('b6', '云边有个小卖部', '张嘉佳'),
      ];
      for (final b in books) {
        await ShelfStore.instance.add(b);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await LibraryStore.instance.addHistory({
        'id': 'b1',
        'kind': 'book',
        'title': '山茶文具店',
        'episode': 3,
        'chapterCount': 12,
        'progress': 0.42,
        'time': DateTime.now().millisecondsSinceEpoch,
      });
      await LibraryStore.instance.addHistory({
        'id': 'b2',
        'kind': 'book',
        'title': '长安的荔枝',
        'episode': 1,
        'chapterCount': 34,
        'progress': 0.18,
        'time': DateTime.now().millisecondsSinceEpoch - 3600000,
      });
    });

    await tester.pumpWidget(_shell(index: 2, body: LibraryPage(cacheStore: MemoryChapterCache())));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('/tmp/shots/app-library.png'),
    );
  });

  testWidgets('library list', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _loadFonts();
    setSingleChapterPrefs({'shelfLayout': 'list'});

    await tester.runAsync(() async {
      final books = [
        _book('b1', '山茶文具店', '小川糸'),
        _book('b2', '长安的荔枝', '马伯庸'),
        _book('b3', '人间草木', '汪曾祺'),
        _book('b4', '夜间图书馆', '卡洛斯·鲁依斯'),
        _book('b5', '雪国', '川端康成'),
        _book('b6', '云边有个小卖部', '张嘉佳'),
      ];
      for (final b in books) {
        await ShelfStore.instance.add(b);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await LibraryStore.instance.addHistory({
        'id': 'b1',
        'kind': 'book',
        'title': '山茶文具店',
        'episode': 3,
        'chapterCount': 12,
        'progress': 0.42,
        'time': DateTime.now().millisecondsSinceEpoch,
      });
      await LibraryStore.instance.addHistory({
        'id': 'b2',
        'kind': 'book',
        'title': '长安的荔枝',
        'episode': 1,
        'chapterCount': 34,
        'progress': 0.18,
        'time': DateTime.now().millisecondsSinceEpoch - 3600000,
      });
      await LibraryStore.instance.addHistory({
        'id': 'b3',
        'kind': 'book',
        'title': '人间草木',
        'episode': 20,
        'chapterCount': 48,
        'progress': 0.55,
        'time': DateTime.now().millisecondsSinceEpoch - 7200000,
      });
    });

    await tester.pumpWidget(_shell(index: 2, body: LibraryPage(cacheStore: MemoryChapterCache())));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('/tmp/shots/app-library-list.png'),
    );
  });

  testWidgets('mine', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _loadFonts();

    await tester.pumpWidget(_shell(index: 4, body: const MinePage()));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('/tmp/shots/app-mine.png'),
    );
  });

  testWidgets('reader', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _loadFonts();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.createTheme(Brightness.light),
        home: ReaderPage(
          bookId: 'b1',
          title: '桃花源记',
          chapters: [
            Chapter(itemId: '1', title: '桃花源记', volumeName: ''),
            Chapter(itemId: '2', title: '岳阳楼记', volumeName: ''),
          ],
          startIndex: 0,
          readerStore: MemoryReaderStore(),
          chapterCache: MemoryChapterCache(),
          chapterLoader: (chapter) async => _taoHuaYuan,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('/tmp/shots/app-reader.png'),
    );
  });
}
