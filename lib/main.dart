import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MyApp());
}

class SessionData {
  String id;
  Uint8List image;
  Map<String, dynamic> extractedData;
  List<Map<String, dynamic>> chatHistory;

  SessionData({
    required this.id,
    required this.image,
    required this.extractedData,
    required this.chatHistory,
  });
}

XFile? pickedFile;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Uint8List? imageBytes;
  bool isDataReady = false;
  bool showChat = false;

  List<SessionData> sessions = [];
  int currentSessionIndex = -1;

  final picker = ImagePicker();
  final TextEditingController questionController =
      TextEditingController();

  SessionData? get currentSession {
    if (currentSessionIndex == -1) return null;
    return sessions[currentSessionIndex];
  }

  
  Future pickImage(ImageSource source) async {
    final picked = await picker.pickImage(source: source);

    if (picked != null) {
      pickedFile = picked;

      final bytes = await picked.readAsBytes();

      setState(() {
        imageBytes = bytes;
        showChat = false;
        isDataReady = false;
      });

      await uploadImage();
    }
  }


  Future pickFromGallery() async {
    await pickImage(ImageSource.gallery);
  }
  Future captureFromCamera() async {
    await pickImage(ImageSource.camera);
  }

  Future uploadImage() async {
    if (imageBytes == null || pickedFile == null) return;

    var request = http.MultipartRequest(
      'POST',
      Uri.parse("http://10.155.123.62:8000/upload/"),
    );

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        imageBytes!,
        filename: pickedFile!.name,
      ),
    );

    var response = await request.send();
    var res = await http.Response.fromStream(response);
    var data = jsonDecode(res.body);

    final newSession = SessionData(
      id: data["id"] ?? "",
      image: imageBytes!,
      extractedData: data["analysis"] ?? {},
      chatHistory: [
        {
          "type": "image",
          "data": imageBytes!,
        }
      ],
    );

    setState(() {
      sessions.add(newSession);
      currentSessionIndex = sessions.length - 1;
      isDataReady = true;
    });
  }

  Future askQuestion() async {
    if (questionController.text.isEmpty ||
        currentSession == null) return;

    var question = questionController.text;

    setState(() {
      currentSession!.chatHistory.add({
        "type": "text",
        "q": question,
        "a": "Thinking..."
      });
      questionController.clear();
    });

    var response = await http.post(
      Uri.parse("http://10.155.123.62:8000/ask/"),
      body: {
        "id": currentSession!.id,
        "question": question,
      },
    );

    var data = jsonDecode(response.body);

    setState(() {
      currentSession!.chatHistory[
          currentSession!.chatHistory.length - 1] = {
        "type": "text",
        "q": question,
        "a": data["answer"] ?? "No answer"
      };
    });
  }

  Widget buildImagePreview() {
    return Container(
      margin: const EdgeInsets.all(19),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: Image.memory(
              currentSession!.image,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  Widget buildTableView() {
  var data = currentSession!.extractedData;

  if (data.isEmpty) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Text("No readable text detected"),
    );
  }

  Color getConfidenceColor(String confidence) {
    switch (confidence.toLowerCase()) {
      case "high":
        return Colors.green;
      case "medium":
        return Colors.orange;
      case "low":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 10),
    child: Card(
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text("Field")),
            DataColumn(label: Text("Value")),
          ],
          rows: data.entries.map((entry) {
            var valueObj = entry.value;

            String value = valueObj is Map
                ? valueObj["value"] ?? "Unclear"
                : valueObj.toString();

            String confidence = valueObj is Map
                ? valueObj["confidence"] ?? ""
                : "";

            return DataRow(cells: [
              DataCell(Text(entry.key)),
              DataCell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value),
                    if (confidence.isNotEmpty)
                      Text(
                        confidence,
                        style: TextStyle(
                          fontSize: 12,
                          color: getConfidenceColor(confidence),
                        ),
                      ),
                  ],
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    ),
  );
}
  Widget buildChatUI() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: currentSession!.chatHistory.map((chat) {
              if (chat["type"] == "image") {
                return buildImagePreview();
              }
              return Column(
                children: [
                  if (chat["q"] != null)
                    chatBubble(chat["q"], true),
                  chatBubble(chat["a"], false),
                ],
              );
            }).toList(),
          ),
        ),
        inputBar(),
      ],
    );
  }

  Widget chatBubble(String text, bool isUser) {
    return Align(
      alignment: isUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF1565C0)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  Widget inputBar() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: questionController,
              decoration: InputDecoration(
                hintText: "Ask...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: askQuestion,
            icon: const Icon(Icons.send),
            color: const Color(0xFF1565C0),
          )
        ],
      ),
    );
  }

  Widget buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.description, size: 80),
        const SizedBox(height: 10),
        const Text("Upload an image to extract information"),
        const SizedBox(height: 20),

        ElevatedButton.icon(
          onPressed: pickFromGallery,
          icon: const Icon(Icons.upload),
          label: const Text("Upload Image"),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: captureFromCamera,
          icon: const Icon(Icons.camera_alt),
          label: const Text("Use Camera"),
        ),
      ],
    );
  }

  Widget buildDataUI() {
    return SingleChildScrollView(
      child: Column(
        children: [
          buildImagePreview(),
          const SizedBox(height: 10),
          buildTableView(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Information Extraction from Image",
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1565C0),
        leading: showChat
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    showChat = false;
                  });
                },
              )
            : null,
      ),

      body: currentSession == null
          ? Center(child: buildEmptyState())
          : !isDataReady
              ? const Center(child: CircularProgressIndicator())
              : showChat
                  ? buildChatUI()
                  : buildDataUI(),

      // ✅ TWO FAB BUTTONS
      floatingActionButton: (isDataReady && !showChat)
          ? Padding(
              padding:
                  const EdgeInsets.only(bottom: 20, left: 25, right: 10),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      FloatingActionButton(
                        heroTag: "gallery",
                        onPressed: pickFromGallery,
                        backgroundColor: const Color(0xFF1565C0),
                        child: const Icon(Icons.photo,
                            color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      FloatingActionButton(
                        heroTag: "camera",
                        onPressed: captureFromCamera,
                        backgroundColor: const Color(0xFF1565C0),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white),
                      ),
                    ],
                  ),
                  if (currentSession!.extractedData.isNotEmpty)
                    FloatingActionButton.extended(
                      onPressed: () {
                        setState(() => showChat = true);
                      },
                      icon: const Icon(Icons.chat,
                          color: Colors.white),
                      label: const Text("Ask",
                          style: TextStyle(color: Colors.white)),
                      backgroundColor:
                          const Color(0xFF1565C0),
                    ),
                ],
              ),
            )
          : null,
    );
  }
}
