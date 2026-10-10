import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:irc/irc.dart';

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
        configuration: ViewConfiguration.empty,
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
  Client? _ircClient;
  final List<String> _messages = [];
  final TextEditingController _msgController = TextEditingController();
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectToIrc();
  }

  void _connectToIrc() {
    final conf = ClientConfiguration(
      widget.nickname,
      widget.nickname,
      widget.nickname,
      'DostYeri User',
      preferredEncodings: ['utf-8'],
    );

    _ircClient = Client(conf);

    _ircClient!.onConnected.listen((_) {
      if (mounted) {
        setState(() {
          _isConnected = true;
          _messages.add('-> Sunucuya başarıyla bağlanıldı.');
        });
      }
      _ircClient!.sendCommand(OClients.join(widget.channel));
    });

    _ircClient!.onMessage.listen((message) {
      if (mounted) {
        setState(() {
          _messages.add('${message.from}: ${message.text}');
        });
      }
    });

    _ircClient!.onClose.listen((_) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _messages.add('<- Sunucu bağlantısı kesildi.');
        });
      }
    });

    try {
      _ircClient!.connect(widget.server, port: widget.port);
    } catch (e) {
      setState(() {
        _messages.add('Bağlantı Hatası: $e');
      });
    }
  }

  void _sendMessage() {
    if (_msgController.text.trim().isEmpty || _ircClient == null) return;
    String text = _msgController.text.trim();
    _ircClient!.sendMessage(widget.channel, text);
    setState(() {
      _messages.add('${widget.nickname}: $text');
    });
    _msgController.clear();
  }

  @override
  void dispose() {
    _ircClient?.disconnect();
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
                  child: Text(_messages[index], style: const TextStyle(fontSize: 16)),
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
