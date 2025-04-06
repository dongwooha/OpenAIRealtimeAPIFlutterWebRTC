import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

class FirstPage extends StatefulWidget {
  const FirstPage({super.key});

  @override
  _FirstPageState createState() => _FirstPageState();
}

class _FirstPageState extends State<FirstPage> {
  final GlobalKey<StatusButton> buttonKey = GlobalKey<StatusButton>();
  WebSocketChannel? _channel;

//1. Call connectWebRTC when the page is loaded
  @override
  void initState() {
    super.initState();
    print("1. Page loaded");
    buttonKey.currentState?.setConnecting();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      getOpenAIWebSocketSecretKey(successBlock: (response) {
        String clientSecret = response["client_secret"]["value"] ?? "";
        print("1. OpenAI Key fetched successfully: $clientSecret");
        connectWebRTC(clientSecret);
      }, failBlock: () {
        print("1. Failed to fetch OpenAI Key");
      });
    });
  }

//1. Initialize WebRTC
  RTCPeerConnection? peerConnection;
  RTCDataChannel? dataChannel;
  MediaStream? localStream;

  // void updateSessionInstructions(String instructions) {
  //   if (_channel != null) {
  //     final event = {
  //       'type': 'session.update',
  //       'session': {'instructions': instructions}
  //     };
  //     _channel?.sink.add(jsonEncode(event));
  //     print('Session instructions updated: $instructions');
  //   } else {
  //     print('WebSocket channel is not initialized');
  //   }
  // }

