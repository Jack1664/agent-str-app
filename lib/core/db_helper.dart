import 'dart:convert';

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
      version: 2,
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
            isMine INTEGER,
            isSystem INTEGER DEFAULT 0,
            contentType TEXT DEFAULT 'text/plain',
            metadataJson TEXT,
            attachmentsJson TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE messages ADD COLUMN isSystem INTEGER DEFAULT 0",
          );
          await db.execute(
            "ALTER TABLE messages ADD COLUMN contentType TEXT DEFAULT 'text/plain'",
          );
          await db.execute("ALTER TABLE messages ADD COLUMN metadataJson TEXT");
          await db.execute(
            "ALTER TABLE messages ADD COLUMN attachmentsJson TEXT",
          );
        }
      },
    );
  }

  static Future<void> insertMessage(
    String myAgentId,
    String peerId,
    ChatMessage msg,
  ) async {
    final db = await database;
    await db.insert('messages', {
      'myAgentId': myAgentId,
      'content': msg.content,
      'signature': msg.signature,
      'senderPubKeyHex': msg.senderPubKeyHex,
      'peerPubKeyHex': peerId,
      'timestamp': msg.timestamp,
      'isMine': msg.isMine ? 1 : 0,
      'isSystem': msg.isSystem ? 1 : 0,
      'contentType': msg.contentType,
      'metadataJson': jsonEncode(msg.metadata),
      'attachmentsJson': jsonEncode(msg.attachments),
    });
  }

  static Future<List<ChatMessage>> getMessages(
    String myAgentId,
    String peerId,
  ) async {
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
        isSystem: (maps[i]['isSystem'] ?? 0) == 1,
        contentType: maps[i]['contentType'] ?? 'text/plain',
        metadata:
            maps[i]['metadataJson'] != null &&
                maps[i]['metadataJson'].toString().isNotEmpty
            ? Map<String, dynamic>.from(
                jsonDecode(maps[i]['metadataJson']) as Map,
              )
            : const {},
        attachments:
            maps[i]['attachmentsJson'] != null &&
                maps[i]['attachmentsJson'].toString().isNotEmpty
            ? (jsonDecode(maps[i]['attachmentsJson']) as List)
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList()
            : const [],
      );
    });
  }

  static Future<void> deleteMessagesForAgent(String myAgentId) async {
    final db = await database;
    await db.delete('messages', where: 'myAgentId = ?', whereArgs: [myAgentId]);
  }
}
