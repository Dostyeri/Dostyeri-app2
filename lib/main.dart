import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';

void main() => runApp(const DostYeriApp());

class DostYeriApp extends StatelessWidget {
  const DostYeriApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DostYeri.Org',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF121212)),
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
  final String text; final Color color;
  ChatMessage(this.text, {this.color = Colors.white70});
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
  late String _nick;
  final List<ChannelTab> _tabs = [ChannelTab(name: 'Status')];
  TabController? _tabController;
  int _activeIndex = 0;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String _buffer = '';
  bool _emojiOpen = false;
  final _emojis = ['😂','❤️','😍','🙏','🔥','😊','🥰','😅','👍','👋','😎','🤔','😢','🎉','💯','😀','😁','🙈','👌','💙'];

  @override
  void initState() {
    super.initState();
    _nick = 'Dost_${Random().nextInt(9000)+1000}';
    _tabController = TabController(length: 1, vsync: this);
    _tabController!.addListener(() { if(!_tabController!.indexIsChanging) { _activeIndex = _tabController!.index; setState(()=> _tabs[_activeIndex].hasNotification=false); } });
    _connect();
  }

  @override
  void dispose() { _tabController?.dispose(); _input.dispose(); _scroll.dispose(); _socket?.destroy(); super.dispose(); }

  void _addTab(String name, {bool go = false}) {
    if(_tabs.any((t)=>t.name.toLowerCase()==name.toLowerCase())) {
      if(go) { final i=_tabs.indexWhere((t)=>t.name.toLowerCase()==name.toLowerCase()); _tabController?.animateTo(i); }
      return;
    }
    setState(() { _tabs.add(ChannelTab(name: name)); _tabController?.dispose(); _tabController=TabController(length: _tabs.length, vsync: this, initialIndex: go? _tabs.length-1 : _activeIndex); if(go) _activeIndex=_tabs.length-1; });
  }

  Future<void> _connect() async {
    _addMsg('Status', ChatMessage('-> $_server bağlanıyor...', color: Colors.cyanAccent));
    try {
      try {
        _socket = await SecureSocket.connect(_server, 6697, timeout: const Duration(seconds: 8), onBadCertificate: (_)=>true);
        _addMsg('Status', ChatMessage('-> TLS 6697 🔒 bağlandı', color: Colors.greenAccent));
      } catch (_) {
        _socket = await Socket.connect(_server, 6667, timeout: const Duration(seconds: 8));
        _addMsg('Status', ChatMessage('-> 6667 bağlandı', color: Colors.cyanAccent));
      }
      setState(()=>_isConnected=true);
      _raw('NICK $_nick'); _raw('USER $_nick 0 * :Mobile');
      _socket!.listen((b){
        String d; try{ d=utf8.decode(b, allowMalformed:true);}catch(_){ d=latin1.decode(b); }
        _buffer+=d;
        while(_buffer.contains('\n')){ final i=_buffer.indexOf('\n'); final line=_buffer.substring(0,i).trim(); _buffer=_buffer.substring(i+1); if(line.isNotEmpty) _handle(line); }
      }, onDone: (){ setState(()=>_isConnected=false); _addMsg('Status', ChatMessage('Bağlantı koptu, 5sn sonra denenecek', color: Colors.redAccent)); Future.delayed(const Duration(seconds:5), _connect); });
    } catch(e){ _addMsg('Status', ChatMessage('Bağlanamadı: $e', color: Colors.redAccent)); Future.delayed(const Duration(seconds:5), _connect); }
  }

  void _raw(String s){ try{ _socket?.add(utf8.encode('$s\r\n')); }catch(_){ _socket?.add(latin1.encode('$s\r\n')); } }

