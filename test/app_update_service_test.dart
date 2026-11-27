import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/app_version.dart';
import 'package:fqapp/services/app_update_service.dart';
import 'package:fqapp/services/update_prompt_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _body({int code = 230, int minCode = 0, int annId = 1, bool annOn = true}) =>
    jsonEncode({
      'schema': 1,
      'latest': {
        'versionName': '9.9.9',
        'versionCode': code,
        'minVersionCode': minCode,
        'url': 'https://example.com/dl',
        'notes': '测试更新',
      },
      'announcement': {
        'id': annId,
        'enabled': annOn,
        'title': '公告',
        'body': '内容',
      },
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdatePromptState.debugResetCache();
    UpdatePromptState.debugDirectoryResolver = null;
  });

  test('update.json 解析与版本比较', () async {
    final service = AppUpdateService(fetcher: (_) async => _body(code: 999));
    final result = await service.check();
    expect(result.ok, isTrue);
    expect(result.hasUpdate, isTrue, reason: '999 > 本机 $kVersionCode');
    expect(result.manifest!.latest.url, 'https://example.com/dl');
  });

  test('versionCode 不高于本机则无更新（等于当前版本不弹）', () async {
    final service =
        AppUpdateService(fetcher: (_) async => _body(code: kVersionCode));
    final result = await service.check();
    expect(result.ok, isTrue);
    expect(result.hasUpdate, isFalse);
  });

  test('低于 minVersionCode 标记强制更新', () async {
    final service =
        AppUpdateService(fetcher: (_) async => _body(code: 999, minCode: 500));
    final result = await service.check();
    expect(result.mustUpdate, isTrue);
  });

  test('非法 JSON 报解析失败', () async {
    final service = AppUpdateService(fetcher: (_) async => 'not-json');
    final result = await service.check();
    expect(result.ok, isFalse);
    expect(result.error, contains('解析失败'));
  });

  test('全部镜像失败时报不可达', () async {
    final service = AppUpdateService(fetcher: (_) async => null);
    final result = await service.check();
    expect(result.ok, isFalse);
    expect(result.error, contains('不可达'));
  });

  test('自动模式先回先赢：最快镜像胜出', () async {
    // raw 最慢（200ms），jsdelivr 最快（5ms）。
    final service = AppUpdateService(fetcher: (url) async {
      if (url.contains('raw.githubusercontent')) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      } else if (url.contains('jsdelivr')) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return _body(code: 999);
    });
    final result = await service.check();
    expect(result.ok, isTrue);
    expect(result.mirror, 'jsDelivr CDN');
  });

  test('手动模式只走指定镜像', () async {
    SharedPreferences.setMockInitialValues({'update_mirror': 'gitmirror'});
    String? hit;
    final service = AppUpdateService(fetcher: (url) async {
      hit = url;
      return _body(code: 999);
    });
    final result = await service.check();
    expect(result.ok, isTrue);
    expect(hit, contains('gitmirror'));
    expect(result.mirror, 'GitMirror');
  });

  test('公告按 id 幂等展示', () async {
    final ann = Announcement(id: 3, enabled: true, title: 't', body: 'b');
    expect(await AppUpdateService.shouldShowAnnouncement(ann), isTrue);
    await AppUpdateService.markAnnouncementSeen(ann);
    expect(await AppUpdateService.shouldShowAnnouncement(ann), isFalse);
    // 更旧的公告不再弹。
    final old = Announcement(id: 1, enabled: true, title: 't', body: 'b');
    expect(await AppUpdateService.shouldShowAnnouncement(old), isFalse);
  });

  test('公告 enabled=false 不展示', () async {
    final ann = Announcement(id: 9, enabled: false, title: 't', body: 'b');
    expect(await AppUpdateService.shouldShowAnnouncement(ann), isFalse);
  });

  test('自动提示同一版本只弹一次', () async {
    expect(await AppUpdateService.shouldAutoPrompt(230), isTrue);
    await AppUpdateService.markAutoPrompted(230);
    expect(await AppUpdateService.shouldAutoPrompt(230), isFalse);
    expect(await AppUpdateService.shouldAutoPrompt(231), isTrue);
  });

  test('启动自动检查默认开启、可关闭', () async {
    expect(await AppUpdateService.autoCheckEnabled(), isTrue);
    await AppUpdateService.setAutoCheckEnabled(false);
    expect(await AppUpdateService.autoCheckEnabled(), isFalse);
  });

  test('公告讲的版本本机已装时不再提示', () async {
    // 1.7.3 的公告带 versionCode=235，装机版本已经不低于它——这正是
    // 「每次打开都弹上个版本更新通知」的来源，必须直接压掉。
    final ann = Announcement(
      id: 42,
      enabled: true,
      title: 't',
      body: 'b',
      versionCode: kVersionCode,
    );
    expect(await AppUpdateService.shouldShowAnnouncement(ann), isFalse);
    // 未来版本的公告仍然要弹。
    final future = Announcement(
      id: 43,
      enabled: true,
      title: 't',
      body: 'b',
      versionCode: kVersionCode + 1,
    );
    expect(await AppUpdateService.shouldShowAnnouncement(future), isTrue);
  });

  test('SharedPreferences 丢写后文件仍记得已看过的公告', () async {
    final dir = await Directory.systemTemp.createTemp('update_state_test');
    UpdatePromptState.debugDirectoryResolver = () async => dir;
    try {
      const ann = Announcement(id: 7, enabled: true, title: 't', body: 'b');
      await AppUpdateService.markAnnouncementSeen(ann);

      // 模拟冷启动读回旧值：SP 被清空、进程内缓存也丢了。
      SharedPreferences.setMockInitialValues({});
      UpdatePromptState.debugResetCache();
      expect(await AppUpdateService.shouldShowAnnouncement(ann), isFalse);

      // 更新提示同理：同一版本不该因为 SP 丢写而重弹。
      await AppUpdateService.markAutoPrompted(501);
      SharedPreferences.setMockInitialValues({});
      UpdatePromptState.debugResetCache();
      expect(await AppUpdateService.shouldAutoPrompt(501), isFalse);
    } finally {
      UpdatePromptState.debugDirectoryResolver = null;
      await dir.delete(recursive: true);
    }
  });
}
