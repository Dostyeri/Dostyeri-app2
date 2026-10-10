import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  runApp(const DostYeriApp());
}

class DostYeriApp extends StatelessWidget {
  const DostYeriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DostYeri IRC & Radyo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainTabScreen(),
    );
  }
}

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = [
    const RadioScreen(),
    const IrcLoginScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.radio),
            label: 'Canlı Radyo',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'IRC Sohbet',
          ),
        ],
      ),
    );
  }
}

// --- RADYO EKRANI ---
class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  bool _isLoading = false;
  final String _streamUrl = 'https://radyo.dostyeri.com/listen';

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _toggleRadio() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_isPlaying) {
        await _audioPlayer.stop();
        setState(() {
          _isPlaying = false;
        });
      } else {
        await _audioPlayer.setUrl(_streamUrl);
        await _audioPlayer.play();
        setState(() {
          _isPlaying = true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Radyo çalınırken hata oluştu: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DostYeri Canlı Radyo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.radio, size: 100, color: Colors.deepPurple),
            const SizedBox(height: 20),
            const Text('Kesintisiz Müzik Keyfi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton.icon(
                    onPressed: _toggleRadio,
                    icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                    label: Text(_isPlaying ? 'Radyoyu Durdur' : 'Radyoyu Başlat'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// --- IRC GİRİŞ EKRANI ---
class IrcLoginScreen extends StatefulWidget {
  const IrcLoginScreen({super.key});

  @override
  State<IrcLoginScreen> createState() => _IrcLoginScreenState();
}

class _IrcLoginScreenState extends State<IrcLoginScreen> {
  final _serverController = TextEditingController(text: 'irc.dostyeri.com');
  final _portController = TextEditingController(text: '6667');
  final _nickController = TextEditingController();
  final _passController = TextEditingController();
  final _channelController = TextEditingController(text: '#dostyeri');

  void _connect() {
    if (_nickController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir Rumuz (Nick) giriniz!')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IrcChatScreen(
          server: _serverController.text.trim(),
          port: int.tryParse(_portController.text.trim()) ?? 6667,
          nickname: _nickController.text.trim(),
          password: _passController.text.trim(),
          channel: _channelController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IRC Sohbet Bağlantısı'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const SizedBox(height: 10),
            TextField(
              controller: _serverController,
              decoration: const InputDecoration(labelText: 'Sunucu Adresi (Host)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _nickController,
              decoration: const InputDecoration(labelText: 'Rumuz (Nick)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Şifre (Opsiyonel)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _channelController,
              decoration: const InputDecoration(labelText: 'Kanal (Örn: #sohbet)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: _connect,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Sohbete Bağlan', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

// --- IRC SOHBET EKRANI ---
class IrcChatScreen extends StatefulWidget {
  final String server;
  final int port;
  final String nickname;
  final String password;
  final String channel;

  const IrcChatScreen({
    super.key,
    required this.server,
    required this.port,
    required this.nickname,
    required this.password,
    required this.channel,
  });

  @override
  State<IrcChatScreen> createState() => _IrcChatScreenState();
}

class _IrcChatScreenState extends State<IrcChatScreen> {
  Socket? _socket;
  final List<String> _messages = [];
  final TextEditingController _msgController = TextEditingController();
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectToIrc();
  }

  Future<void> _connectToIrc() async {
    try {
      setState(() {
        _messages.add('-> ${widget.server} adresine bağlanılıyor...');
      });

      _socket = await Socket.connect(widget.server, widget.port);
      
      setState(() {
        _isConnected = true;
        _messages.add('-> Sunucuya bağlandı, yetkilendiriliyor...');
      });

      if (widget.password.isNotEmpty) {
        _socket!.write('PASS ${widget.password}\r\n');
      }
      _socket!.write('NICK ${widget.nickname}\r\n');
      _socket!.write('USER ${widget.nickname} 0 * :${widget.nickname}\r\n');

      _socket!.listen(
        (data) {
          String serverResponse = utf8.decode(data);
          List<String> lines = serverResponse.split('\r\n');
          for (var line in lines) {
            if (line.isNotEmpty) {
              if (line.startsWith('PING')) {
                String pingParam = line.split(' ')[1];
                _socket!.write('PONG $pingParam\r\n');
              } else if (line.contains(' 001 ')) {
                _socket!.write('JOIN ${widget.channel}\r\n');
                if (mounted) {
                  setState(() {
                    _messages.add('-> ${widget.channel} kanalına giriş yapıldı.');
                  });
                }
              }
              if (mounted) {
                setState(() {
                  _messages.add(line);
                });
              }
            }
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isConnected = false;
              _messages.add('<- Bağlantı kapatıldı.');
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _messages.add('Hata: $error');
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add('Bağlantı Kurulamadı: $e');
        });
      }
    }
  }

  void _sendMessage() {
    if (_msgController.text.trim().isEmpty || _socket == null || !_isConnected) return;
    String text = _msgController.text.trim();
    _socket!.write('PRIVMSG ${widget.channel} :$text\r\n');
    setState(() {
      _messages.add('${widget.nickname}: $text');
    });
    _msgController.clear();
  }

  @override
  void dispose() {
    _socket?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.channel} (${_isConnected ? "Bağlı" : "Bağlanıyor..."})'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(_messages[index], style: const TextStyle(fontSize: 14)),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[200],
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: const InputDecoration(
                      hintText: 'Mesajınızı yazın...',
                      border: OutlineInputBorder(),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.deepPurple),
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
