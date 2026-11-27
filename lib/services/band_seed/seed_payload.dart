/// 生成「内置书入口」app.js。
///
/// 手环快应用的入口不一定要是 webpack 产物：运行时只认入口脚本默认导出对象上的
/// `manifest` 与生命周期函数。所以这里直接写一份几十 KB 的明文入口，
/// 把书数据内联进去，启动后写盘，页面字节码一个都不动。
///
/// 已用 Vela 模拟器验证：手写入口替换 183 KB bundle 后可正常启动、首页渲染、
/// 文件落盘。
library;

import 'dart:convert';

/// 已经塞过书的标记文件（手环侧）。
const String kSeedDoneMarker = 'internal://files/books/.seeded';

/// 在 app.js 里标记这是内置书入口。
const String kSeedPayloadMarker = 'injected seed payload';

/// 把 manifest 与书文件编成一份完整可用的 `app.js`。
///
/// [manifest] 是原包 manifest.json 的内容（原样内联，包名等字段由 repack 决定）。
/// [files] 的键是相对手环 `files/` 的路径，值是该文件文本。
String buildShellAppJs({
  required Map<String, dynamic> manifest,
  required Map<String, String> files,
}) {
  if (files.isEmpty) {
    throw const FormatException('没有可写入的文件');
  }
  // U+2028 / U+2029 在 JS 源码里等同于换行，正文里出现会把字符串截断。
  final seed = jsonEncode(files)
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');
  final manifestJson = _jsSingleQuoted(jsonEncode(manifest));
  return _shell
      .replaceFirst('__MANIFEST__', manifestJson)
      .replaceFirst('__SEED__', seed);
}

/// 书数据部分的字符数（调试/统计用）。
int seedCharCount(Map<String, String> files) =>
    files.values.fold(0, (sum, text) => sum + text.length);

/// 把 JSON 变成能安全放进单引号 JS 字面量的文本。
String _jsSingleQuoted(String json) => json
    .replaceAll('\\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r');

/// 入口脚本模板。`$` 与 `\` 在 Dart raw 字符串里保持原样。
const String _shell = r'''
/* 页屿 · 内置书入口（手写，非 aiot build 产物）
 *
 * injected seed payload (shell, no compile)
 *
 * 这个文件替代原包的 app.jsc：页面字节码全部保留，只把入口换成
 * 「启动后把书写进 internal://files/books/」。
 * 代价：传书通道（conn.register）不在，内置书版不需要它。
 */
export default function (global, globalThis, window, $app_exports$, $app_evaluate$) {
  var MANIFEST = JSON.parse('__MANIFEST__');
  var SEED = __SEED__;
  var MARK = 'internal://files/books/.seeded';
  var req = global.$app_require$ || (typeof $app_require$ !== 'undefined' ? $app_require$ : null);

  function log(m) { try { console.error('[SEED] ' + m); } catch (e) {} }

  // 入口拿到的 global 与页面里的 globalThis 不保证是同一个对象，
  // 页面靠 __seedBusy__ / __bookshelf_cache__ 判断要不要重读书架，两边都设一份。
  function setFlag(key, value) {
    try { global[key] = value; } catch (e) {}
    try { globalThis[key] = value; } catch (e) {}
  }

  function writeBooks() {
    if (!req) return log('no require');
    var f = null;
    try { f = req('@app-module/system.file'); } catch (e) { return log('nofile ' + e); }
    if (!f) return log('nofile-null');

    // 页面首帧只读 bookshelf.json 列书，先写它，剩下的再铺开
    var keys = Object.keys(SEED);
    keys.sort(function (a, b) {
      var A = a === 'books/bookshelf.json' ? 0 : 1;
      var B = b === 'books/bookshelf.json' ? 0 : 1;
      return A - B;
    });
    var t0 = Date.now();
    var written = 0;

    function reloadHome() {
      try {
        var r = req('@app-module/system.router');
        if (!r || !r.replace) return log('no router');
        var uri = (MANIFEST.router && MANIFEST.router.entry) || 'pages/index';
        r.replace({ uri: uri });
        log('reload ' + uri);
      } catch (e) { log('reload fail ' + e); }
    }

    function finish() {
      f.writeText({ uri: MARK, text: '1', complete: function () {
        log('seeded ' + written + '/' + keys.length + ' in ' + (Date.now() - t0) + 'ms');
        // 首帧读的是空书架，缓存必须失效，否则新数据永远读不到
        setFlag('__bookshelf_cache__', null);
        setFlag('__seedBusy__', false);
        // 页面已经在首帧把空态画出来了，缓存清了也不会自己重读：
        // 主动回一次首页，让页面重建时读到写好的书架。
        var later = (typeof setTimeout !== 'undefined') ? setTimeout : (global && global.setTimeout);
        if (later) { later(reloadHome, 300); } else { reloadHome(); }
      } });
    }

    function writeAll() {
      if (!keys.length) return finish();
      var pending = keys.length;
      function tick() { if (--pending === 0) finish(); }
      keys.forEach(function (k) {
        f.writeText({
          uri: 'internal://files/' + k,
          text: SEED[k],
          success: function () { written++; tick(); },
          fail: function (e) { log('write fail ' + k); tick(); }
        });
      });
    }

    // 只建两个目录：其余子目录 writeText 会自己补齐，逐个 mkdir 只会刷一堆
    // operation not permitted。
    f.mkdir({ uri: 'internal://files/books/', complete: function () {
      f.mkdir({ uri: 'internal://files/books/storage-api/', complete: writeAll });
    } });
  }

  setFlag('__seedBusy__', true);
  // 立即写：首帧会去读 bookshelf.json，晚 300ms 就只能看到空书架。
  // 写盘是异步 IO，JS 侧只是发起调用，实测不拖慢首帧。
  writeBooks();

  // 原 app.ux 只做两件事：建目录、按用户设置恢复亮度。前者已在写盘里覆盖。
  // 亮度恢复暂时不做：模拟器对未实现的 feature 取模块会抛不可捕获的错误，
  // 直接把 LVGL 带崩，得在真机上单独验证再补。
  $app_exports$.default = {};
  $app_exports$.default.manifest = MANIFEST;
  // app.ux 没有 <style>，编译产物里是空数组；但页面元素会用 style 绑定，
  // 缺了这一项 detail 页会报「style 函数没有求值」并白屏。
  $app_exports$.default.style = [];
  $app_exports$.default.onShow = function () {};

  // 同样是 app.ux 编译时挂到全局上的工具函数，页面样式绑定要用
  try {
    global.$translateStyle$ = function (value) {
      if (typeof value === 'string') {
        return Object.fromEntries(
          value.split(';')
            .filter(function (item) { return Boolean(item && item.trim()); })
            .map(function (item) {
              var m = item.match(/([^:]+):(.*)/);
              if (m && m.length > 2) {
                return [m[1].trim().replace(/-([a-z])/g, function (_, c) { return c.toUpperCase(); }), m[2].trim()];
              }
              return [];
            })
        );
      }
      return value;
    };
  } catch (e) { log('translateStyle fail ' + e); }
}
''';
