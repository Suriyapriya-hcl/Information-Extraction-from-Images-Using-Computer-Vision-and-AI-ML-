import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MyApp());
}

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
  seedColor: const Color(0xFF1565C0), // ✅ YOUR COLOR
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

  String sessionId = "";
  Map<String, dynamic> extractedData = {};

  List<Map<String, dynamic>> chatHistory = [];

  final picker = ImagePicker();
  final TextEditingController questionController = TextEditingController();

  // ✅ PICK IMAGE
  Future pickImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      final bytes = await picked.readAsBytes();

      setState(() {
        imageBytes = bytes;
        showChat = false;
        isDataReady = false;
        extractedData = {};
        sessionId = "";
        chatHistory.clear();
      });

      await uploadImage();
    }
  }

  // ✅ UPLOAD IMAGE
  Future uploadImage() async {
    if (imageBytes == null) return;

    var request = http.MultipartRequest(
      'POST',
      Uri.parse("http://10.0.2.2:8000/upload/"),
    );

    request.files.add(
      http.MultipartFile.fromBytes('file', imageBytes!,
          filename: "upload.png"),
    );

    var response = await request.send();
    var res = await http.Response.fromStream(response);

    var data = jsonDecode(res.body);
    print("FULL API RESPONSE: $data");
    setState(() {
      sessionId = data["id"] ?? "";
      extractedData = data["analysis"] ?? {};
      isDataReady = true;

      chatHistory.clear();
      chatHistory.add({
        "type": "image",
        "data": imageBytes!,
      });
    });
  }

  // ✅ ASK QUESTION
  Future askQuestion() async {
    if (questionController.text.isEmpty || sessionId.isEmpty) return;

    var question = questionController.text;

    setState(() {
      chatHistory.add({
        "type": "text",
        "q": question,
        "a": "Thinking..."
      });
      questionController.clear();
    });

    var response = await http.post(
      Uri.parse("http://10.0.2.2:8000/ask/"),
      body: {
        "id": sessionId,
        "question": question,
      },
    );
    var data = jsonDecode(response.body);

    setState(() {
      chatHistory[chatHistory.length - 1] = {
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
              imageBytes!,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
  Widget buildTableView() {
  if (extractedData.isEmpty) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Text(
        "No readable text detected",
        style: TextStyle(color: Colors.grey),
      ),
    );
  }
  return Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: 60, // 
      vertical: 10,
    ),
    child: Card(
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DataTable(
          headingRowColor:
    MaterialStateProperty.all(
      const Color(0xFF1565C0).withOpacity(0.1), // ✅ light version
    ),
          columnSpacing: 50, // ✅ improves readability
          columns: const [
            DataColumn(
              label: Text(
                "Field",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                "Value",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          rows: extractedData.entries.map((entry) {
            return DataRow(cells: [
              DataCell(Text(entry.key)),
              DataCell(Text(entry.value.toString())),
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
            children: chatHistory.map((chat) {
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

  // ✅ CHAT BUBBLE
  Widget chatBubble(String text, bool isUser) {
    return Align(
      alignment:
          isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
    ? const Color(0xFF1565C0) // ✅ YOUR COLOR
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

  // ✅ DATA UI
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

  // ✅ INPUT BAR
  Widget inputBar() {
    return Container(
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

  // ✅ MAIN UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Information Extraction from Image",style: TextStyle(color: Colors.white),),
        centerTitle: true,
        backgroundColor: const Color(0xFF1565C0),
        // ✅ BACK BUTTON
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

      body: imageBytes == null
          ? Center(child: buildEmptyState())
          : !isDataReady
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 10),
                      Text("Extracting information..."),
                    ],
                  ),
                )
              : showChat
                  ? buildChatUI()
                  : buildDataUI(),

      // ✅ FIXED FAB (NO OVERLAP)
    floatingActionButton: (isDataReady && !showChat)
    ? Padding(
        padding: const EdgeInsets.only(
          bottom: 20,
          left: 25,   // ✅ move it slightly right
          right: 10,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ✅ LEFT → UPLOAD BUTTON (shifted right)
            FloatingActionButton(
  onPressed: pickImage,
  backgroundColor: const Color(0xFF1565C0), // ✅ keep const
  child: const Icon(
    Icons.add_photo_alternate,
    color: Colors.white, // ✅ simpler
  ),
),


            // ✅ RIGHT → ASK BUTTON
            if (extractedData.isNotEmpty)
              FloatingActionButton.extended(
                heroTag: "chat",
                onPressed: () {
                  setState(() => showChat = true);
                },
                icon: const Icon(Icons.chat,color: Colors.white),
                label: const Text("Ask",style: TextStyle(color: Colors.white),),
                backgroundColor: const Color(0xFF1565C0),
              ),
          ],
        ),
      )
    : null,
        
    );
  }

  // ✅ EMPTY SCREEN
  Widget buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.description,
            size: 80),
        const SizedBox(height: 10),
        const Text(
          "Upload an image to extract information",
          style: TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: pickImage,
          icon: const Icon(Icons.upload),
          label: const Text("Upload Image"),
        ),
      ],
    );
  }
}