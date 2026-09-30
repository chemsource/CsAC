import 'package:flutter/material.dart';

class ApiRefPage extends StatelessWidget {
  const ApiRefPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API 参考')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(context, '事件注册', [
            _api("bot.on('group.message', handler)", '群消息事件，handler 参数为 ctx'),
            _api(
              "bot.on('private.message', handler)",
              '私聊消息事件，handler 参数为 ctx',
            ),
            _api("bot.on('group.member.join', handler)", '入群事件'),
            _api("bot.on('group.member.leave', handler)", '退群/踢出事件'),
            _api("bot.on('group.member.mute', handler)", '禁言/解禁事件'),
            _api("bot.on('group.disband', handler)", '群解散事件'),
            _api("bot.command('/help', handler)", '注册指令，支持字符串或正则'),
          ]),
          _section(context, 'ctx 上下文', [
            _api('ctx.text', '消息文本'),
            _api('ctx.sender.uid', '发送者 UID'),
            _api('ctx.message.id', '消息 ID'),
            _api('ctx.group.id', '群 ID'),
            _api('ctx.bot.uid', 'Bot UID'),
            _api('ctx.reply(text)', '回复当前消息'),
            _api('ctx.send(text)', '发送消息但不引用原消息'),
          ]),
          _section(context, '群聊方法', [
            _api('csac.group.sendMessage(groupId, text)', '发送群消息'),
            _api('csac.group.replyMessage(groupId, msgId, text)', '回复群消息'),
            _api('csac.group.recallMessage(groupId, msgId)', '撤回群消息，需管理员权限'),
            _api('csac.group.setEssence(groupId, msgId)', '设置群精华，需管理员权限'),
            _api(
              'csac.group.muteMember(groupId, uid, seconds)',
              '禁言群成员，需管理员权限',
            ),
            _api('csac.group.sendImage(groupId, url)', '发送群图片'),
            _api('csac.group.leave(groupId)', '退出群聊'),
          ]),
          _section(context, '私聊方法', [
            _api('csac.private.sendMessage(uid, text)', '发送私聊消息'),
            _api('csac.private.replyMessage(uid, msgId, text)', '回复私聊消息'),
            _api('csac.private.recallMessage(uid, msgId)', '撤回 Bot 自己发送的私聊消息'),
            _api('csac.private.sendImage(uid, url)', '发送私聊图片'),
          ]),
          _section(context, '通知方法', [
            _api('csac.notice.send(uid, title, content)', '发送通知，需通知权限'),
          ]),
          _section(context, '信息查询', [
            _api('csac.user.get(uid)', '获取用户信息'),
            _api('csac.groupInfo.get(groupId)', '获取群信息'),
            _api('csac.groupInfo.memberCount(groupId)', '获取群成员数量'),
            _api('csac.groupInfo.hasMember(groupId, uid)', '判断是否为群成员'),
            _api('csac.groupInfo.botPermissions(groupId)', '获取 Bot 群管理员权限'),
          ]),
          _section(context, '外部服务', [
            _api('csac.http.get(url, options?)', 'HTTP GET 请求，需 HTTP 权限'),
            _api(
              'csac.http.post(url, {json, body, headers})',
              'HTTP POST 请求，需 HTTP 权限',
            ),
          ]),
          _section(context, '定时任务', [
            _api(
              'bot.schedule(expression, handler)',
              '注册定时任务。表达式5字段: "分 时 日 月 周"',
            ),
          ]),
          _section(context, '通用方法', [
            _api('const / let / async / await', '支持常用 JavaScript 语法'),
            _api('JSON.parse / JSON.stringify', 'JSON 处理'),
            _api('Array / Object / RegExp', '数组、对象、正则'),
            _api('Date / Math', '时间和数学工具'),
          ]),
          _section(context, '调试方法', [
            _api('logger.info(...)', '输出普通日志'),
            _api('logger.warn(...)', '输出警告日志'),
            _api('logger.error(...)', '输出错误日志'),
            _api('console.log(...)', '兼容 JS 调试习惯'),
          ]),
          _section(context, '语法特性', [
            _api('禁用能力', 'require / process / fetch / eval / new Function'),
            _api('外部 HTTP', '必须使用 csac.http，不能使用原生 fetch'),
            _api('持久化', '使用 csac.storage，不依赖全局变量持久化'),
          ]),
          _section(context, '异常类型', [
            _api('ARG_ERROR', '参数错误'),
            _api('PERMISSION_DENIED', '缺少管理员权限'),
            _api('HTTP_PERMISSION_REQUIRED', '缺少 HTTP 权限'),
            _api('NOTICE_PERMISSION_REQUIRED', '缺少通知权限'),
          ]),
          _section(context, '执行限制', [_api('执行超时', '单次加载/事件默认 3 秒超时')]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _api(String name, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              name,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
