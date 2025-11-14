import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class CurrentOrderScreen extends StatefulWidget {
  final String orderId;
  final String toyName;
  final String totalAmount;

  const CurrentOrderScreen({
    super.key,
    required this.orderId,
    required this.toyName,
    required this.totalAmount,
  });

  @override
  State<CurrentOrderScreen> createState() => _CurrentOrderScreenState();
}

class _CurrentOrderScreenState extends State<CurrentOrderScreen> {
  late List<OrderStatus> _statuses;
  int _currentStatusIndex = 0;
  Timer? _simulationTimer;
  bool _isFastForward = false;
  WebSocketChannel? _channel;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _initializeTimeline();
    _connectWebSocket();
    _startSimulation();
  }

  void _initializeTimeline() {
    final now = DateTime.now();
    final orderPlacedTime = now.subtract(const Duration(hours: 24));
    
    final statusMessages = [
      'Order is placed',
      'Seller is preparing to ship your parcel',
      'Your parcel has been picked up by our logistics partner',
      'Parcel has arrived at sorting facility: Tondo Hub',
      'Parcel is loaded into truck, to leave first mile hub soon',
      'Parcel has departed from sorting facility',
      'Parcel has arrived at sorting facility',
      'Parcel has arrived at sorting facility: MFM Ugong',
      'Parcel is loaded into truck, to leave first mile hub soon',
      'Parcel has arrived at sorting facility',
      'Parcel has departed from sorting facility',
      'Parcel has arrived at sorting facility: SOC 6',
      'Parcel is loaded into truck, to leave sorting center soon',
      'Parcel has departed from sorting facility',
      'Your parcel has arrived at the delivery hub: San Juan Hub',
      'Delivery driver has been assigned',
      'Your parcel is in transit to delivery address',
      'Parcel is ready to be claimed',
    ];

    _statuses = [];
    DateTime currentTime = orderPlacedTime;
    
    for (int i = 0; i < statusMessages.length; i++) {
      if (i == 0) {
        _statuses.add(OrderStatus(
          message: statusMessages[i],
          timestamp: currentTime,
        ));
      } else {
        final minutesIncrement = _random.nextInt(120) + 30;
        currentTime = currentTime.add(Duration(minutes: minutesIncrement));
        _statuses.add(OrderStatus(
          message: statusMessages[i],
          timestamp: currentTime,
        ));
      }
    }
    
    final lastStatus = _statuses.last;
    if (lastStatus.timestamp.isBefore(now)) {
      _statuses[_statuses.length - 1] = OrderStatus(
        message: lastStatus.message,
        timestamp: now,
      );
    }
  }

  void _connectWebSocket() {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final wsUrl = appProvider.config['wsUrl'] ?? 'ws://localhost:5000/ws';
      
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      _channel!.stream.listen((data) {
        try {
          final message = jsonDecode(data);
          
          if (message['type'] == 'fast_forward' && 
              message['orderId'] == widget.orderId) {
            _activateFastForward();
          }
        } catch (e) {
          print('Error parsing WebSocket message: $e');
        }
      }, onError: (error) {
        print('WebSocket error: $error');
      });
    } catch (e) {
      print('WebSocket connection error: $e');
    }
  }

  void _startSimulation() {
    const normalInterval = Duration(seconds: 5);
    
    _simulationTimer = Timer.periodic(normalInterval, (timer) {
      if (_currentStatusIndex < _statuses.length - 1) {
        setState(() {
          _currentStatusIndex++;
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _activateFastForward() {
    if (_isFastForward) return;
    
    setState(() {
      _isFastForward = true;
    });
    
    _simulationTimer?.cancel();
    
    final remaining = _statuses.length - 1 - _currentStatusIndex;
    if (remaining <= 0) return;
    
    const fastForwardDuration = Duration(seconds: 30);
    final intervalMs = fastForwardDuration.inMilliseconds ~/ remaining;
    
    _simulationTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (timer) {
        if (_currentStatusIndex < _statuses.length - 1) {
          setState(() {
            _currentStatusIndex++;
          });
        } else {
          timer.cancel();
        }
      },
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays == 0) {
      return 'Today ${DateFormat('hh:mm a').format(dateTime)}';
    } else {
      return DateFormat('MMM dd, hh:mm a').format(dateTime);
    }
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Tracking'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.toyName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Total: ₱${widget.totalAmount}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                if (_isFastForward)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '⚡ Fast-Forward Active',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _currentStatusIndex + 1,
              reverse: true,
              itemBuilder: (context, index) {
                final reversedIndex = _currentStatusIndex - index;
                final status = _statuses[reversedIndex];
                final isLatest = reversedIndex == _currentStatusIndex;
                
                return _buildTimelineItem(
                  status: status,
                  isLatest: isLatest,
                  isLast: reversedIndex == 0,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required OrderStatus status,
    required bool isLatest,
    required bool isLast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLatest ? Colors.green : Colors.blue,
                border: Border.all(
                  color: isLatest ? Colors.green : Colors.blue,
                  width: 3,
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 60,
                color: Colors.grey[300],
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDateTime(status.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status.message,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isLatest ? FontWeight.bold : FontWeight.normal,
                    color: isLatest ? Colors.black : Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class OrderStatus {
  final String message;
  final DateTime timestamp;

  OrderStatus({
    required this.message,
    required this.timestamp,
  });
}
