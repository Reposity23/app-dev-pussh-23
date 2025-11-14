import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../lib/database.dart';
import '../lib/models.dart';
import '../lib/auth.dart';

final _clients = <WebSocketChannel>[];
final _db = Database();
final _uuid = Uuid();

// --- Main Server Setup ---
void main() async {
  await _db.initialize();
  print('Database initialized');

  final apiRouter = Router();
  // API Endpoints
  apiRouter.post('/api/login', _loginHandler);
  apiRouter.post('/api/signup', _signupHandler);
  apiRouter.post('/api/save-address', _saveAddressHandler);
  apiRouter.post('/api/orders', _createOrderHandler);
  apiRouter.get('/api/orders', _getOrdersHandler);
  apiRouter.post('/api/orders/clear', _clearOrdersHandler);
  // New endpoint for person-centric scans
  apiRouter.post('/api/process-next', _processNextOrderHandler);
  // Fast-forward endpoint
  apiRouter.post('/api/fast-forward', _fastForwardHandler);

  // WebSocket for dashboard updates
  apiRouter.get('/ws', webSocketHandler((WebSocketChannel webSocket, String? protocol) {
    _clients.add(webSocket);
    print('Dashboard client connected. Total clients: ${_clients.length}');
    webSocket.stream.listen((message) {},
     onDone: () {
      _clients.remove(webSocket);
      print('Dashboard client disconnected. Total clients: ${_clients.length}');
    });
  }));

  final dashboardPath = p.normalize(p.join(Directory.current.path, '..', 'dashboard'));
  final staticHandler = createStaticHandler(dashboardPath, defaultDocument: 'index.html');

  final cascade = Cascade().add(apiRouter.call).add(staticHandler);

  // CORS middleware
  Middleware corsMiddleware = createMiddleware(
    requestHandler: (Request request) {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
          'Access-Control-Allow-Credentials': 'true',
        });
      }
      return null;
    },
    responseHandler: (Response response) {
      return response.change(headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
        'Access-Control-Allow-Credentials': 'true',
      });
    },
  );

  final server = await shelf_io.serve(
    const Pipeline()
        .addMiddleware(corsMiddleware)
        .addMiddleware(logRequests())
        .addHandler(cascade.handler),
    '0.0.0.0', 
    5000,
  );

  print('Server running on http://${server.address.host}:${server.port}');
}

// --- New Person-Centric Handler ---
Future<Response> _processNextOrderHandler(Request request) async {
  final payload = await request.readAsString();
  final data = jsonDecode(payload);
  final personName = data['person_name'];

  if (personName == null) {
    return Response.badRequest(body: jsonEncode({'action': 'error', 'led': 'all'}));
  }

  final nextOrder = await _db.getOldestPendingOrderForPerson(personName);

  if (nextOrder == null) {
    print('Scan from $personName, but they have no pending orders.');
    return Response.ok(jsonEncode({'action': 'no_pending_orders', 'led': 'all'}));
  }

  print('Processing order ${nextOrder.toyName} for $personName');
  var updatedOrder = nextOrder.copyWith(status: 'PROCESSING', updatedAt: DateTime.now());
  await _db.updateOrder(updatedOrder);
  _broadcastToClients(updatedOrder.toJson());

  _simulateFulfillment(updatedOrder);
  
  return Response.ok(jsonEncode({'action': 'processing_success', 'led': updatedOrder.category}));
}

// --- Fast-Forward Handler ---
Future<Response> _fastForwardHandler(Request request) async {
  final payload = await request.readAsString();
  final data = jsonDecode(payload);
  final orderId = data['orderId'];
  final password = data['password'];

  if (orderId == null) {
    return Response.badRequest(body: jsonEncode({'error': 'Order ID is required'}));
  }

  if (password == null || password != 'TIP123@APPDEV') {
    return Response(403, body: jsonEncode({'error': 'Invalid admin password'}));
  }

  final order = await _db.getOrderById(orderId);
  if (order == null) {
    return Response.notFound(jsonEncode({'error': 'Order not found'}));
  }

  _broadcastToClients({
    'type': 'fast_forward',
    'orderId': orderId,
    'message': 'Fast-forward delivery simulation activated'
  });

  _simulateFastForwardFulfillment(order);

  return Response.ok(jsonEncode({
    'success': true,
    'message': 'Fast-forward activated',
    'orderId': orderId
  }));
}

// --- Fast-Forward Fulfillment Simulation (30 seconds total) ---
void _simulateFastForwardFulfillment(Order order) {
  Future.delayed(const Duration(seconds: 10), () async {
    var currentOrder = await _db.getOrderById(order.id);
    if (currentOrder == null) return;

    var onTheWayOrder = currentOrder.copyWith(status: 'ON_THE_WAY', updatedAt: DateTime.now());
    var result1 = await _db.updateOrder(onTheWayOrder);
    if (result1 == null) return;

    _broadcastToClients(result1.toJson());

    Future.delayed(const Duration(seconds: 10), () async {
      var currentOrder2 = await _db.getOrderById(order.id);
      if (currentOrder2 == null) return;

      var deliveredOrder = currentOrder2.copyWith(status: 'DELIVERED', updatedAt: DateTime.now());
      var result2 = await _db.updateOrder(deliveredOrder);
      if (result2 == null) return;

      _broadcastToClients(result2.toJson());

      Future.delayed(const Duration(seconds: 10), () async {
        var currentOrder3 = await _db.getOrderById(order.id);
        if (currentOrder3 == null) return;

        var completedOrder = currentOrder3.copyWith(status: 'COMPLETED', updatedAt: DateTime.now());
        var result3 = await _db.updateOrder(completedOrder);
        if (result3 != null) _broadcastToClients(result3.toJson());
      });
    });
  });
}

