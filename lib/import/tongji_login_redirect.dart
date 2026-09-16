/// 同济统一认证偶尔会返回明文 HTTP 地址。
/// 只升级协议，不限制其他统一认证页面的正常跳转。
Uri? upgradeTongjiLoginRedirect(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'http' ||
      uri.host.toLowerCase() != '1.tongji.edu.cn') {
    return null;
  }
  return uri.replace(scheme: 'https');
}
