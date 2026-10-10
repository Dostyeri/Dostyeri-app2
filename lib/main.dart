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
  final List<ChatMessage> messages;
  final List<String> userList;
  bool hasNotification;

  ChannelTab({
    required this.name,
    List<ChatMessage>? messages,
    List<String>? userList,
    this.hasNotification = false,
  })  : messages = messages ?? [],
        userList = userList ?? [];
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
  
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  String _buffer = '';

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
        _tabs[_activeTabIndex].hasNotification = false;
      });
    });
  }

  void _addNewTab(String name) {
    if (!_tabs.any((t) => t.name.toLowerCase() == name.toLowerCase())) {
      setState(() {
        _tabs.add(ChannelTab(name: name));
        _initTabController();
      });
    }
  }

  Future<void> _connectToIRC() async {
    _addMessage('Status', ChatMessage('-> $_server adresine bağlanılıyor...', defaultColor: Colors.cyanAccent));
    try {
      _socket = await Socket.connect(_server, _port, timeout: const Duration(seconds: 10));
      _socket!.setOption(SocketOption.tcpNoDelay, true);

      setState(() {
        _isConnected = true;
      });
      _addMessage('Status', ChatMessage('-> Sunucuyla bağlantı kuruldu, yetkilendiriliyor...', defaultColor: Colors.cyanAccent));

      _sendRaw('NICK $_currentNick');
      _sendRaw('USER $_currentNick 0 * :DostYeri User');

      _socket!.listen(
        (List<int> bytes) {
          final data = latin1.decode(bytes);
          _buffer += data;
          
          while (_buffer.contains('\n')) {
            final index = _buffer.indexOf('\n');
            final line = _buffer.substring(0, index).trim();
            _buffer = _buffer.substring(index + 1);
            if (line.isNotEmpty) {
              _handleServerMessage(line);
            }
          }
        },
        onError: (err) {
          _addMessage('Status', ChatMessage('Bağlantı Hatası: $err', defaultColor: Colors.redAccent));
          setState(() => _isConnected = false);
        },
        onDone: () {
          _addMessage('Status', ChatMessage('Sunucu bağlantıyı kapattı.', defaultColor: Colors.redAccent));
          setState(() => _isConnected = false);
        },
      );
    } catch (e) {
      _addMessage('Status', ChatMessage('Bağlantı kurulamadı: $e', defaultColor: Colors.redAccent));
      setState(() => _isConnected = false);
    }
  }

  void _sendRaw(String data) {
    if (_socket != null && _isConnected) {
      _socket!.add(latin1.encode('$data\r\n'));
      _socket!.flush();
    }
  }

  void _handleServerMessage(String line) {
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
      
      if (msg.toLowerCase().contains(_currentNick.toLowerCase())) {
        final tab = _tabs.firstWhere((t) => t.name.toLowerCase() == tabTarget.toLowerCase(), orElse: () => _tabs[0]);
        setState(() {
          tab.hasNotification = true;
        });

        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('$tabTarget: $senderNick size seslendi!'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      _addMessage(tabTarget, ChatMessage('[$timeStr] <$senderNick> $msg', defaultColor: Colors.white));
    } 
    else if (line.contains(' NOTICE ')) {
      try {
        final parts = line.split(' NOTICE ');
        final sender = parts[0].startsWith(':') ? parts[0].substring(1).split('!')[0] : 'Sunucu';
        final rest = parts[1];
        final msg = rest.contains(' :') ? rest.substring(rest.indexOf(' :') + 2) : rest;

        _addMessage('Status', ChatMessage('[$timeStr] *** [$sender] $msg', defaultColor: Colors.purpleAccent));
      } catch (_) {
        _addMessage('Status', ChatMessage('[$timeStr] $line', defaultColor: Colors.purpleAccent));
      }
    }
    else if (line.contains(' JOIN :') || (line.contains(' JOIN ') && !line.contains(' 353 '))) {
      try {
        final nick = line.substring(1, line.indexOf('!'));
        String channel = '';
        if (line.contains(' JOIN :')) {
          channel = line.substring(line.indexOf(' JOIN :') + 7).trim();
        } else {
          channel = line.split(' JOIN ')[1].trim();
          if (channel.startsWith(':')) channel = channel.substring(1);
        }

        _addNewTab(channel);
        _addMessage(channel, ChatMessage('[$timeStr] *** $nick kanala girdi.', defaultColor: Colors.greenAccent));
        _addUserToChannel(channel, nick);
      } catch (_) {}
    } 
    else if (line.contains(' PART ')) {
      try {
        final nick = line.substring(1, line.indexOf('!'));
        final channel = line.split(' PART ')[1].split(' ')[0];
        _addMessage(channel, ChatMessage('[$timeStr] *** $nick kanaldan ayrıldı (part).', defaultColor: Colors.orangeAccent));
        _removeUserFromChannel(channel, nick);
      } catch (_) {}
    } 
    else if (line.contains(' QUIT ')) {
      try {
        final nick = line.substring(1, line.indexOf('!'));
        for (var tab in _tabs) {
          if (tab.userList.contains(nick) || tab.userList.any((u) => u.contains(nick))) {
            _addMessage(tab.name, ChatMessage('[$timeStr] *** $nick sunucudan çıktı.', defaultColor: Colors.redAccent));
            _removeUserFromChannel(tab.name, nick);
          }
        }
      } catch (_) {}
    } 
    else if (line.contains(' MODE ')) {
      try {
        final prefix = line.substring(1);
        final sender = prefix.contains('!') ? prefix.split('!')[0] : 'Sunucu';
        final modePart = line.split(' MODE ')[1];
        final target = modePart.split(' ')[0];
        final modes = modePart.substring(target.length).trim();

        if (target.startsWith('#')) {
          _addMessage(target, ChatMessage('[$timeStr] *** $sender kanal modunu değiştirdi: $modes', defaultColor: Colors.yellowAccent));
        } else {
          _addMessage('Status', ChatMessage('[$timeStr] *** $sender mod değişikliği: $target $modes', defaultColor: Colors.yellowAccent));
        }
      } catch (_) {}
    } 
    else if (line.contains(' 353 ')) {
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
    } 
    else {
      String displayLine = line;
      if (line.contains(' :')) {
        final colonIdx = line.indexOf(' :');
        displayLine = line.substring(colonIdx + 2);
      }
      _addMessage('Status', ChatMessage('[$timeStr] $displayLine', defaultColor: Colors.lightBlueAccent));
    }
  }

  void _addUserToChannel(String channel, String nick) {
    final tab = _tabs.firstWhere((t) => t.name.toLowerCase() == channel.toLowerCase(), orElse: () => _tabs[0]);
    if (!tab.userList.contains(nick)) {
      setState(() {
        tab.userList.add(nick);
        tab.userList.sort((a, b) {
          final cleanA = a.replaceAll(RegExp(r'[@+~%&]'), '').toLowerCase();
          final cleanB = b.replaceAll(RegExp(r'[@+~%&]'), '').toLowerCase();
          return cleanA.compareTo(cleanB);
        });
      });
    }
  }

  void _removeUserFromChannel(String channel, String nick) {
    final tab = _tabs.firstWhere((t) => t.name.toLowerCase() == channel.toLowerCase(), orElse: () => _tabs[0]);
    setState(() {
      tab.userList.removeWhere((u) => u.replaceAll(RegExp(r'[@+~%&]'), '').toLowerCase() == nick.replaceAll(RegExp(r'[@+~%&]'), '').toLowerCase());
    });
  }

  void _addMessage(String tabName, ChatMessage msg) {
    setState(() {
      final tab = _tabs.firstWhere((t) => t.name.toLowerCase() == tabName.toLowerCase(), orElse: () => _tabs[0]);
      tab.messages.add(msg);
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
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
      _addMessage(currentTab.name, ChatMessage('[$timeStr] <$_currentNick> $text', defaultColor: Colors.white));
    }

    _inputController.clear();
  }

  // mIRC Renk Kodlarını Çözümleyen Parser
  List<TextSpan> _parseMircColors(String text, Color baseColor) {
    final List<TextSpan> spans = [];
    // mIRC renk kodu: \x03 (ASCII 3) veya ANSI kodları
    // Basit ve güvenli bir regex tabanlı split/parse mekanizması
    final regex = RegExp(r'\x03(\d{1,2})?(?:,\d{1,2})?|\x02|\x1F|\x0F|\x16');
    
    int currentIndex = 0;
    Color currentColor = baseColor;
    bool isBold = false;
    bool isUnderline = false;

    for (final match in regex.allMatches(text)) {
      if (match.start > currentIndex) {
        final plainText = text.substring(currentIndex, match.start);
        spans.add(TextSpan(
          text: plainText,
          style: TextStyle(
            color: currentColor,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            decoration: isUnderline ? TextDecoration.underline : TextDecoration.none,
          ),
        ));
      }

      final code = match.group(0)!;
      if (code.startsWith('\x03')) {
        // Renk kodu değişimi
        final matchNum = RegExp(r'\d{1,2}').firstMatch(code);
        if (matchNum != null) {
          final colorCode = int.tryParse(matchNum.group(0)!) ?? 0;
          currentColor = _getMircColor(colorCode, baseColor);
        } else {
          // Kod sıfırlama (\x03 tek başına renkleri normale döndürür)
          currentColor = baseColor;
        }
      } else if (code == '\x02') {
        isBold = !isBold;
      } else if (code == '\x1F') {
        isUnderline = !isUnderline;
      } else if (code == '\x0F') {
        // Tüm biçimlendirmeyi sıfırla
        currentColor = baseColor;
        isBold = false;
        isUnderline = false;
      }

      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: TextStyle(
          color: currentColor,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          decoration: isUnderline ? TextDecoration.underline : TextDecoration.none,
        ),
      ));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: TextStyle(color: baseColor)));
    }

    return spans;
  }

  // Standart mIRC 16 Renk Paleti Karşılığı
  Color _getMircColor(int code, Color fallback) {
    switch (code) {
      case 0: return Colors.white;
      case 1: return Colors.black;
      case 2: return Colors.blue.shade900;
      case 3: return Colors.green;
      case 4: return Colors.red;
      case 5: return Colors.brown;
      case 6: return Colors.purple;
      case 7: return Colors.orange;
      case 8: return Colors.yellow;
      case 9: return Colors.lightGreen;
      case 10: return Colors.teal;
      case 11: return Colors.cyan;
      case 12: return Colors.blue;
      case 13: return Colors.pink;
      case 14: return Colors.grey;
      case 15: return Colors.grey.shade400;
      default: return fallback;
    }
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
                  _addMessage('Status', ChatMessage('$cleanNick engellendi.', defaultColor: Colors.orange));
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

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF1E88E5),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F1F1F),
          elevation: 2,
        ),
      ),
      home: Scaffold(
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
                  tabs: _tabs.map((t) {
                    return Tab(
                      child: Text(
                        t.name,
                        style: TextStyle(
                          color: t.hasNotification ? Colors.redAccent : null,
                          fontWeight: t.hasNotification ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
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
                          tex
