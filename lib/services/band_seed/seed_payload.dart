/// 生成注入 app.js 的种子片段。
///
/// 片段与 PC 端 `make_seed_payload.py` 的输出逐字一致：一段 IIFE，把整本书的
/// 文件表内联成 `SEED`，首帧渲染完成后再写盘。手环端不提供包内资源读取通道
/// （`@system.file` 只认 `internal://files|cache|mass`），所以只能「启动时把
/// 书写进数据目录」，不能在运行时直接读包里的文件。
library;

import 'dart:convert';

/// 注入标记。检测「这个包已经塞过书」靠它。
const String kSeedPayloadMarker = 'injected seed payload';

/// 已写入完成的标记文件（手环侧）。
const String kSeedDoneMarker = 'internal://files/books/.seeded';

/// 把文件映射编成可直接插进 app.js 的片段。
///
/// [files] 的键是相对手环 `files/` 的路径，值是该文件文本。
String buildSeedPayload(Map<String, String> files) {
  if (files.isEmpty) {
    throw const FormatException('没有可写入的文件');
  }
  // U+2028 / U+2029 在 JS 源码里等同于换行，正文里出现会把字符串截断。
  final seed = jsonEncode(files)
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');
  return _template.replaceFirst('__SEED__', seed);
}

/// 片段里的数据部分（调试/统计用）。
int seedCharCount(Map<String, String> files) =>
    files.values.fold(0, (sum, text) => sum + text.length);

/// 与 PC 端模板一致；`\` 与 `$` 在 Dart 字符串里要转义，产物本身不变。
const String _template = r'''
  /* ---- injected seed payload (text-level, no compile) ---- */
  (function () {
    var SEED = __SEED__;
    var MARK = 'internal://files/books/.seeded';
    function log(m) { try { console.error('[SEED] ' + m); } catch (e) {} }
    var g = global;
    var st = (typeof setTimeout !== 'undefined') ? setTimeout : (g && g.setTimeout);
    function start() {
      var f = null;
      try { f = $app_require$('@app-module/system.file'); } catch (e) { return log('nofile ' + e); }
      if (!f) return log('nofile-null');

      var keys = Object.keys(SEED);
      var dirs = {};
      keys.forEach(function (k) {
        var parts = k.split('/');
        var acc = '';
        for (var i = 0; i < parts.length - 1; i++) {
          acc += (i ? '/' : '') + parts[i];
          dirs['internal://files/' + acc] = 1;
        }
      });
      var dlist = Object.keys(dirs);
      var written = 0;
      var t0 = Date.now();

      function done() {
        f.writeText({ uri: MARK, text: '1', complete: function () {
          log('seeded ' + written + '/' + keys.length + ' in ' + (Date.now() - t0) + 'ms');
          // 首帧读的是空书架，缓存必须失效，否则新数据永远读不到
          try { g.__bookshelf_cache__ = null; } catch (e) {}
          try { g.__seedBusy__ = false; } catch (e) {}
        } });
      }

      function writeAll() {
        if (!keys.length) return done();
        var pending = keys.length;
        function tick() { if (--pending === 0) done(); }
        keys.forEach(function (k) {
          var uri = 'internal://files/' + k;
          f.readText({
            uri: uri,
            success: function () { tick(); },
            fail: function () {
              f.writeText({
                uri: uri,
                text: SEED[k],
                success: function () { written++; tick(); },
                fail: function () { tick(); }
              });
            }
          });
        });
      }

      (function mkdirAll() {
        if (!dlist.length) return writeAll();
        var pending = dlist.length;
        dlist.forEach(function (d) {
          f.mkdir({ uri: d, complete: function () { if (--pending === 0) writeAll(); } });
        });
      })();
    }
    try { g.__seedBusy__ = true; } catch (e) {}
    // 延后写入：首帧渲染（约 105ms）完成后再抢 IO，避免拖慢启动。
    // 页面侧 onShow 有 __seedBusy__ 轮询兜底，不依赖写入早于首帧。
    if (st) st(start, 300); else start();
  })();
''';
