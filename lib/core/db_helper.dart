import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/chat_message.dart';

class DbHelper {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  static Future<Database> _initDb() async {
    String path = join(await getDatabasesPath(), 'agent_chat_v2.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            myAgentId TEXT,
            content TEXT,
            signature TEXT,
            senderPubKeyHex TEXT,
            peerPubKeyHex TEXT,
            timestamp INTEGER,
            isMine INTEGER
          )
        ''');
      },
    );
  }

  static Future<void> insertMessage(String myAgentId, String peerId, ChatMessage msg) async {
    final db = await database;
    await db.insert('messages', {
      'myAgentId': myAgentId,
      'content': msg.content,
      'signature': msg.signature,
      'senderPubKeyHex': msg.senderPubKeyHex,
      'peerPubKeyHex': peerId,
      'timestamp': msg.timestamp,
      'isMine': msg.isMine ? 1 : 0,
    });
  }

  static Future<List<ChatMessage>> getMessages(String myAgentId, String peerId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'myAgentId = ? AND peerPubKeyHex = ?',
      whereArgs: [myAgentId, peerId],
      orderBy: 'timestamp ASC',
    );

    return List.generate(maps.length, (i) {
      return ChatMessage(
        content: maps[i]['content'],
        signature: maps[i]['signature'],
        senderPubKeyHex: maps[i]['senderPubKeyHex'],
        timestamp: maps[i]['timestamp'],
        isMine: maps[i]['isMine'] == 1,
      );
    });
  }
}