// --- CORRECTED Fulfillment Simulation ---
void _simulateFulfillment(Order order) {
  // PROCESSING -> ON_THE_WAY
  Future.delayed(const Duration(seconds: 3), () async {
    var currentOrder = await _db.getOrderById(order.id);
    if (currentOrder == null || currentOrder.status != 'PROCESSING') return;

    var onTheWayOrder = currentOrder.copyWith(status: 'ON_THE_WAY', updatedAt: DateTime.now());
    var result1 = await _db.updateOrder(onTheWayOrder);
    if (result1 == null) return;

    _broadcastToClients(result1.toJson());

    // ON_THE_WAY -> DELIVERED
    Future.delayed(const Duration(seconds: 3), () async {
      var currentOrder2 = await _db.getOrderById(order.id);
      if (currentOrder2 == null || currentOrder2.status != 'ON_THE_WAY') return;

      var deliveredOrder = currentOrder2.copyWith(status: 'DELIVERED', updatedAt: DateTime.now());
      var result2 = await _db.updateOrder(deliveredOrder);
      if (result2 == null) return;

      _broadcastToClients(result2.toJson());

      // DELIVERED -> COMPLETED
      Future.delayed(const Duration(seconds: 3), () async {
        var currentOrder3 = await _db.getOrderById(order.id);
        if (currentOrder3 == null || currentOrder3.status != 'DELIVERED') return;

        var completedOrder = currentOrder3.copyWith(status: 'COMPLETED', updatedAt: DateTime.now());
        var result3 = await _db.updateOrder(completedOrder);
        if (result3 != null) _broadcastToClients(result3.toJson());
      });
    });
  });
}

// --- Other Handlers (Mostly Unchanged) ---

Future<Response> _createOrderHandler(Request request) async {
    final authHeader = request.headers['authorization'];
    if (authHeader == null) return Response.unauthorized(jsonEncode({'error': 'Unauthorized'}));
    final token = authHeader.replaceFirst('Bearer ', '');
    final payload = AuthService.verifyToken(token);
    if (payload == null) return Response.unauthorized(jsonEncode({'error': 'Invalid token'}));
    final body = await request.readAsString();
    final data = jsonDecode(body);
    
    final userId = payload['userId'];
    final latestAddress = await _db.getLatestAddressByUserId(userId);
    
    final order = Order(
      id: _uuid.v4(),
      toyId: data['toy_id'],
      toyName: data['toy_name'],
      category: data['category'],
      rfidUid: data['rfid_uid'],
      assignedPerson: data['assigned_person'],
      status: 'PENDING',
      createdAt: DateTime.now(),
      department: data['department'],
      totalAmount: (data['total_amount'] ?? 0).toDouble(),
      addressId: latestAddress?.id,
    );
    await _db.createOrder(order);
    _broadcastToClients(order.toJson());
    return Response(201, body: jsonEncode(order.toJson()), headers: {'Content-Type': 'application/json'});
}

Future<Response> _clearOrdersHandler(Request request) async {
  await _db.clearAllOrders();
  _broadcastToClients({'type': 'clear'});
  return Response.ok(jsonEncode({'message': 'All orders cleared'}));
}

Future<Response> _getOrdersHandler(Request request) async {
  final orders = await _db.getAllOrders();
  return Response.ok(jsonEncode(orders.map((o) => o.toJson()).toList()), headers: {'Content-Type': 'application/json'});
}

Future<Response> _loginHandler(Request request) async {
  final payload = await request.readAsString();
  final data = jsonDecode(payload);
  final user = await _db.getUserByUsername(data['username']);
  if (user == null || !AuthService.verifyPassword(data['password'], user.passwordHash)) {
    return Response.unauthorized(jsonEncode({'error': 'Invalid credentials'}));
  }
  final token = AuthService.generateToken(user.id, user.username, user.department);
  return Response.ok(jsonEncode({'user': user.toSafeJson(), 'token': token}), headers: {'Content-Type': 'application/json'});
}

Future<Response> _signupHandler(Request request) async {
  final payload = await request.readAsString();
  final data = jsonDecode(payload);
  final user = User(
    id: _uuid.v4(),
    username: data['username'],
    email: data['email'],
    passwordHash: AuthService.hashPassword(data['password']),
    department: "General",
    createdAt: DateTime.now(),
  );
  await _db.createUser(user);
  final token = AuthService.generateToken(user.id, user.username, user.department);
  return Response(201, body: jsonEncode({'user': user.toSafeJson(), 'token': token}), headers: {'Content-Type': 'application/json'});
}

Future<Response> _saveAddressHandler(Request request) async {
  final authHeader = request.headers['authorization'];
  if (authHeader == null) return Response.unauthorized(jsonEncode({'error': 'Unauthorized'}));
  
  final token = authHeader.replaceFirst('Bearer ', '');
  final payload = AuthService.verifyToken(token);
  if (payload == null) return Response.unauthorized(jsonEncode({'error': 'Invalid token'}));
  
  final body = await request.readAsString();
  final data = jsonDecode(body);
  
  final address = Address(
    id: _uuid.v4(),
    userId: payload['userId'],
    name: data['name'],
    phone: data['phone'],
    address: data['address'],
    street: data['street'],
    postalCode: data['postal_code'],
    createdAt: DateTime.now(),
  );
  
  await _db.createAddress(address);
  return Response(201, body: jsonEncode(address.toJson()), headers: {'Content-Type': 'application/json'});
}

void _broadcastToClients(Map<String, dynamic> data) {
  final message = jsonEncode(data);
  _clients.removeWhere((client) => client.closeCode != null);
  for (final client in _clients) {
    try {
      client.sink.add(message);
    } catch (e) {
      print('Failed to send message to client: $e');
    }
  }
}
