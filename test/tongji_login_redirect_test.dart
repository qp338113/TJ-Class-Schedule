import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/import/tongji_login_redirect.dart';

void main() {
  test('把同济1系统的明文登录回调升级为 HTTPS，并保留全部参数', () {
    final result = upgradeTongjiLoginRedirect(
      'http://1.tongji.edu.cn/ssologin?token=secret&uid=user&ts=123',
    );

    expect(
      result.toString(),
      'https://1.tongji.edu.cn/ssologin?token=secret&uid=user&ts=123',
    );
  });

  test('不拦截其他统一认证网址和已经安全的同济网址', () {
    expect(
      upgradeTongjiLoginRedirect('https://1.tongji.edu.cn/ssologin'),
      isNull,
    );
    expect(
      upgradeTongjiLoginRedirect('https://iam.tongji.edu.cn/login'),
      isNull,
    );
    expect(upgradeTongjiLoginRedirect('https://example.com/login'), isNull);
  });
}
