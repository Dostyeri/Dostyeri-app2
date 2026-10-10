import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

void main() {
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
        primaryColor: const Color(0xFF1E88E5),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F1F1F),
          elevation: 2,
        ),
      ),
      home: const IRCMainScreen(),
    );
  }
}

class ChannelTab {
  final String name;
  final List<String> messages;
  final List<String> userList;

  ChannelTab({
    required this.name,
    List<String>? messages,
    List<String>? userList,
  })  : messages = messages ?? [],
        userList = userList ?? [];
}

class IRCMainScreen extends StatefulWidget {
  const IRCMainScreen({super.key});

  @override
  State<IRCMainScreen> createState() => _IRCMainScreenState();
}

class _IRCMainScreenState extends State<IRCMainScreen> with TickerProviderStateMixin {
  Socket? _socket;
  bool _isConnected = false;

  final String _server = 'irc.dostyeri.org';
  final int _port = 6667;
  late final String _currentNick;

  final List<ChannelTab> _tabs = [ChannelTab(name: 'Status')];
  TabController? _tabController;
  int _activeTabIndex = 0;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _currentNick = 'DostUser_${DateTime.now().millisecond % 1000}';
    _initTabController();
    _connectToIRC();
  }

  void _initTabController() {
    _tabController?.dispose();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) return;
      setState(() {
        _activeTabIndex = _tabController!.index;
      });
    });
  }

  void _addNewTab(String name) {
    if (!_tabs.any((t) => t.name.toLowerCase() == name.toLowerCase())) {
      setState(() {
        _tabs.add(ChannelTab(name: name));
        _initTabController();
        _tabController!.animateTo(_tabs.length - 1);
      });
    }
  }

  Future<void> _connectToIRC() async {
    _addMessage('Status', '-> $_server adresine hızlı bağlanılıyor...');
    try {
      _socket = await Socket.connect(_server, _port, timeout: const Duration(seconds: 5));
      _socket!.setOption(SocketOption.tcpNoDelay, true); // Gecikmeyi (Nagle algoritmasını) kapatır, hızı artırır

      setState(() {
        _isConnected = true;
      });
      _addMessage('Status', '-> Sunucuyla bağlantı kuruldu, yetkilendiriliyor...');

      _sendRaw('NICK $_currentNick');
      _sendRaw('USER $_currentNick 0 * :DostYeri User');

      utf8.decoder
          .bind(_socket!)
          .transform(const LineSplitter())
          .listen(
        _handleServerMessage,
        onError: (err) {
          _addMessage('Status', 'Bağlantı Hatası: $err');
          setState(() => _isConnected = false);
        },
        onDone: () {
          _addMessage('Status', 'Sunucu bağlantıyı kapattı.');
          setState(() => _isConnected = false);
        },
      );
    } catch (e) {
      _addMessage('Status', 'Bağlantı kurulamadı: $e');
      setState(() => _isConnected = false);
    }
  }

  void _sendRaw(String data) {
    if (_socket != null && _isConnected) {
      _socket!.write('$data\r\n');
      _socket!.flush(); // Verinin anında iletilmesini sağlar, gecikmeyi önler
    }
  }

  void _handleServerMessage(String line) {
    // PING isteklerine anında PONG yanıtı vererek kopma ve lag önlenir
    if (line.startsWith('PING')) {
      final pingArg = line.substring(4);
      _sendRaw('PONG$pingArg');
      return;
    }

    final timeStr = DateTime.now().toString().substring(11, 16);

    if (line.contains(' PRIVMSG ')) {
      final parts = line.split(' PRIVMSG ');
      final senderNick = parts[0].substring(1).split('!')[0];
      final rest = parts[1];
      final target = rest.substring(0, rest.indexOf(' '));
      final msg = rest.substring(rest.indexOf(' :') + 2);

      final tabTarget = target.startsWith('#') ? target : senderNick;
      _addNewTab(tabTarget);
      _addMessage(tabTarget, '[$timeStr] <$senderNick> $msg');
    } else if (line.contains(' JOIN :')) {
      final nick = line.substring(1, line.indexOf('!'));
      final channel = line.substring(line.indexOf(' JOIN :') + 7).trim();
      _addNewTab(channel);
      _addMessage(channel, '[$timeStr] ** $nick kanala katıldı.');
      _addUserToChannel(channel, nick);
    } else if (line.contains(' PART ')) {
      final nick = line.substring(1, line.indexOf('!'));
      final channel = line.split(' PART ')[1].split(' ')[0];
      _addMessage(channel, '[$timeStr] ** $nick kanaldan ayrıldı.');
      _removeUserFromChannel(channel, nick);
    } else if (line.contains(' 353 ')) {
      try {
        final colonIdx = line.indexOf(' :', 1);
        if (colonIdx != -1) {
          final headerPart = line.substring(0, colonIdx);
          final namesPart = line.substring(colonIdx + 2);
          final headerTokens = headerPart.split(' ');
          String channel = '';
          for (var token in headerTokens) {
            if (token.startsWith('#')) {
              channel = token;
              break;
            }
          }
          if (channel.isNotEmpty) {
            _addNewTab(channel);
            final nicks = namesPart.split(' ');
            for (var n in nicks) {
              final clean = n.trim();
              if (clean.isNotEmpty) {
                _addUserToChannel(channel, clean);
              }
            }
          }
        }
      } catch (_) {}
    } else {
      _addMessage('Status', line);
    }
  }

  void _addUserToChannel(String channel, String nick) {
    final tab = _tabs.firstWhere((t) => t.name.toLowerCase() == channel.toLowerCase(), orElse: () => _tabs[0]);
    if (!tab.userList.contains(nick)) {
      setState(() {
        tab.userList.add(nick);
      });
    }
  }

  void _removeUserFromChannel(String channel, String nick) {
    final tab = _tabs.firstWhere((t) => t.name.toLowerCase() == channel.toLowerCase(), orElse: () => _tabs[0]);
    setState(() {
      tab.userList.remove(nick);
    });
  }

  void _addMessage(String tabName, String msg) {
    setState(() {
      final tab = _tabs.firstWhere((t) => t.name.toLowerCase() == tabName.toLowerCase(), orElse: () => _tabs[0]);
      tab.messages.add(msg);
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    final currentTab = _tabs[_activeTabIndex];

    if (text.startsWith('/')) {
      _sendRaw(text.substring(1));
    } else if (currentTab.name != 'Status') {
      _sendRaw('PRIVMSG ${currentTab.name} :$text');
      final timeStr = DateTime.now().toString().substring(11, 16);
      _addMessage(currentTab.name, '[$timeStr] <$_currentNick> $text');
    }

    _inputController.clear();
  }

  void _showUserActionMenu(String rawNick, String channelName) {
    final cleanNick = rawNick.replaceAll(RegExp(r'[@+~%&]'), '');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C2C),
          title: Text(
            cleanNick,
            style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.chat, color: Colors.greenAccent),
                title: const Text('Özel Mesaj (Query)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addNewTab(cleanNick);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.amber),
                title: const Text('Whois Bilgisi'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendRaw('WHOIS $cleanNick');
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.orange),
                title: const Text('Engelle (Ignore)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addMessage('Status', '$cleanNick engellendi.');
                },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.star, color: Colors.yellow),
                title: const Text('Voice Ver (+v)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendRaw('MODE $channelName +v $cleanNick');
                },
              ),
              ListTile(
                leading: const Icon(Icons.security, color: Colors.cyan),
                title: const Text('Op Ver (+o)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendRaw('MODE $channelName +o $cleanNick');
                },
              ),
              ListTile(
                leading: const Icon(Icons.gavel, color: Colors.redAccent),
                title: const Text('Kick + Ban (Yasakla)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendRaw('MODE $channelName +b $cleanNick');
                  _sendRaw('KICK $channelName $cleanNick :Atıldınız.');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = _tabs.isNotEmpty && _activeTabIndex < _tabs.length ? _tabs[_activeTabIndex] : _tabs[0];

    return Scaffold(
      appBar: AppBar(
        title: Text(currentTab.name),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.people),
              tooltip: 'Kanal Rumuzları',
              onPressed: () {
                Scaffold.of(ctx).openEndDrawer();
              },
            ),
          ),
        ],
        bottom: _tabs.isNotEmpty
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: Colors.lightBlueAccent,
                labelColor: Colors.lightBlueAccent,
                unselectedLabelColor: Colors.white70,
                tabs: _tabs.map((t) => Tab(text: t.name)).toList(),
              )
            : null,
      ),
      endDrawer: Drawer(
        backgroundColor: const Color(0xFF1E1E1E),
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF2B2B2B)),
              accountName: Text('${currentTab.name} Rumuzları'),
              accountEmail: Text('${currentTab.userList.length} Kişi Bağlı'),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.lightBlue,
                child: Icon(Icons.group, color: Colors.white),
              ),
            ),
            Expanded(
              child: currentTab.userList.isEmpty
                  ? const Center(
                      child: Text(
                        'Bu kanalda listelenecek rumuz yok\n(veya Status sekmesindesiniz)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      itemCount: currentTab.userList.length,
                      itemBuilder: (ctx, idx) {
                        final nick = currentTab.userList[idx];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.person, size: 18, color: Colors.white70),
                          title: Text(nick, style: const TextStyle(fontSize: 14)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _showUserActionMenu(nick, currentTab.name);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: currentTab.messages.length,
              itemBuilder: (ctx, idx) {
                final line = currentTab.messages[idx];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            color: const Color(0xFF1F1F1F),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yaz veya komut gir (/join #kanal)...',
                      hintStyle: TextStyle(color: Colors.white38),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.lightBlueAccent),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
