import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DostYeriApp());
}

class DostYeriApp extends StatelessWidget {
  const DostYeriApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DostYeri.Org',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1F1F1F)),
      ),
      home: const IRCMainScreen(),
    );
  }
}

class ChannelTab {
  final String name;
  final List<ChatMessage> messages;
  final List<String> userList;
  bool hasNotification;
  ChannelTab({required this.name, List<ChatMessage>? messages, List<String>? userList, this.hasNotification = false})
      : messages = messages?? [], userList = userList?? [];
}

class ChatMessage {
  final String text;
  final Color defaultColor;
  ChatMessage(this.text, {this.defaultColor = Colors.white70});
}

class IRCMainScreen extends StatefulWidget {
  const IRCMainScreen({super.key});
  @override
  State<IRCMainScreen> createState() => _IRCMainScreenState();
}

class _IRCMainScreenState extends State<IRCMainScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  Socket? _socket;
  bool _isConnected = false;
  final String _server = 'irc.dostyeri.org';
  final int _port = 6667;
  final int _tlsPort = 6697;
  late String _currentNick;

  final List<ChannelTab> _tabs = [ChannelTab(name: 'Status')];
  TabController? _tabController;
  int _activeTabIndex = 0;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();

  bool _emojiShowing = false;
  String _buffer = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentNick = 'Dost_${Random().nextInt(9000) + 1000}';
    _initTabController();
    _initNotifications();
    _connectToIRC();
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: android);
    await _notif.initialize(init);
    // Android 13+ izin
    final androidPlugin = _notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> _showMentionNotif(String channel, String from, String msg) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'mentions', 'Mentions',
        importance: Importance.high, priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    );
    await _notif.show(
      Random().nextInt(10000),
      '$channel - $from seni andı',
      msg,
      details,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _socket?.destroy();
    super.dispose();
  }

  void _initTabController({int? initialIndex}) {
    _tabController?.dispose();
    _tabController = TabController(
      length: _tabs.length, vsync: this,
      initialIndex: (initialIndex?? _activeTabIndex).clamp(0, _tabs.length - 1),
    );
    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) return;
      setState(() {
        _activeTabIndex = _tabController!.index;
        _tabs[_activeTabIndex].hasNotification = false;
      });
    });
  }

  void _addNewTab(String name, {bool switchTo = false}) {
    if (_tabs.any((t) => t.name.toLowerCase() == name.toLowerCase())) {
      if (switchTo) {
        final idx = _tabs.indexWhere((t) => t.name.toLowerCase() == name.toLowerCase());
        _tabController?.animateTo(idx);
      }
      return;
    }
    setState(() {
      _tabs.add(ChannelTab(name: name));
      _initTabController(initialIndex: switchTo? _tabs.length - 1 : _activeTabIndex);
      if (switchTo) _activeTabIndex = _tabs.length - 1;
    });
  }

  Future<void> _connectToIRC() async {
    _addMessage('Status', ChatMessage('-> $_server bağlanılıyor (TLS deneniyor)...', defaultColor: Colors.cyanAccent));
    try {
      // Önce TLS
      try {
        final secure = await SecureSocket.connect(_server, _tlsPort, timeout: const Duration(seconds: 10), onBadCertificate: (_) => true);
        _socket = secure;
        _addMessage('Status', ChatMessage('-> TLS 6697 ile bağlandı 🔒', defaultColor: Colors.greenAccent));
      } catch (_) {
        _socket = await Socket.connect(_server, _port, timeout: const Duration(seconds: 10));
        _addMessage('Status', ChatMessage('-> Düz 6667 ile bağlandı', defaultColor: Colors.cyanAccent));
      }

      _socket!.setOption(SocketOption.tcpNoDelay, true);
      setState(() => _isConnected = true);

      _sendRaw('NICK $_currentNick');
      _sendRaw('USER $_currentNick 0 * :DostYeri Mobile');

      _socket!.listen(
        (bytes) {
          String data;
          try { data = utf8.decode(bytes, allowMalformed: true); } catch (_) { data = latin1.decode(bytes); }
          _buffer += data;
          while (_buffer.contains('\n')) {
            final i = _buffer.indexOf('\n');
            final line = _buffer.substring(0, i).trim();
            _buffer = _buffer.substring(i + 1);
            if (line.isNotEmpty) _handleServerMessage(line);
          }
        },
        onError: (e) { _addMessage('Status', ChatMessage('Hata: $e', defaultColor: Colors.redAccent)); setState(()=>_isConnected=false); _tryReconnect(); },
        onDone: () { _addMessage('Status', ChatMessage('Bağlantı kapandı.', defaultColor: Colors.redAccent)); setState(()=>_isConnected=false); _tryReconnect(); },
      );
    } catch (e) {
      _addMessage('Status', ChatMessage('Bağlanamadı: $e - 5sn sonra tekrar', defaultColor: Colors.redAccent));
      _tryReconnect();
    }
  }

  void _tryReconnect() => Future.delayed(const Duration(seconds: 5), () { if (!_isConnected && mounted) _connectToIRC(); });

  void _sendRaw(String d) {
    if (_socket!= null) {
      try { _socket!.add(utf8.encode('$d\r\n')); } catch (_) { _socket!.add(latin1.encode('$d\r\n')); }
    }
  }

  void _handleServerMessage(String line) {
    if (line.startsWith('PING')) { _sendRaw('PONG${line.substring(4)}'); return; }
    final timeStr = DateTime.now().toString().substring(11, 16);
    if (line.contains(' 433 ')) {
      _currentNick = '${_currentNick}_${Random().nextInt(99)}';
      _sendRaw('NICK $_currentNick');
      return;
    }
    if (line.contains(' 001 ')) {
      _sendRaw('JOIN #dostyeri');
      _sendRaw('JOIN #sohbet');
    }
    if (line.contains(' PRIVMSG ')) {
      final p = line.split(' PRIVMSG ');
      final sender = p[0].substring(1).split('!')[0];
      final rest = p[1];
      final target = rest.substring(0, rest.indexOf(' '));
      final msg = rest.contains(' :')? rest.substring(rest.indexOf(' :') + 2) : '';
      final tabTarget = target.startsWith('#')? target : sender;
      _addNewTab(tabTarget);
      if (msg.toLowerCase().contains(_currentNick.toLowerCase())) {
        setState(() => _tabs.firstWhere((t) => t.name.toLowerCase() == tabTarget.toLowerCase(), orElse: () => _tabs[0]).hasNotification = true);
        _scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(content: Text('$tabTarget: $sender seni andı!'), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
        _showMentionNotif(tabTarget, sender, msg);
      }
      _addMessage(tabTarget, ChatMessage('[$timeStr] <$sender> $msg'));
    } else if (line.contains(' JOIN ')) {
      try {
        final nick = line.substring(1, line.indexOf('!'));
        final ch = line.contains(' JOIN :')? line.substring(line.indexOf(' JOIN :') + 7).trim() : line.split(' JOIN ')[1].trim().replaceAll(':', '');
        _addNewTab(ch); _addMessage(ch, ChatMessage('[$timeStr] *** $nick girdi.', defaultColor: Colors.greenAccent)); _addUserToChannel(ch, nick);
      } catch (_) {}
    } else if (line.contains(' 353 ')) {
      try {
        final colonIdx = line.indexOf(' :', 1);
        if (colonIdx!= -1) {
          final channel = line.substring(0, colonIdx).split(' ').firstWhere((t) => t.startsWith('#'), orElse: () => '');
          final names = line.substring(colonIdx + 2).split(' ');
          if (channel.isNotEmpty) { _addNewTab(channel); for (var n in names) { if (n.trim().isNotEmpty) _addUserToChannel(channel, n.trim()); } }
        }
      } catch (_) {}
    } else {
      final disp = line.contains(' :')? line.substring(line.indexOf(' :') + 2) : line;
      _addMessage('Status', ChatMessage('[$timeStr] $disp', defaultColor: Colors.lightBlueAccent));
    }
  }

  void _addUserToChannel(String ch, String nick) {
    final tab = _tabs.firstWhere((t) => t.name.toLowerCase() == ch.toLowerCase(), orElse: () => _tabs[0]);
    if (!tab.userList.any((u) => u.replaceAll(RegExp(r'[@+~%&]'), '').toLowerCase() == nick.replaceAll(RegExp(r'[@+~%&]'), '').toLowerCase())) {
      setState(() { tab.userList.add(nick); tab.userList.sort((a,b)=>a.replaceAll(RegExp(r'[@+~%&]'), '').toLowerCase().compareTo(b.replaceAll(RegExp(r'[@+~%&]'), '').toLowerCase())); });
    }
  }

  void _addMessage(String tabName, ChatMessage msg) {
    setState(() {
      final tab = _tabs.firstWhere((t) => t.name.toLowerCase() == tabName.toLowerCase(), orElse: () => _tabs[0]);
      tab.messages.add(msg);
      if (tab.messages.length > 800) tab.messages.removeRange(0, 150);
    });
    Future.delayed(const Duration(milliseconds: 80), () { if (_scrollController.hasClients) _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 150), curve: Curves.easeOut); });
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    final cur = _tabs[_activeTabIndex];
    if (text.startsWith('/')) { _sendRaw(text.substring(1)); }
    else if (cur.name!= 'Status') { _sendRaw('PRIVMSG ${cur.name} :$text'); _addMessage(cur.name, ChatMessage('[${DateTime.now().toString().substring(11,16)}] <$_currentNick> $text')); }
    else { _addMessage('Status', ChatMessage('Komut kullan: /join #dostyeri', defaultColor: Colors.yellowAccent)); }
    _inputController.clear();
    setState(() => _emojiShowing = false);
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = _tabs[_activeTabIndex];
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Row(children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: _isConnected? Colors.greenAccent : Colors.red, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(currentTab.name)),
            Text(_currentNick, style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ]),
          bottom: TabBar(controller: _tabController, isScrollable: true, tabs: _tabs.map((t) => Tab(child: Text(t.name, style: TextStyle(color: t.hasNotification? Colors.redAccent : null, fontWeight: t.hasNotification? FontWeight.bold : null)))).toList()),
        ),
        endDrawer: Drawer(backgroundColor: const Color(0xFF1E1E1E), child: ListView.builder(itemCount: currentTab.userList.length, itemBuilder: (c,i) => ListTile(dense:true, title: Text(currentTab.userList[i]), onTap: () { _addNewTab(currentTab.userList[i].replaceAll(RegExp(r'[@+~%&]'), ''), switchTo: true); Navigator.pop(c); }))),
        body: Column(children: [
          Expanded(child: TabBarView(controller: _tabController, children: _tabs.map((tab) => ListView.builder(controller: tab.name==currentTab.name?_scrollController:null, padding: const EdgeInsets.all(8), itemCount: tab.messages.length, itemBuilder: (c,i) => Padding(padding: const EdgeInsets.symmetric(vertical:2), child: Text(tab.messages[i].text, style: TextStyle(color: tab.messages[i].defaultColor, fontFamily: 'monospace', fontSize: 13.5))))).toList())),
          _buildInput(),
          if (_emojiShowing) SizedBox(height: 250, child: EmojiPicker(
            onEmojiSelected: (cat, emoji) { _inputController.text += emoji.emoji; },
            config: Config(emojiViewConfig: EmojiViewConfig(emojiSizeMax: 28)),
          )),
        ]),
      ),
    );
  }

  Widget _buildInput() {
    return SafeArea(child: Container(color: const Color(0xFF1F1F1F), padding: const EdgeInsets.all(6), child: Row(children: [
      IconButton(icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white54), onPressed: () { _focusNode.unfocus(); setState(() => _emojiShowing =!_emojiShowing); }),
      Expanded(child: TextField(controller: _inputController, focusNode: _focusNode, onTap: () => setState(()=>_emojiShowing=false), style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Mesaj...', filled: true, fillColor: const Color(0xFF2C2C2C), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)), onSubmitted: (_) => _sendMessage())),
      const SizedBox(width: 6),
      CircleAvatar(backgroundColor: Colors.lightBlue, child: IconButton(icon: const Icon(Icons.send, size: 18), onPressed: _sendMessage)),
    ])));
  }
}
