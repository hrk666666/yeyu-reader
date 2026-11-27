/// 应用版本常量。发布脚本（build_release.sh）只改这里，pubspec 与
/// AboutPage.versionText 由守卫测试（about_version_test）对齐。
library;

const String kVersionName = '1.7.8';
const int kVersionCode = 240;
const String kVersionText = '$kVersionName ($kVersionCode)';
