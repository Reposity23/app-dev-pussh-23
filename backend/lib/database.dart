import 'dart:io';
import 'package:postgres/postgres.dart';
import 'models.dart';

class Database {
  static final Database _instance = Database._internal();
  factory Database() => _instance;
  Database._internal();

  late Connection _connection;

  Future<void> initialize() async {
    final databaseUrl = Platform.environment['DATABASE_URL'];
    if (databaseUrl == null) {
      throw Exception('DATABASE_URL not set');
    }

    print('Connecting to database...');
    final uri = Uri.parse(databaseUrl);
    final endpoint = Endpoint(
      host: uri.host,
      port: uri.port > 0 ? uri.port : 5432,
      database: uri.pathSegments.isNotEmpty ? uri.pathSegments[0] : 'postgres',
      username: uri.userInfo.split(':')[0],
      password: uri.userInfo.split(':')[1],
    );

    _connection = await Connection.open(
      endpoint,
      settings: ConnectionSettings(
        sslMode: SslMode.require,
        connectTimeout: Duration(seconds: 30),
      ),
    );

    print('Database connected successfully');
    await _createTables();
    print('Tables created successfully');
  }

  Future<void> _createTables() async {
    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        email TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        department TEXT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT NOW()
      )
    ''');

    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS addresses (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(id),
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        address TEXT NOT NULL,
        street TEXT NOT NULL,
        postal_code TEXT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT NOW()
      )
    ''');

    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        id TEXT PRIMARY KEY,
        toy_id TEXT NOT NULL,
        toy_name TEXT NOT NULL,
        category TEXT NOT NULL,
        rfid_uid TEXT NOT NULL,
        assigned_person TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP,
        department TEXT NOT NULL,
        total_amount DECIMAL(10, 2) NOT NULL,
        address_id TEXT REFERENCES addresses(id)
      )
    ''');
  }

  Future<void> clearAllOrders() async {
    await _connection.execute('DELETE FROM orders');
  }

  Future<User> createUser(User user) async {
    await _connection.execute(
      '''INSERT INTO users (id, username, email, password_hash, department, created_at) 
         VALUES (\$1, \$2, \$3, \$4, \$5, \$6)''',
      parameters: [
        user.id,
        user.username,
        user.email,
        user.passwordHash,
        user.department,
        user.createdAt,
      ],
    );
    return user;
  }

  Future<User?> getUserByUsername(String username) async {
    final result = await _connection.execute(
      'SELECT * FROM users WHERE username = \$1',
      parameters: [username],
    );
    
    if (result.isEmpty) return null;
    
    final row = result.first;
    return User(
      id: row[0] as String,
      username: row[1] as String,
      email: row[2] as String,
      passwordHash: row[3] as String,
      department: row[4] as String,
      createdAt: row[5] as DateTime,
    );
  }

  Future<Address> createAddress(Address address) async {
    await _connection.execute(
      '''INSERT INTO addresses (id, user_id, name, phone, address, street, postal_code, created_at) 
         VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8)''',
      parameters: [
        address.id,
        address.userId,
        address.name,
        address.phone,
        address.address,
        address.street,
        address.postalCode,
        address.createdAt,
      ],
    );
    return address;
  }

  Future<Address?> getLatestAddressByUserId(String userId) async {
    final result = await _connection.execute(
      'SELECT * FROM addresses WHERE user_id = \$1 ORDER BY created_at DESC LIMIT 1',
      parameters: [userId],
    );
    
    if (result.isEmpty) return null;
    
    final row = result.first;
    return Address(
      id: row[0] as String,
      userId: row[1] as String,
      name: row[2] as String,
      phone: row[3] as String,
      address: row[4] as String,
      street: row[5] as String,
      postalCode: row[6] as String,
      createdAt: row[7] as DateTime,
    );
  }

  Future<Order> createOrder(Order order) async {
    await _connection.execute(
      '''INSERT INTO orders (id, toy_id, toy_name, category, rfid_uid, assigned_person, 
         status, created_at, department, total_amount, address_id) 
         VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11)''',
      parameters: [
        order.id,
        order.toyId,
        order.toyName,
        order.category,
        order.rfidUid,
        order.assignedPerson,
        order.status,
        order.createdAt,
        order.department,
        order.totalAmount,
        order.addressId,
      ],
    );
    return order;
  }

  Future<Order?> updateOrder(Order order) async {
    final existing = await getOrderById(order.id);
    if (existing == null) return null;
    if (existing.status == 'COMPLETED') {
      print('Attempted to update a completed order. No action taken.');
      return null;
    }

    await _connection.execute(
      '''UPDATE orders SET status = \$1, updated_at = \$2 WHERE id = \$3''',
      parameters: [order.status, order.updatedAt, order.id],
    );
    return order;
  }

  Future<Order?> getOrderById(String id) async {
    final result = await _connection.execute(
      'SELECT * FROM orders WHERE id = \$1',
      parameters: [id],
    );
    
    if (result.isEmpty) return null;
    
    final row = result.first;
    return Order(
      id: row[0] as String,
      toyId: row[1] as String,
      toyName: row[2] as String,
      category: row[3] as String,
      rfidUid: row[4] as String,
      assignedPerson: row[5] as String,
      status: row[6] as String,
      createdAt: row[7] as DateTime,
      updatedAt: row[8] as DateTime?,
      department: row[9] as String,
      totalAmount: (row[10] is int) ? (row[10] as int).toDouble() : row[10] as double,
      addressId: row[11] as String?,
    );
  }

  Future<Order?> getOldestPendingOrderForPerson(String personName) async {
    final result = await _connection.execute(
      '''SELECT * FROM orders 
         WHERE status = 'PENDING' AND assigned_person = \$1 
         ORDER BY created_at ASC LIMIT 1''',
      parameters: [personName],
    );
    
    if (result.isEmpty) return null;
    
    final row = result.first;
    return Order(
      id: row[0] as String,
      toyId: row[1] as String,
      toyName: row[2] as String,
      category: row[3] as String,
      rfidUid: row[4] as String,
      assignedPerson: row[5] as String,
      status: row[6] as String,
      createdAt: row[7] as DateTime,
      updatedAt: row[8] as DateTime?,
      department: row[9] as String,
      totalAmount: (row[10] is int) ? (row[10] as int).toDouble() : row[10] as double,
      addressId: row[11] as String?,
    );
  }

  Future<List<Order>> getAllOrders() async {
    final result = await _connection.execute(
      'SELECT * FROM orders ORDER BY created_at DESC',
    );
    
    return result.map((row) => Order(
      id: row[0] as String,
      toyId: row[1] as String,
      toyName: row[2] as String,
      category: row[3] as String,
      rfidUid: row[4] as String,
      assignedPerson: row[5] as String,
      status: row[6] as String,
      createdAt: row[7] as DateTime,
      updatedAt: row[8] as DateTime?,
      department: row[9] as String,
      totalAmount: (row[10] is int) ? (row[10] as int).toDouble() : row[10] as double,
      addressId: row[11] as String?,
    )).toList();
  }
}
