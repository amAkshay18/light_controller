import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(const LightControllerApp());
}

class LightControllerApp extends StatelessWidget {
  const LightControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Light Controller',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LightControllerScreen(),
    );
  }
}

class LightControllerScreen extends StatefulWidget {
  const LightControllerScreen({super.key});

  @override
  State<LightControllerScreen> createState() => _LightControllerScreenState();
}

class _LightControllerScreenState extends State<LightControllerScreen> {
  Map<String, dynamic> updatedPayloadMap = {};

  final String _username = 'Navin';
  final String _password = 'Navi@1405';
  final String productId = '4ltc225';

  //methods for subscription
  String getStatus(String productId) => 'onwords/$productId/currentStatus';
  String postStatusRequest(String productId) =>
      'onwords/$productId/getCurrentStatus';
  String postStatus(String productId) => 'onwords/$productId/status';

  late MqttServerClient client;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<bool> _connect() async {
    bool status = false;
    log("called local mqtt connection");
    // broker = mqtt.onwords.in;
    client = MqttServerClient.withPort("mqtt.onwords.in", "Client Test", 1883);

    client.logging(on: false);
    client.keepAlivePeriod = 60;
    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;
    client.onSubscribed = _onSubscribed;
    client.onUnsubscribed = _onUnsubscribed;

    final connectMessage = MqttConnectMessage()
        .startClean()
        .withWillQos(MqttQos.atLeastOnce)
        .withWillRetain();
    client.connectionMessage = connectMessage;

    try {
      if (client.connectionStatus!.state == MqttConnectionState.disconnected) {
        await client
            .connect(_username, _password)
            .timeout(const Duration(milliseconds: 1500));
      }
      if (isConnected) status = true;
    } catch (e) {
      log("Error in mqtt connection $e");
      client.disconnect();
    }

    return status;
  }

  bool get isConnected {
    bool connected = false;
    try {
      connected =
          client.connectionStatus!.state == MqttConnectionState.connected;
    } catch (e) {
      log('Error from MQTT status check $e');
    }
    return connected;
  }

  void disconnect() {
    client.disconnect();
  }

  Set<String> subscribedTopics = <String>{};

  void subscribe(String topic) {
    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      if (!subscribedTopics.contains(topic)) {
        client.subscribe(topic, MqttQos.atLeastOnce);
      }
    }
  }

  void unSubscribe(String topic) async {
    if (subscribedTopics.contains(topic)) {
      client.unsubscribe(topic);
      subscribedTopics.remove(topic);
    }
  }

  void _onConnected() {
    log('MQTTClient::Connected');
    _getStatusOnConnected();
  }

  void _onDisconnected() {
    log('MQTTClient::Disconnected');
    subscribedTopics.clear();
  }

  void _onSubscribed(String topic) {
    subscribedTopics.add(topic);
    log('MQTTClient::Subscribed to topic: $topic all topics are $subscribedTopics');
  }

  void _onUnsubscribed(String? topic) {
    log('MQTTClient::Unsubscribed topic: $topic all topics are $subscribedTopics');
  }

  void _getStatusOnConnected() {
    log("start");

    // Subscribe to current status topic
    String currentStatusTopic = getStatus(productId);
    client.subscribe(currentStatusTopic, MqttQos.atMostOnce);

    // Subscribe to get current status request topic
    String getCurrentStatusRequestTopic = postStatusRequest(productId);
    client.subscribe(getCurrentStatusRequestTopic, MqttQos.atMostOnce);

    // Subscribe to status topic
    String statusTopic = postStatus(productId);
    client.subscribe(statusTopic, MqttQos.atMostOnce);

    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>>? c) {
      final MqttPublishMessage receivedMessage =
          c![0].payload as MqttPublishMessage;
      final String payload = MqttPublishPayload.bytesToStringAsString(
          receivedMessage.payload.message);
      log("Received message: $payload from topic ${c[0].topic}");

      setState(() {
        payload == 'ON';
      });
    });
    log("Connected to Broker");
  }

  void publishStatus() {
    final topic = postStatus(productId);
    final builder = MqttClientPayloadBuilder();

    // Convert the updated payload map to a JSON string
    final payloadJson = jsonEncode(updatedPayloadMap);

    // Add the payload to the builder
    builder.addString(payloadJson);

    // Publish the message with the updated payload
    client.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);

    log('Published payload: $payloadJson');
  }

  Color getColorForValue(dynamic value) {
    if (value == 1) {
      return Colors.yellowAccent;
    } else if (value == 0) {
      return Colors.grey;
    } else {
      return Colors.red;
    }
  }

  Widget getDeviceTile(String deviceName, int status) {
    return Card(
      child: ListTile(
        title: Text(deviceName),
        subtitle: Text('Status: $status'),
        trailing: GestureDetector(
          onTap: () {
            setState(() {
              updatedPayloadMap[deviceName] = (status == 1) ? 0 : 1;
              publishStatus();
            });
          },
          child: Icon(
            Icons.lightbulb,
            color: status == 1 ? Colors.yellow : Colors.grey,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Light Controller App"),
      ),
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StreamBuilder<List<MqttReceivedMessage<MqttMessage>>>(
              stream: client.updates,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                } else {
                  final receivedMessages = snapshot.data ?? [];
                  if (receivedMessages.isEmpty) {
                    return const Center(
                        child: Text("No messages received yet"));
                  }
                  final MqttPublishMessage receivedMessage =
                      receivedMessages[0].payload as MqttPublishMessage;
                  final Map<String, dynamic> payloadMap = jsonDecode(
                      MqttPublishPayload.bytesToStringAsString(
                          receivedMessage.payload.message));
                  updatedPayloadMap = payloadMap;

                  return Column(
                    children: payloadMap.entries.map((entry) {
                      final deviceName = entry.key;
                      final status = entry.value;
                      return getDeviceTile(deviceName, status);
                    }).toList(),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
