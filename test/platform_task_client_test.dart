import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/platform_task_client.dart';

void main() {
  FakeHttpClient canvasClient({bool partial = false, String? next}) =>
      FakeHttpClient((request) {
        switch (request.uri.path) {
          case '/api/v1/users/self/profile':
            return Reply({'id': 7});
          case '/api/v1/courses':
            return Reply([
              {'id': 1, 'name': '数学'},
              if (partial) {'id': 2, 'name': '英语'},
            ]);
          case '/api/v1/courses/1/assignments':
            return Reply([
              {
                'id': 10,
                'name': '习题',
                'due_at': '2026-10-08T00:00:00+08:00',
                'submission': {
                  'workflow_state': 'graded',
                  'submitted_at': null,
                },
              },
              {'id': 11, 'name': '隐藏', 'published': false},
            ], link: next);
          default:
            return Reply({}, status: 403);
        }
      });
  test('Canvas 使用个人截止时间与提交状态，部分失败不产生该课程快照', () async {
    final http = canvasClient(partial: true);
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    final batch = await client.collectCanvas('fixture-token');
    expect(batch.accountId, '7');
    expect(batch.tasks.single.completed, isFalse);
    expect(batch.tasks.single.dueAt, DateTime.utc(2026, 10, 7, 16));
    expect(batch.warnings, hasLength(1));
    expect(batch.successfulCourses, 1);
    expect(http.requests.every((r) => !r.followRedirects), isTrue);
    expect(http.requests.last.uri.host, 'canvas.tongji.edu.cn');
    expect(
      http.requests[2].uri.queryParameters['override_assignment_dates'],
      'true',
    );
  });
  test('Canvas 恶意跨域分页在发出请求前停止', () async {
    final http = canvasClient(
      next: '<https://evil.example/api/v1/steal>; rel="next"',
    );
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    await expectLater(
      client.collectCanvas('fixture-token'),
      throwsA(isA<PlatformRequestException>()),
    );
    expect(
      http.requests.every((r) => r.uri.host == 'canvas.tongji.edu.cn'),
      isTrue,
    );
  });
  test('Canvas 重复分页不会无限读取', () async {
    final http = canvasClient(
      next:
          '<https://canvas.tongji.edu.cn/api/v1/courses/1/assignments?include[]=submission&override_assignment_dates=true&per_page=100>; rel="next"',
    );
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    await expectLater(
      client.collectCanvas('fixture-token'),
      throwsA(isA<PlatformRequestException>()),
    );
    expect(http.requests, hasLength(3));
  });
  test('401 与登录跳转不会重试或跟随到其他站点', () async {
    for (final status in [401, 302]) {
      final http = FakeHttpClient((_) => Reply({}, status: status));
      final client = PlatformTaskClient(httpClient: http);
      await expectLater(
        client.collectCanvas('fixture-token'),
        throwsA(
          isA<PlatformRequestException>().having(
            (e) => e.statusCode,
            'HTTP status',
            status,
          ),
        ),
      );
      expect(http.requests, hasLength(1));
      expect(http.requests.single.followRedirects, isFalse);
      client.close();
    }
  });
  Map envelope(Object data) => {'code': 200, 'data': data};
  Reply haokeReply(FakeRequest request, {bool repeated = false}) {
    switch (request.uri.path) {
      case '/api/auth/queryCurrentUserInfo':
        return Reply(
          envelope({
            'userInfo': {'userId': 23},
          }),
        );
      case '/api/teach/instance/listMyClass':
        return Reply(
          envelope({
            'teachClassResponseList': [
              {'classId': 42, 'instanceId': 73, 'instanceName': '数学'},
            ],
          }),
        );
      case '/api/learn/task/queryClassInfo':
        return Reply(
          envelope({
            'columnList': [
              {
                'columnName': '课程',
                'subList': [
                  {'columnId': 9, 'columnName': '课后作业'},
                ],
              },
            ],
          }),
        );
      case '/api/learn/task/listTaskType':
        return Reply(
          envelope({
            'columnList': [
              {
                'learnShowType': 10,
                'typeList': [1, 2],
              },
            ],
          }),
        );
      case '/api/learn/task/listTask':
        return Reply(
          envelope({
            'totalRowCount': repeated ? 100 : 1,
            'rowList': [
              {
                'taskId': 1,
                'taskName': '习题',
                'myStatus': 30,
                'continueType': 20,
                'endTime': '2026-10-08 00:00:00',
              },
            ],
          }),
        );
      default:
        return Reply({}, status: 404);
    }
  }

  test('好课遍历嵌套栏目，使用真实账号 ID，已退回优先于完成', () async {
    final http = FakeHttpClient((r) => haokeReply(r));
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    final batch = await client.collectHaoke('fixture-token');
    expect(batch.accountId, '23');
    expect(batch.tasks.single.id, 'haoke:23:42:1');
    expect(batch.tasks.single.completed, isFalse);
    expect(batch.tasks.single.submissionState, 'returned');
    final body = jsonDecode(http.requests.last.body.toString());
    expect(body['taskTypes'], [1, 2]);
    expect(body['page'], {'pageNo': 1, 'pageSize': 50});
    expect(
      RegExp(
        r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
      ).hasMatch(body['requestId']),
      isTrue,
    );
  });
  test('好课重复分页停止，不保存不完整课程', () async {
    final http = FakeHttpClient((r) => haokeReply(r, repeated: true));
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    await expectLater(
      client.collectHaoke('fixture-token'),
      throwsA(isA<PlatformRequestException>()),
    );
    expect(
      http.requests.where((r) => r.uri.path.endsWith('/listTask')),
      hasLength(2),
    );
  });
  test('好课 503 只重试一次，401 和 403 不重试', () async {
    for (final status in [503, 401, 403]) {
      final http = FakeHttpClient((_) => Reply({}, status: status));
      final client = PlatformTaskClient(httpClient: http);
      await expectLater(
        client.collectHaoke('fixture-token'),
        throwsA(
          isA<PlatformRequestException>().having(
            (e) => e.statusCode,
            'HTTP status',
            status,
          ),
        ),
      );
      expect(http.requests, hasLength(status == 503 ? 2 : 1));
      client.close();
    }
  });
  test('续期返回配对票据，并携带当前 token、ticket 和 requestId', () async {
    final http = FakeHttpClient(
      (_) =>
          Reply(envelope({'token': 'next-fixture', 'ticket': 'next-ticket'})),
    );
    final client = PlatformTaskClient(httpClient: http);
    addTearDown(client.close);
    final next = await client.renewHaoke(
      const HaokeCredentials(token: 'fixture', ticket: 'fixture-ticket'),
    );
    expect(next.token, 'next-fixture');
    expect(next.ticket, 'next-ticket');
    final body = jsonDecode(http.requests.single.body.toString());
    expect(body['token'], 'fixture');
    expect(body['ticket'], 'fixture-ticket');
    expect(body['requestId'], isNotEmpty);
  });
  test('续期不会接受不完整票据或超大响应', () async {
    for (final value in [
      envelope({'token': 'fixture'}),
      envelope({'token': 'x' * 65536, 'ticket': 'fixture'}),
    ]) {
      final http = FakeHttpClient((_) => Reply(value));
      final client = PlatformTaskClient(httpClient: http);
      await expectLater(
        client.renewHaoke(
          const HaokeCredentials(token: 'fixture', ticket: 'fixture-ticket'),
        ),
        throwsA(isA<PlatformRequestException>()),
      );
      client.close();
    }
  });
  test('释放客户端后不能继续请求', () async {
    final http = canvasClient();
    final client = PlatformTaskClient(httpClient: http)..close();
    await expectLater(
      client.collectCanvas('fixture-token'),
      throwsA(isA<PlatformRequestException>()),
    );
    expect(http.requests, isEmpty);
  });
}

class Reply {
  Reply(this.data, {this.status = 200, this.link});
  final Object data;
  final int status;
  final String? link;
}

class FakeHttpClient implements HttpClient {
  FakeHttpClient(this.handler);
  final Reply Function(FakeRequest) handler;
  final requests = <FakeRequest>[];
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = FakeRequest(method, url, handler);
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRequest implements HttpClientRequest {
  FakeRequest(this.method, this.uri, this.handler);
  @override
  final String method;
  @override
  final Uri uri;
  final Reply Function(FakeRequest) handler;
  final body = StringBuffer();
  @override
  final headers = FakeHeaders();
  @override
  bool followRedirects = true;
  @override
  void write(Object? value) {
    body.write(value);
  }

  @override
  Future<HttpClientResponse> close() async => FakeResponse(handler(this));
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHeaders implements HttpHeaders {
  final values = <String, String>{};
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = '$value';
  }

  @override
  String? value(String name) => values[name.toLowerCase()];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  FakeResponse(this.reply) {
    if (reply.link != null) headers.set('link', reply.link!);
  }
  final Reply reply;
  @override
  final headers = FakeHeaders();
  @override
  int get statusCode => reply.status;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(jsonEncode(reply.data))).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