  void _handle(String line){
    if(line.startsWith('PING')){ _raw('PONG${line.substring(4)}'); return; }
    final time = DateTime.now().toString().substring(11,16);
    if(line.contains(' 433 ')){ _nick='${_nick}_${Random().nextInt(99)}'; _raw('NICK $_nick'); return; }
    if(line.contains(' 001 ')){ _raw('JOIN #dostyeri'); _raw('JOIN #sohbet'); }
    if(line.contains(' PRIVMSG ')){
      final p=line.split(' PRIVMSG '); final sender=p[0].substring(1).split('!')[0]; final rest=p[1]; final target=rest.substring(0,rest.indexOf(' ')); final msg=rest.contains(' :')? rest.substring(rest.indexOf(' :')+2):'';
      final tabTarget=target.startsWith('#')? target : sender; _addTab(tabTarget);
      if(msg.toLowerCase().contains(_nick.toLowerCase())){
        final t=_tabs.firstWhere((x)=>x.name.toLowerCase()==tabTarget.toLowerCase(), orElse:()=>_tabs[0]); setState(()=>t.hasNotification=true);
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$tabTarget: $sender seni andı! $msg'), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
      }
      _addMsg(tabTarget, ChatMessage('[$time] <$sender> $msg'));
    } else if(line.contains(' JOIN ')){
      try{ final nick=line.substring(1,line.indexOf('!')); final ch=line.contains(' JOIN :')? line.substring(line.indexOf(' JOIN :')+7).trim() : line.split(' JOIN ')[1].trim().replaceAll(':',''); _addTab(ch); _addMsg(ch, ChatMessage('[$time] *** $nick girdi', color: Colors.greenAccent)); }catch(_){}
    }
  }

  void _addMsg(String tab, ChatMessage m){ setState((){ final t=_tabs.firstWhere((x)=>x.name.toLowerCase()==tab.toLowerCase(), orElse:()=>_tabs[0]); t.messages.add(m); if(t.messages.length>500) t.messages.removeRange(0,100); }); Future.delayed(const Duration(milliseconds:80),(){ if(_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds:150), curve: Curves.easeOut); }); }

  void _send(){ final txt=_input.text.trim(); if(txt.isEmpty) return; final cur=_tabs[_activeIndex]; if(txt.startsWith('/')){ _raw(txt.substring(1)); } else if(cur.name!='Status'){ _raw('PRIVMSG ${cur.name} :$txt'); _addMsg(cur.name, ChatMessage('[${DateTime.now().toString().substring(11,16)}] <$_nick> $txt')); } else { _addMsg('Status', ChatMessage('/join #dostyeri yaz', color: Colors.yellowAccent)); } _input.clear(); }

  @override
  Widget build(BuildContext context){
    final cur=_tabs[_activeIndex];
    return Scaffold(
      appBar: AppBar(title: Row(children:[Container(width:8,height:8,decoration:BoxDecoration(color:_isConnected?Colors.green:Colors.red,shape:BoxShape.circle)), const SizedBox(width:8), Expanded(child:Text(cur.name)), Text(_nick, style: const TextStyle(fontSize:10,color:Colors.white54))]), bottom: TabBar(controller: _tabController, isScrollable:true, tabs:_tabs.map((t)=>Tab(child:Text(t.name, style:TextStyle(color:t.hasNotification?Colors.redAccent:null)))).toList())),
      endDrawer: Drawer(backgroundColor: const Color(0xFF1E1E1E), child: ListView.builder(itemCount: cur.userList.length, itemBuilder:(c,i)=>ListTile(title:Text(cur.userList[i])))),
      body: Column(children:[
        Expanded(child: TabBarView(controller: _tabController, children: _tabs.map((tab)=> ListView.builder(controller: tab.name==cur.name? _scroll : null, padding: const EdgeInsets.all(8), itemCount: tab.messages.length, itemBuilder:(c,i)=> Padding(padding: const EdgeInsets.symmetric(vertical:2), child: Text(tab.messages[i].text, style: TextStyle(color: tab.messages[i].color, fontFamily:'monospace', fontSize:13))))).toList())),
        if(_emojiOpen) Container(color: const Color(0xFF1F1F1F), height: 180, child: GridView.count(crossAxisCount: 8, children: _emojis.map((e)=> InkWell(onTap: (){ _input.text+=e; }, child: Center(child: Text(e, style: const TextStyle(fontSize:24))))).toList())),
        SafeArea(child: Container(color: const Color(0xFF1F1F1F), padding: const EdgeInsets.all(6), child: Row(children:[
          IconButton(icon: const Icon(Icons.emoji_emotions_outlined), onPressed: ()=> setState(()=>_emojiOpen=!_emojiOpen)),
          Expanded(child: TextField(controller: _input, style: const TextStyle(color:Colors.white), decoration: InputDecoration(hintText: cur.name=='Status'? '/join #dostyeri':'Mesaj yaz...', filled:true, fillColor: const Color(0xFF2C2C2C), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)), onSubmitted: (_)=>_send())),
          const SizedBox(width:6), CircleAvatar(backgroundColor: Colors.blue, child: IconButton(icon: const Icon(Icons.send, size:18), onPressed: _send))
        ])))
      ]),
    );
  }
}