//2. connectWebRTC();
  Future<void> connectWebRTC(String key) async {
    print("2. Starting connection to PeerConnection");
    try {
      // Initialize WebSocket connection
      final uri = Uri.parse('wss://api.openai.com/v1/realtime/ws');
      final headers = {
        'Authorization': 'Bearer $key',
      };
      _channel = WebSocketChannel.connect(
        uri.replace(
          scheme: 'wss',
          queryParameters: {
            'authorization': 'Bearer $key',
          },
        ),
      );

      // Listen for WebSocket messages
      _channel?.stream.listen(
        (message) {
          print('Received: $message');
        },
        onError: (error) {
          print('WebSocket error: $error');
        },
        onDone: () {
          print('WebSocket connection closed');
        },
      );

      //2.1. Initialize peerConnection
      peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });
      if (peerConnection != null) {
        print(
            "2.1. Initialized peerConnection successfully:${peerConnection!}");
      } else {
        print("2.2. Failed to initialize peerConnection");
        buttonKey.currentState?.setNotConnect();
        return;
      }

      //2.2. Add local audio stream
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
        'mandatory': {
          'googNoiseSuppression': true, // Noise suppression
          'googEchoCancellation': true, // Echo cancellation
          'googAutoGainControl': true, // Auto gain control
          'minSampleRate': 16000, // Minimum sample rate (Hz)
          'maxSampleRate': 48000, // Maximum sample rate (Hz)
          'minBitrate': 32000, // Minimum bitrate (bps)
          'maxBitrate': 128000, // Maximum bitrate (bps)
        },
        'optional': [
          {
            'googHighpassFilter': true
          }, // High-pass filter, enhances voice quality
        ],
      });
      if (localStream != null) {
        print("2.2. Added local audio stream successfully:${localStream!}");
      } else {
        print("2.2. Failed to add local audio stream");
        buttonKey.currentState?.setNotConnect();
        return;
      }
      localStream!.getTracks().forEach((track) {
        peerConnection!.addTrack(track, localStream!);
      });
      //2.3. Create data channel
      dataChannel = await peerConnection!
          .createDataChannel('oai-events', RTCDataChannelInit());
      if (dataChannel != null) {
        print("2.3. Data channel created successfully");
      } else {
        print("2.3. Failed to create data channel");
        buttonKey.currentState?.setNotConnect();
        return;
      }

      //2.4. Create Offer and set local description
      RTCSessionDescription offer = await peerConnection!.createOffer();
      print("2.4.1--Created offer");
      await peerConnection!.setLocalDescription(offer);
      print("2.4.2--Set local description: ${offer.sdp}");

      //2.5. Send SDP to server
      sendSDPToServer(offer.sdp, key, (remoteSdp) {
        print("2.5--Sent SDP to server successfully: $remoteSdp");
        //2.6. Set RemoteSdp
        try {
          RTCSessionDescription remoteDescription =
              RTCSessionDescription(remoteSdp, 'answer');
          peerConnection!.setRemoteDescription(remoteDescription);
        } catch (erroe1) {
          print("2.6 Failed to set RemoteSdp: $erroe1");
          buttonKey.currentState?.setNotConnect();
        }
      }, () {
        print("2.5--Failed to send SDP to server");
      });
      print("WebRTC Initialized");
    } catch (error) {
      print("Failed to initialize WebRTC: $error");
      buttonKey.currentState?.setNotConnect();
    }

    // Callback method:
    // Received data
    dataChannel?.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) {
        print(
            "Callback method--Received binary message of length: ${message.binary.length}");
      } else {
        print("Callback method--Received text message: ${message.text}");
      }
    };
    peerConnection?.onAddStream = (MediaStream stream) {
      print("Received remote media stream");
      // Get audio or video tracks
      var audioTracks = stream.getAudioTracks();
      var videoTracks = stream.getVideoTracks();
      if (audioTracks.isNotEmpty) {
        print("Audio track received");
        // Can be used to play audio stream
        Helper.setSpeakerphoneOn(true);
        buttonKey.currentState?.setConnected();
      } else {
        buttonKey.currentState?.setNotConnect();
      }
      if (videoTracks.isNotEmpty) {
        print("Video track received");
        // Can be used to play video stream
      }
    };
  }

  Future<void> getOpenAIWebSocketSecretKey({
    required Function(Map<String, dynamic>) successBlock,
    required Function() failBlock,
  }) async {
    final url = Uri.parse("https://api.openai.com/v1/realtime/sessions");
    const String openaiApiKey = "";

    final body = jsonEncode({
      "model": "gpt-4o-realtime-preview-2024-12-17",
      "voice": "verse",
      "instructions": """
당신은 한국어 선생님입니다. 기존의 모든 대화를 잊고 한국어로만 이야기 하세요.
한국에서 아르바이트를 구하려는 상황에 맞춰서 한국어로 면접을 진행합니다.
면접에 필요한 질문을 하세요. 질문에 답변을 받으면 적절한 질문을 추가로 해주세요.
말을 먼저 시작하세요.
"""
    });

    try {
      final response = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $openaiApiKey",
          "Content-Type": "application/json",
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        //print("Network request successful, response content: $jsonResponse");
        if (jsonResponse is Map<String, dynamic>) {
          successBlock(jsonResponse);
        } else {
          failBlock();
        }
      } else {
        //print("Network request failed, status code: ${response.statusCode}, response body: ${response.body}");
        failBlock();
      }
    } catch (e) {
      print("getOpenAIWebSocketSecretKey -- fail: $e");
      failBlock();
    }
  }

  Future<void> sendSDPToServer(String? sdp, String key,
      Function(String) onSuccess, Function() onFailure) async {
    final url = Uri.parse("https://api.openai.com/v1/realtime");
    try {
      final client = HttpClient();
      final request = await client.postUrl(url);

      // Set request headers
      request.headers.set("Authorization", "Bearer $key");
      request.headers.set("Content-Type", "application/sdp");

      // Write request body
      request.write(sdp);

      // Send request and get response
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      print("Network request successful, response content: $responseBody");
      if (responseBody.isNotEmpty) {
        onSuccess(responseBody);
      } else {
        onFailure();
      }
    } catch (e) {
      print("catch-->${e.toString()}");
      onFailure();
    }
  }

  @override
  Widget build(BuildContext context) {
    //ContentChangingButton()
    // Create GlobalKey

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ContentChangingButton(key: buttonKey),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }
}

// Button -- carrying variable data
class ContentChangingButton extends StatefulWidget {
  @override
  final GlobalKey<StatusButton> key;
  const ContentChangingButton({required this.key}) : super(key: key);
  @override
  StatusButton createState() => StatusButton();
}

class StatusButton extends State<ContentChangingButton> {
  // Initial button text
  String buttonText = "WebRTC: connecting";
  String connected_status =
      "connecting"; // not connect / connecting / connected
  // Button click event
  void clickStatusButton() {
    print("Button clicked");
  }

  // External control:
  void setConnected() {
    connected_status = "connected";
    refreshStatusButton();
  }

  // External control:
  void setConnecting() {
    connected_status = "connecting";
    refreshStatusButton();
  }

  // External control:
  void setNotConnect() {
    connected_status = "not connect";
    refreshStatusButton();
  }

  void refreshStatusButton() {
    setState(() {
      if (connected_status == "not connect") {
        buttonText = "WebRTC: not connect";
      } else if (connected_status == "connecting") {
        buttonText = "WebRTC: connecting";
      } else if (connected_status == "connected") {
        buttonText = "WebRTC: connected";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: clickStatusButton, // Set button click event
      child: Text(buttonText), // Display the text content on the button
    );
  }
}
