# Google Gemini Integration

Complete guide for integrating Flutter MCP with Google's Gemini AI models.

## Overview

This guide demonstrates how to integrate Flutter MCP with Google's Gemini API for:
- Multi-modal AI interactions (text, image, video, audio)
- Advanced reasoning capabilities
- Code generation and analysis
- Long context window support (up to 1M tokens)
- Safety filtering and content moderation
- Real-time streaming responses

## Setup

### API Configuration

```yaml
# pubspec.yaml
dependencies:
  flutter_mcp: ^1.0.0
  google_generative_ai: ^0.2.0
  http: ^1.0.0
```

```dart
// lib/gemini_integration.dart
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class GeminiIntegration {
  final String apiKey;
  final FlutterMCP mcp;
  late GenerativeModel model;
  
  GeminiIntegration({
    required this.apiKey,
    required this.mcp,
    String modelName = 'gemini-1.5-pro',
  }) {
    model = GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.9,
        maxOutputTokens: 8192,
      ),
    );
  }
  
  Future<String> generateContent(String prompt) async {
    final content = [Content.text(prompt)];
    final response = await model.generateContent(content);
    return response.text ?? '';
  }
  
  Stream<String> streamContent(String prompt) async* {
    final content = [Content.text(prompt)];
    final responses = model.generateContentStream(content);
    
    await for (final response in responses) {
      if (response.text != null) {
        yield response.text!;
      }
    }
  }
  
  Future<String> analyzeImage(File imageFile, String prompt) async {
    final imageBytes = await imageFile.readAsBytes();
    final content = [
      Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', imageBytes),
      ])
    ];
    
    final response = await model.generateContent(content);
    return response.text ?? '';
  }
}
```

## MCP Server Implementation

### Gemini-Powered MCP Server

```javascript
// server/gemini-mcp-server.js
const { Server } = require('@modelcontextprotocol/sdk/server/index.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const { GoogleGenerativeAI } = require('@google/generative-ai');

class GeminiMCPServer {
  constructor(apiKey) {
    this.genAI = new GoogleGenerativeAI(apiKey);
    
    this.server = new Server({
      name: 'gemini-assistant',
      version: '1.0.0',
    }, {
      capabilities: {
        tools: true,
        prompts: true,
        resources: true,
      },
    });
    
    this.setupTools();
    this.setupPrompts();
    this.setupResources();
  }
  
  setupTools() {
    this.server.setRequestHandler('tools/list', async () => ({
      tools: [
        {
          name: 'multi_modal_analysis',
          description: 'Analyze multiple types of content together',
          inputSchema: {
            type: 'object',
            properties: {
              text: { type: 'string' },
              images: { type: 'array', items: { type: 'string' } },
              videos: { type: 'array', items: { type: 'string' } },
              audio: { type: 'array', items: { type: 'string' } },
              model: { type: 'string', enum: ['gemini-1.5-pro', 'gemini-1.5-flash'] },
            },
            required: ['text'],
          },
        },
        {
          name: 'code_generation',
          description: 'Generate and analyze code with Gemini',
          inputSchema: {
            type: 'object',
            properties: {
              instruction: { type: 'string' },
              language: { type: 'string' },
              context: { type: 'string' },
              examples: { type: 'array', items: { type: 'object' } },
            },
            required: ['instruction', 'language'],
          },
        },
        {
          name: 'long_context_processing',
          description: 'Process very long documents or conversations',
          inputSchema: {
            type: 'object',
            properties: {
              documents: { type: 'array', items: { type: 'string' } },
              query: { type: 'string' },
              maxTokens: { type: 'integer', maximum: 1048576 },
            },
            required: ['documents', 'query'],
          },
        },
        {
          name: 'safety_analysis',
          description: 'Analyze content for safety and appropriateness',
          inputSchema: {
            type: 'object',
            properties: {
              content: { type: 'string' },
              categories: { type: 'array', items: { type: 'string' } },
              threshold: { type: 'string', enum: ['BLOCK_NONE', 'BLOCK_LOW_AND_ABOVE', 'BLOCK_MEDIUM_AND_ABOVE', 'BLOCK_HIGH_AND_ABOVE'] },
            },
            required: ['content'],
          },
        },
      ],
    }));
    
    this.server.setRequestHandler('tools/call', async (request) => {
      const { name, arguments: args } = request.params;
      
      switch (name) {
        case 'multi_modal_analysis':
          return await this.multiModalAnalysis(args);
          
        case 'code_generation':
          return await this.generateCode(args);
          
        case 'long_context_processing':
          return await this.processLongContext(args);
          
        case 'safety_analysis':
          return await this.analyzeSafety(args);
          
        default:
          throw new Error(`Unknown tool: ${name}`);
      }
    });
  }
  
  setupPrompts() {
    this.server.setRequestHandler('prompts/list', async () => ({
      prompts: [
        {
          name: 'scientific_reasoning',
          description: 'Advanced scientific analysis and reasoning',
          arguments: [
            { name: 'hypothesis', type: 'string', required: true },
            { name: 'data', type: 'string', required: true },
            { name: 'methodology', type: 'string', required: false },
          ],
        },
        {
          name: 'creative_storytelling',
          description: 'Generate creative stories with complex narratives',
          arguments: [
            { name: 'genre', type: 'string', required: true },
            { name: 'characters', type: 'array', required: true },
            { name: 'setting', type: 'string', required: true },
            { name: 'plot_points', type: 'array', required: false },
          ],
        },
        {
          name: 'technical_documentation',
          description: 'Generate comprehensive technical documentation',
          arguments: [
            { name: 'project_name', type: 'string', required: true },
            { name: 'code_base', type: 'string', required: true },
            { name: 'target_audience', type: 'string', required: true },
          ],
        },
      ],
    }));
    
    this.server.setRequestHandler('prompts/get', async (request) => {
      const { name, arguments: args } = request.params;
      
      const prompts = {
        scientific_reasoning: `As a scientific researcher, analyze the following:

Hypothesis: ${args.hypothesis}

Data:
${args.data}

${args.methodology ? `Methodology: ${args.methodology}` : ''}

Please provide:
1. Analysis of the hypothesis validity
2. Interpretation of the data
3. Statistical significance (if applicable)
4. Potential confounding factors
5. Recommendations for further research`,

        creative_storytelling: `Create a ${args.genre} story with the following elements:

Characters: ${args.characters.join(', ')}
Setting: ${args.setting}
${args.plot_points ? `Plot points: ${args.plot_points.join(', ')}` : ''}

Write a compelling narrative that:
1. Develops each character
2. Creates tension and resolution
3. Uses vivid descriptions
4. Maintains genre conventions
5. Delivers a satisfying conclusion`,

        technical_documentation: `Generate technical documentation for:

Project: ${args.project_name}
Target Audience: ${args.target_audience}

Code Base:
${args.code_base}

Include:
1. Project overview
2. Installation instructions
3. API documentation
4. Usage examples
5. Configuration options
6. Troubleshooting guide
7. Best practices`,
      };
      
      return {
        messages: [
          {
            role: 'user',
            content: prompts[name] || 'Invalid prompt name',
          },
        ],
      };
    });
  }
  
  setupResources() {
    this.server.setRequestHandler('resources/list', async () => ({
      resources: [
        {
          uri: 'gemini://models',
          name: 'Available Gemini Models',
          description: 'List of available Gemini models and capabilities',
          mimeType: 'application/json',
        },
        {
          uri: 'gemini://safety-settings',
          name: 'Safety Settings',
          description: 'Current safety filter settings',
          mimeType: 'application/json',
        },
      ],
    }));
    
    this.server.setRequestHandler('resources/read', async (request) => {
      const { uri } = request.params;
      
      if (uri === 'gemini://models') {
        return {
          contents: [
            {
              uri,
              mimeType: 'application/json',
              text: JSON.stringify({
                models: [
                  {
                    name: 'gemini-1.5-pro',
                    inputTokenLimit: 1048576,
                    outputTokenLimit: 8192,
                    supportedMimeTypes: ['text/plain', 'image/jpeg', 'image/png', 'video/mp4', 'audio/wav'],
                  },
                  {
                    name: 'gemini-1.5-flash',
                    inputTokenLimit: 1048576,
                    outputTokenLimit: 8192,
                    supportedMimeTypes: ['text/plain', 'image/jpeg', 'image/png'],
                  },
                ],
              }),
            },
          ],
        };
      }
      
      if (uri === 'gemini://safety-settings') {
        return {
          contents: [
            {
              uri,
              mimeType: 'application/json',
              text: JSON.stringify({
                categories: [
                  'HARM_CATEGORY_HATE_SPEECH',
                  'HARM_CATEGORY_DANGEROUS_CONTENT',
                  'HARM_CATEGORY_HARASSMENT',
                  'HARM_CATEGORY_SEXUALLY_EXPLICIT',
                ],
                defaultThreshold: 'BLOCK_MEDIUM_AND_ABOVE',
              }),
            },
          ],
        };
      }
      
      throw new Error(`Unknown resource: ${uri}`);
    });
  }
  
  async multiModalAnalysis({ text, images, videos, audio, model }) {
    const parts = [{ text }];
    
    if (images) {
      for (const image of images) {
        const imageData = Buffer.from(image, 'base64');
        parts.push({
          inlineData: {
            data: image,
            mimeType: 'image/jpeg',
          },
        });
      }
    }
    
    if (videos) {
      for (const video of videos) {
        parts.push({
          inlineData: {
            data: video,
            mimeType: 'video/mp4',
          },
        });
      }
    }
    
    if (audio) {
      for (const audioFile of audio) {
        parts.push({
          inlineData: {
            data: audioFile,
            mimeType: 'audio/wav',
          },
        });
      }
    }
    
    const genModel = this.genAI.getGenerativeModel({ model: model || 'gemini-1.5-pro' });
    const result = await genModel.generateContent({
      contents: [{ role: 'user', parts }],
    });
    
    return {
      content: [
        {
          type: 'text',
          text: result.response.text(),
        },
      ],
    };
  }
  
  async generateCode({ instruction, language, context, examples }) {
    const prompt = `Generate ${language} code for the following:

Instruction: ${instruction}

${context ? `Context:\n${context}\n` : ''}

${examples ? `Examples:\n${examples.map(e => `Input: ${e.input}\nOutput: ${e.output}`).join('\n\n')}\n` : ''}

Requirements:
1. Follow best practices for ${language}
2. Include error handling
3. Add comprehensive comments
4. Ensure type safety (if applicable)
5. Optimize for performance and readability`;
    
    const model = this.genAI.getGenerativeModel({ model: 'gemini-1.5-pro' });
    const result = await model.generateContent(prompt);
    
    return {
      content: [
        {
          type: 'text',
          text: result.response.text(),
        },
      ],
    };
  }
  
  async processLongContext({ documents, query, maxTokens }) {
    const context = documents.join('\n\n---\n\n');
    
    const prompt = `Given the following documents:

${context}

Answer the following query:
${query}

Provide a comprehensive answer based on all the provided documents.`;
    
    const model = this.genAI.getGenerativeModel({ 
      model: 'gemini-1.5-pro',
      generationConfig: {
        maxOutputTokens: maxTokens || 8192,
      },
    });
    
    const result = await model.generateContent(prompt);
    
    return {
      content: [
        {
          type: 'text',
          text: result.response.text(),
        },
      ],
    };
  }
  
  async analyzeSafety({ content, categories, threshold }) {
    const safetySettings = categories ? categories.map(category => ({
      category,
      threshold: threshold || 'BLOCK_MEDIUM_AND_ABOVE',
    })) : undefined;
    
    const model = this.genAI.getGenerativeModel({ 
      model: 'gemini-1.5-pro',
      safetySettings,
    });
    
    try {
      const result = await model.generateContent(content);
      const safetyRatings = result.response.candidates[0].safetyRatings;
      
      return {
        content: [
          {
            type: 'safety_analysis',
            data: {
              text: result.response.text(),
              safetyRatings: safetyRatings,
              blocked: result.response.candidates[0].finishReason === 'SAFETY',
            },
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: 'safety_analysis',
            data: {
              error: error.message,
              blocked: true,
              safetyRatings: [],
            },
          },
        ],
      };
    }
  }
  
  async start() {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('Gemini MCP Server started');
  }
}

// Start server
const apiKey = process.env.GOOGLE_AI_API_KEY;
if (!apiKey) {
  console.error('GOOGLE_AI_API_KEY environment variable is required');
  process.exit(1);
}

const server = new GeminiMCPServer(apiKey);
server.start().catch(console.error);
```

## Flutter Integration

### Gemini-Powered MCP Client

```dart
// lib/gemini_mcp_client.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:io';
import 'dart:convert';

class GeminiMCPClient extends StatefulWidget {
  const GeminiMCPClient({Key? key}) : super(key: key);

  @override
  State<GeminiMCPClient> createState() => _GeminiMCPClientState();
}

class _GeminiMCPClientState extends State<GeminiMCPClient> {
  final _mcp = FlutterMCP();
  final _textController = TextEditingController();
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  List<File> _selectedFiles = [];
  
  @override
  void initState() {
    super.initState();
    _initializeMCP();
  }
  
  Future<void> _initializeMCP() async {
    await _mcp.initialize(
      config: McpConfig(
        servers: [
          ServerConfig(
            id: 'gemini-server',
            command: 'node',
            args: ['gemini-mcp-server.js'],
            env: {
              'GOOGLE_AI_API_KEY': 'your-api-key',
            },
          ),
        ],
      ),
    );
  }
  
  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedFiles.isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _messages.add(ChatMessage(
        text: text,
        files: List.from(_selectedFiles),
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _textController.clear();
    });
    
    try {
      // Prepare multi-modal content
      final images = <String>[];
      final videos = <String>[];
      final audio = <String>[];
      
      for (final file in _selectedFiles) {
        final bytes = await file.readAsBytes();
        final base64 = base64Encode(bytes);
        
        if (file.path.endsWith('.jpg') || file.path.endsWith('.png')) {
          images.add(base64);
        } else if (file.path.endsWith('.mp4')) {
          videos.add(base64);
        } else if (file.path.endsWith('.wav') || file.path.endsWith('.mp3')) {
          audio.add(base64);
        }
      }
      
      final result = await _mcp.client.callTool(
        serverId: 'gemini-server',
        name: 'multi_modal_analysis',
        arguments: {
          'text': text,
          if (images.isNotEmpty) 'images': images,
          if (videos.isNotEmpty) 'videos': videos,
          if (audio.isNotEmpty) 'audio': audio,
          'model': 'gemini-1.5-pro',
        },
      );
      
      setState(() {
        _messages.add(ChatMessage(
          text: result.content.first.text,
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _selectedFiles.clear();
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: 'Error: $e',
          isUser: false,
          timestamp: DateTime.now(),
          isError: true,
        ));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _selectFile() async {
    // Implementation for file selection
    // Uses image_picker or file_picker package
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini MCP Integration'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[_messages.length - 1 - index];
                return MessageBubble(message: message);
              },
            ),
          ),
          if (_selectedFiles.isNotEmpty)
            Container(
              height: 80,
              padding: const EdgeInsets.all(8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedFiles.length,
                itemBuilder: (context, index) {
                  return FilePreview(
                    file: _selectedFiles[index],
                    onRemove: () {
                      setState(() {
                        _selectedFiles.removeAt(index);
                      });
                    },
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _selectFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: _isLoading ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _textController.dispose();
    _mcp.dispose();
    super.dispose();
  }
}

class ChatMessage {
  final String text;
  final List<File> files;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  
  ChatMessage({
    required this.text,
    this.files = const [],
    required this.isUser,
    required this.timestamp,
    this.isError = false,
  });
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  
  const MessageBubble({Key? key, required this.message}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.isError
              ? Colors.red.shade100
              : message.isUser
                  ? Colors.blue.shade100
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.files.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: message.files.map((file) {
                  return FilePreview(file: file, small: true);
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
            Text(message.text),
          ],
        ),
      ),
    );
  }
}

class FilePreview extends StatelessWidget {
  final File file;
  final VoidCallback? onRemove;
  final bool small;
  
  const FilePreview({
    Key? key,
    required this.file,
    this.onRemove,
    this.small = false,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final isImage = file.path.endsWith('.jpg') || file.path.endsWith('.png');
    final isVideo = file.path.endsWith('.mp4');
    final isAudio = file.path.endsWith('.wav') || file.path.endsWith('.mp3');
    
    Widget preview;
    if (isImage) {
      preview = Image.file(
        file,
        fit: BoxFit.cover,
        width: small ? 40 : 60,
        height: small ? 40 : 60,
      );
    } else {
      IconData icon;
      if (isVideo) {
        icon = Icons.videocam;
      } else if (isAudio) {
        icon = Icons.audiotrack;
      } else {
        icon = Icons.insert_drive_file;
      }
      
      preview = Container(
        width: small ? 40 : 60,
        height: small ? 40 : 60,
        color: Colors.grey.shade200,
        child: Icon(icon, size: small ? 20 : 30),
      );
    }
    
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: preview,
        ),
        if (onRemove != null && !small)
          Positioned(
            top: -8,
            right: -8,
            child: IconButton(
              icon: const Icon(Icons.cancel, size: 20),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
      ],
    );
  }
}
```

### Advanced Gemini Features

```dart
// lib/gemini_advanced_features.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:io';
import 'dart:convert';

class GeminiAdvancedFeatures {
  final FlutterMCP mcp;
  
  GeminiAdvancedFeatures({required this.mcp});
  
  // Long document processing
  Future<String> processLongDocuments({
    required List<String> documents,
    required String query,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'gemini-server',
      name: 'long_context_processing',
      arguments: {
        'documents': documents,
        'query': query,
        'maxTokens': 8192,
      },
    );
    
    return result.content.first.text;
  }
  
  // Code generation with context
  Future<GeneratedCode> generateCodeWithContext({
    required String instruction,
    required String language,
    required String existingCode,
    List<CodeExample>? examples,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'gemini-server',
      name: 'code_generation',
      arguments: {
        'instruction': instruction,
        'language': language,
        'context': existingCode,
        if (examples != null) 'examples': examples.map((e) => e.toJson()).toList(),
      },
    );
    
    final code = result.content.first.text;
    
    // Parse the generated code
    return GeneratedCode.parse(code, language);
  }
  
  // Safety analysis
  Future<SafetyAnalysis> analyzeSafety(String content) async {
    final result = await mcp.client.callTool(
      serverId: 'gemini-server',
      name: 'safety_analysis',
      arguments: {
        'content': content,
        'categories': [
          'HARM_CATEGORY_HATE_SPEECH',
          'HARM_CATEGORY_DANGEROUS_CONTENT',
          'HARM_CATEGORY_HARASSMENT',
          'HARM_CATEGORY_SEXUALLY_EXPLICIT',
        ],
        'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
      },
    );
    
    final data = result.content.first.data as Map<String, dynamic>;
    return SafetyAnalysis.fromJson(data);
  }
  
  // Scientific reasoning
  Future<ScientificAnalysis> performScientificAnalysis({
    required String hypothesis,
    required String data,
    String? methodology,
  }) async {
    final prompt = await mcp.client.getPrompt(
      serverId: 'gemini-server',
      name: 'scientific_reasoning',
      arguments: {
        'hypothesis': hypothesis,
        'data': data,
        if (methodology != null) 'methodology': methodology,
      },
    );
    
    final result = await mcp.client.callTool(
      serverId: 'gemini-server',
      name: 'multi_modal_analysis',
      arguments: {
        'text': prompt.messages.first.content,
        'model': 'gemini-1.5-pro',
      },
    );
    
    return ScientificAnalysis.parse(result.content.first.text);
  }
  
  // Creative content generation
  Future<CreativeContent> generateCreativeContent({
    required String genre,
    required List<String> characters,
    required String setting,
    List<String>? plotPoints,
  }) async {
    final prompt = await mcp.client.getPrompt(
      serverId: 'gemini-server',
      name: 'creative_storytelling',
      arguments: {
        'genre': genre,
        'characters': characters,
        'setting': setting,
        if (plotPoints != null) 'plot_points': plotPoints,
      },
    );
    
    final result = await mcp.client.callTool(
      serverId: 'gemini-server',
      name: 'multi_modal_analysis',
      arguments: {
        'text': prompt.messages.first.content,
        'model': 'gemini-1.5-pro',
      },
    );
    
    return CreativeContent(
      story: result.content.first.text,
      genre: genre,
      characters: characters,
    );
  }
}

class GeneratedCode {
  final String code;
  final String language;
  final List<String> imports;
  final List<CodeFunction> functions;
  final List<CodeClass> classes;
  
  GeneratedCode({
    required this.code,
    required this.language,
    required this.imports,
    required this.functions,
    required this.classes,
  });
  
  static GeneratedCode parse(String code, String language) {
    // Parse the generated code to extract structure
    // This is a simplified example
    return GeneratedCode(
      code: code,
      language: language,
      imports: _extractImports(code, language),
      functions: _extractFunctions(code, language),
      classes: _extractClasses(code, language),
    );
  }
  
  static List<String> _extractImports(String code, String language) {
    // Language-specific import extraction
    return [];
  }
  
  static List<CodeFunction> _extractFunctions(String code, String language) {
    // Language-specific function extraction
    return [];
  }
  
  static List<CodeClass> _extractClasses(String code, String language) {
    // Language-specific class extraction
    return [];
  }
}

class CodeExample {
  final String input;
  final String output;
  final String? description;
  
  CodeExample({
    required this.input,
    required this.output,
    this.description,
  });
  
  Map<String, dynamic> toJson() => {
    'input': input,
    'output': output,
    if (description != null) 'description': description,
  };
}

class CodeFunction {
  final String name;
  final String returnType;
  final List<String> parameters;
  final String body;
  
  CodeFunction({
    required this.name,
    required this.returnType,
    required this.parameters,
    required this.body,
  });
}

class CodeClass {
  final String name;
  final List<String> fields;
  final List<CodeFunction> methods;
  
  CodeClass({
    required this.name,
    required this.fields,
    required this.methods,
  });
}

class SafetyAnalysis {
  final String? text;
  final bool blocked;
  final List<SafetyRating> ratings;
  final String? error;
  
  SafetyAnalysis({
    this.text,
    required this.blocked,
    required this.ratings,
    this.error,
  });
  
  factory SafetyAnalysis.fromJson(Map<String, dynamic> json) {
    return SafetyAnalysis(
      text: json['text'],
      blocked: json['blocked'],
      ratings: (json['safetyRatings'] as List)
          .map((r) => SafetyRating.fromJson(r))
          .toList(),
      error: json['error'],
    );
  }
}

class SafetyRating {
  final String category;
  final String probability;
  
  SafetyRating({
    required this.category,
    required this.probability,
  });
  
  factory SafetyRating.fromJson(Map<String, dynamic> json) {
    return SafetyRating(
      category: json['category'],
      probability: json['probability'],
    );
  }
}

class ScientificAnalysis {
  final String hypothesis;
  final String dataInterpretation;
  final String statisticalSignificance;
  final List<String> confoundingFactors;
  final List<String> recommendations;
  
  ScientificAnalysis({
    required this.hypothesis,
    required this.dataInterpretation,
    required this.statisticalSignificance,
    required this.confoundingFactors,
    required this.recommendations,
  });
  
  static ScientificAnalysis parse(String analysis) {
    // Parse the analysis text to extract structured information
    // This is a simplified example
    return ScientificAnalysis(
      hypothesis: '',
      dataInterpretation: '',
      statisticalSignificance: '',
      confoundingFactors: [],
      recommendations: [],
    );
  }
}

class CreativeContent {
  final String story;
  final String genre;
  final List<String> characters;
  
  CreativeContent({
    required this.story,
    required this.genre,
    required this.characters,
  });
}
```

### Gemini-Powered UI Components

```dart
// lib/widgets/gemini_chat_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiChatWidget extends StatefulWidget {
  final FlutterMCP mcp;
  final String serverId;
  
  const GeminiChatWidget({
    Key? key,
    required this.mcp,
    required this.serverId,
  }) : super(key: key);

  @override
  State<GeminiChatWidget> createState() => _GeminiChatWidgetState();
}

class _GeminiChatWidgetState extends State<GeminiChatWidget> {
  final _controller = TextEditingController();
  final _messages = <GeminiMessage>[];
  final _scrollController = ScrollController();
  bool _isTyping = false;
  
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    setState(() {
      _messages.add(GeminiMessage(
        text: text,
        role: 'user',
        timestamp: DateTime.now(),
      ));
      _controller.clear();
      _isTyping = true;
    });
    
    _scrollToBottom();
    
    try {
      // Stream the response
      final stream = widget.mcp.client.streamTool(
        serverId: widget.serverId,
        name: 'multi_modal_analysis',
        arguments: {
          'text': text,
          'model': 'gemini-1.5-flash', // Faster model for chat
        },
      );
      
      String response = '';
      setState(() {
        _messages.add(GeminiMessage(
          text: '',
          role: 'model',
          timestamp: DateTime.now(),
        ));
      });
      
      await for (final chunk in stream) {
        response += chunk.content.first.text;
        setState(() {
          _messages.last = GeminiMessage(
            text: response,
            role: 'model',
            timestamp: _messages.last.timestamp,
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _messages.add(GeminiMessage(
          text: 'Error: $e',
          role: 'error',
          timestamp: DateTime.now(),
        ));
      });
    } finally {
      setState(() {
        _isTyping = false;
      });
    }
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _messages.length + (_isTyping ? 1 : 0),
            itemBuilder: (context, index) {
              if (_isTyping && index == _messages.length) {
                return const TypingIndicator();
              }
              
              final message = _messages[index];
              return GeminiMessageBubble(message: message);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Ask Gemini...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class GeminiMessage {
  final String text;
  final String role;
  final DateTime timestamp;
  
  GeminiMessage({
    required this.text,
    required this.role,
    required this.timestamp,
  });
}

class GeminiMessageBubble extends StatelessWidget {
  final GeminiMessage message;
  
  const GeminiMessageBubble({Key? key, required this.message}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isError = message.role == 'error';
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError
              ? Colors.red.shade100
              : isUser
                  ? Theme.of(context).primaryColor.withOpacity(0.1)
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: isError
              ? Border.all(color: Colors.red)
              : null,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message.text,
              style: TextStyle(
                color: isError ? Colors.red.shade900 : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}';
  }
}

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({Key? key}) : super(key: key);

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final delay = index * 0.15;
                final value = (_controller.value - delay).clamp(0.0, 1.0);
                final opacity = (value < 0.5 ? value * 2 : (1 - value) * 2);
                
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(opacity),
                    shape: BoxShape.circle,
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}
```

### Document Analysis Widget

```dart
// lib/widgets/document_analysis_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class DocumentAnalysisWidget extends StatefulWidget {
  final FlutterMCP mcp;
  
  const DocumentAnalysisWidget({Key? key, required this.mcp}) : super(key: key);

  @override
  State<DocumentAnalysisWidget> createState() => _DocumentAnalysisWidgetState();
}

class _DocumentAnalysisWidgetState extends State<DocumentAnalysisWidget> {
  final _documents = <DocumentInfo>[];
  final _queryController = TextEditingController();
  String _analysisResult = '';
  bool _isLoading = false;
  bool _isAnalyzing = false;
  
  Future<void> _addDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'pdf', 'docx', 'md'],
      allowMultiple: true,
    );
    
    if (result != null) {
      setState(() {
        _isLoading = true;
      });
      
      for (final file in result.files) {
        if (file.path != null) {
          final content = await File(file.path!).readAsString();
          setState(() {
            _documents.add(DocumentInfo(
              name: file.name,
              content: content,
              size: file.size,
            ));
          });
        }
      }
      
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _analyzeDocuments() async {
    if (_documents.isEmpty || _queryController.text.trim().isEmpty) return;
    
    setState(() {
      _isAnalyzing = true;
      _analysisResult = '';
    });
    
    try {
      final advanced = GeminiAdvancedFeatures(mcp: widget.mcp);
      final result = await advanced.processLongDocuments(
        documents: _documents.map((d) => d.content).toList(),
        query: _queryController.text,
      );
      
      setState(() {
        _analysisResult = result;
      });
    } catch (e) {
      setState(() {
        _analysisResult = 'Error: $e';
      });
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Documents',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                      onPressed: _isLoading ? null : _addDocument,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_documents.isEmpty)
                  const Text(
                    'No documents added',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...(_documents.map((doc) => ListTile(
                    leading: const Icon(Icons.description),
                    title: Text(doc.name),
                    subtitle: Text(_formatFileSize(doc.size)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        setState(() {
                          _documents.remove(doc);
                        });
                      },
                    ),
                  ))),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _queryController,
            decoration: const InputDecoration(
              labelText: 'Query',
              hintText: 'What would you like to know about these documents?',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _documents.isEmpty || _isAnalyzing
                  ? null
                  : _analyzeDocuments,
              child: _isAnalyzing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Analyze Documents'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: SelectableText(
                  _analysisResult.isEmpty
                      ? 'Analysis results will appear here'
                      : _analysisResult,
                  style: TextStyle(
                    color: _analysisResult.isEmpty ? Colors.grey : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  String _formatFileSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    int unitIndex = 0;
    double size = bytes.toDouble();
    
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }
  
  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }
}

class DocumentInfo {
  final String name;
  final String content;
  final int size;
  
  DocumentInfo({
    required this.name,
    required this.content,
    required this.size,
  });
}
```

## Configuration

### Environment Variables

```dart
// lib/config/gemini_config.dart
class GeminiConfig {
  static const String apiKey = String.fromEnvironment(
    'GOOGLE_AI_API_KEY',
    defaultValue: '',
  );
  
  static const String defaultModel = String.fromEnvironment(
    'GEMINI_DEFAULT_MODEL',
    defaultValue: 'gemini-1.5-pro',
  );
  
  static const double defaultTemperature = double.fromEnvironment(
    'GEMINI_TEMPERATURE',
    defaultValue: 0.9,
  );
  
  static const int maxOutputTokens = int.fromEnvironment(
    'GEMINI_MAX_OUTPUT_TOKENS',
    defaultValue: 8192,
  );
  
  static const int contextWindow = int.fromEnvironment(
    'GEMINI_CONTEXT_WINDOW',
    defaultValue: 1048576,
  );
}
```

### Safety Settings

```dart
// lib/config/safety_settings.dart
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiSafetySettings {
  static const defaultSettings = [
    SafetySetting(HarmCategory.harassment, HarmBlockThreshold.mediumAndAbove),
    SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.mediumAndAbove),
    SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.mediumAndAbove),
    SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.mediumAndAbove),
  ];
  
  static List<SafetySetting> forFamily = [
    SafetySetting(HarmCategory.harassment, HarmBlockThreshold.lowAndAbove),
    SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.lowAndAbove),
    SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.lowAndAbove),
    SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.lowAndAbove),
  ];
  
  static List<SafetySetting> unrestricted = [
    SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
    SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
    SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.none),
    SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
  ];
}
```

## Best Practices

### 1. Context Window Management

```dart
// lib/utils/context_window_manager.dart
class ContextWindowManager {
  static const int maxContextTokens = 1048576; // 1M tokens
  final List<ContextChunk> _chunks = [];
  
  void addContent(String content, {required String identifier}) {
    final tokens = _estimateTokens(content);
    _chunks.add(ContextChunk(
      identifier: identifier,
      content: content,
      tokenCount: tokens,
      timestamp: DateTime.now(),
    ));
    
    _trimToFitWindow();
  }
  
  void _trimToFitWindow() {
    int totalTokens = _chunks.fold(0, (sum, chunk) => sum + chunk.tokenCount);
    
    while (totalTokens > maxContextTokens && _chunks.isNotEmpty) {
      // Remove oldest chunks first
      final removed = _chunks.removeAt(0);
      totalTokens -= removed.tokenCount;
    }
  }
  
  String getFullContext() {
    return _chunks.map((c) => c.content).join('\n\n');
  }
  
  int _estimateTokens(String text) {
    // Rough estimation: 1 token per 4 characters
    return (text.length / 4).ceil();
  }
}

class ContextChunk {
  final String identifier;
  final String content;
  final int tokenCount;
  final DateTime timestamp;
  
  ContextChunk({
    required this.identifier,
    required this.content,
    required this.tokenCount,
    required this.timestamp,
  });
}
```

### 2. Multi-Modal Caching

```dart
// lib/utils/multi_modal_cache.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class MultiModalCache {
  final Map<String, CachedContent> _cache = {};
  final Duration ttl;
  final int maxSizeBytes;
  int _currentSizeBytes = 0;
  
  MultiModalCache({
    this.ttl = const Duration(hours: 1),
    this.maxSizeBytes = 100 * 1024 * 1024, // 100MB
  });
  
  String _generateKey(String type, dynamic content) {
    String contentString;
    if (content is String) {
      contentString = content;
    } else if (content is Uint8List) {
      contentString = base64Encode(content);
    } else {
      contentString = content.toString();
    }
    
    final input = '$type:$contentString';
    return md5.convert(utf8.encode(input)).toString();
  }
  
  Future<T?> get<T>({
    required String type,
    required dynamic content,
  }) async {
    final key = _generateKey(type, content);
    final cached = _cache[key];
    
    if (cached != null && !cached.isExpired) {
      cached.lastAccessed = DateTime.now();
      return cached.data as T;
    }
    
    return null;
  }
  
  Future<void> set<T>({
    required String type,
    required dynamic content,
    required T data,
  }) async {
    final key = _generateKey(type, content);
    final size = _estimateSize(data);
    
    // Evict old entries if needed
    while (_currentSizeBytes + size > maxSizeBytes && _cache.isNotEmpty) {
      _evictOldest();
    }
    
    _cache[key] = CachedContent(
      data: data,
      sizeBytes: size,
      created: DateTime.now(),
      lastAccessed: DateTime.now(),
      ttl: ttl,
    );
    
    _currentSizeBytes += size;
  }
  
  void _evictOldest() {
    String? oldestKey;
    DateTime? oldestAccess;
    
    for (final entry in _cache.entries) {
      if (oldestAccess == null || entry.value.lastAccessed.isBefore(oldestAccess)) {
        oldestAccess = entry.value.lastAccessed;
        oldestKey = entry.key;
      }
    }
    
    if (oldestKey != null) {
      final removed = _cache.remove(oldestKey);
      if (removed != null) {
        _currentSizeBytes -= removed.sizeBytes;
      }
    }
  }
  
  int _estimateSize(dynamic data) {
    if (data is String) {
      return data.length * 2; // UTF-16 encoding
    } else if (data is Uint8List) {
      return data.length;
    } else if (data is Map || data is List) {
      return jsonEncode(data).length * 2;
    }
    return 1000; // Default estimate
  }
}

class CachedContent {
  final dynamic data;
  final int sizeBytes;
  final DateTime created;
  DateTime lastAccessed;
  final Duration ttl;
  
  CachedContent({
    required this.data,
    required this.sizeBytes,
    required this.created,
    required this.lastAccessed,
    required this.ttl,
  });
  
  bool get isExpired => DateTime.now().difference(created) > ttl;
}
```

### 3. Error Recovery

```dart
// lib/utils/gemini_error_handler.dart
class GeminiErrorHandler {
  static Future<T> handleWithRetry<T>({
    required Future<T> Function() operation,
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;
    
    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        
        if (e is GenerativeAIException) {
          // Handle specific Gemini errors
          if (e.message.contains('quota exceeded')) {
            throw QuotaExceededException(e.message);
          } else if (e.message.contains('invalid request')) {
            throw InvalidRequestException(e.message);
          } else if (e.message.contains('safety')) {
            throw SafetyBlockedException(e.message);
          }
        }
        
        if (attempt >= maxRetries) {
          rethrow;
        }
        
        await Future.delayed(delay);
        delay *= 2; // Exponential backoff
      }
    }
    
    throw Exception('Failed after $maxRetries attempts');
  }
  
  static String getUserFriendlyError(dynamic error) {
    if (error is QuotaExceededException) {
      return 'API quota exceeded. Please try again later.';
    } else if (error is InvalidRequestException) {
      return 'Invalid request. Please check your input.';
    } else if (error is SafetyBlockedException) {
      return 'Content blocked by safety filters.';
    } else if (error is GenerativeAIException) {
      return 'AI service error: ${error.message}';
    }
    
    return 'An unexpected error occurred.';
  }
}

class QuotaExceededException implements Exception {
  final String message;
  QuotaExceededException(this.message);
}

class InvalidRequestException implements Exception {
  final String message;
  InvalidRequestException(this.message);
}

class SafetyBlockedException implements Exception {
  final String message;
  SafetyBlockedException(this.message);
}
```

## Advanced Use Cases

### 1. Research Assistant

```dart
// lib/features/research_assistant.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class ResearchAssistant {
  final FlutterMCP mcp;
  final GeminiAdvancedFeatures advanced;
  
  ResearchAssistant({required this.mcp})
      : advanced = GeminiAdvancedFeatures(mcp: mcp);
  
  Future<ResearchReport> conductResearch({
    required String topic,
    required List<String> sources,
    List<String>? specificQuestions,
  }) async {
    // Step 1: Analyze all sources
    final sourceAnalyses = <SourceAnalysis>[];
    
    for (final source in sources) {
      final analysis = await advanced.processLongDocuments(
        documents: [source],
        query: 'Summarize key points related to $topic',
      );
      
      sourceAnalyses.add(SourceAnalysis(
        source: source,
        summary: analysis,
        relevantQuotes: await _extractQuotes(source, topic),
      ));
    }
    
    // Step 2: Answer specific questions
    final answers = <String, String>{};
    
    if (specificQuestions != null) {
      for (final question in specificQuestions) {
        final answer = await advanced.processLongDocuments(
          documents: sources,
          query: question,
        );
        answers[question] = answer;
      }
    }
    
    // Step 3: Generate comprehensive report
    final report = await _generateReport(
      topic: topic,
      analyses: sourceAnalyses,
      questionAnswers: answers,
    );
    
    // Step 4: Generate citations
    final citations = _generateCitations(sourceAnalyses);
    
    return ResearchReport(
      topic: topic,
      executive_summary: report.summary,
      detailed_findings: report.findings,
      question_answers: answers,
      citations: citations,
      generated_at: DateTime.now(),
    );
  }
  
  Future<List<String>> _extractQuotes(String source, String topic) async {
    final result = await mcp.client.callTool(
      serverId: 'gemini-server',
      name: 'multi_modal_analysis',
      arguments: {
        'text': 'Extract relevant quotes about $topic from:\n\n$source',
        'model': 'gemini-1.5-pro',
      },
    );
    
    // Parse quotes from response
    final text = result.content.first.text;
    return text.split('\n').where((line) => line.trim().isNotEmpty).toList();
  }
  
  Future<ReportContent> _generateReport({
    required String topic,
    required List<SourceAnalysis> analyses,
    required Map<String, String> questionAnswers,
  }) async {
    final prompt = '''Generate a comprehensive research report on "$topic".

Source Summaries:
${analyses.map((a) => a.summary).join('\n\n')}

Specific Findings:
${questionAnswers.entries.map((e) => 'Q: ${e.key}\nA: ${e.value}').join('\n\n')}

Please provide:
1. Executive summary (2-3 paragraphs)
2. Detailed findings organized by theme
3. Key insights and conclusions
4. Recommendations for further research''';
    
    final result = await mcp.client.callTool(
      serverId: 'gemini-server',
      name: 'multi_modal_analysis',
      arguments: {
        'text': prompt,
        'model': 'gemini-1.5-pro',
      },
    );
    
    // Parse the structured report
    return ReportContent.parse(result.content.first.text);
  }
  
  List<Citation> _generateCitations(List<SourceAnalysis> analyses) {
    return analyses.map((analysis) {
      // Extract metadata from source
      return Citation(
        source: analysis.source,
        quotes: analysis.relevantQuotes,
        accessed: DateTime.now(),
      );
    }).toList();
  }
}

class ResearchReport {
  final String topic;
  final String executive_summary;
  final List<Finding> detailed_findings;
  final Map<String, String> question_answers;
  final List<Citation> citations;
  final DateTime generated_at;
  
  ResearchReport({
    required this.topic,
    required this.executive_summary,
    required this.detailed_findings,
    required this.question_answers,
    required this.citations,
    required this.generated_at,
  });
}

class SourceAnalysis {
  final String source;
  final String summary;
  final List<String> relevantQuotes;
  
  SourceAnalysis({
    required this.source,
    required this.summary,
    required this.relevantQuotes,
  });
}

class ReportContent {
  final String summary;
  final List<Finding> findings;
  
  ReportContent({required this.summary, required this.findings});
  
  static ReportContent parse(String text) {
    // Parse the generated report into structured format
    return ReportContent(
      summary: '',
      findings: [],
    );
  }
}

class Finding {
  final String theme;
  final String content;
  final List<String> supporting_evidence;
  
  Finding({
    required this.theme,
    required this.content,
    required this.supporting_evidence,
  });
}

class Citation {
  final String source;
  final List<String> quotes;
  final DateTime accessed;
  
  Citation({
    required this.source,
    required this.quotes,
    required this.accessed,
  });
}
```

### 2. Code Migration Tool

```dart
// lib/features/code_migration_tool.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class CodeMigrationTool {
  final FlutterMCP mcp;
  final GeminiAdvancedFeatures advanced;
  
  CodeMigrationTool({required this.mcp})
      : advanced = GeminiAdvancedFeatures(mcp: mcp);
  
  Future<MigrationResult> migrateCode({
    required String sourceCode,
    required String fromFramework,
    required String toFramework,
    Map<String, String>? mappings,
  }) async {
    // Step 1: Analyze source code structure
    final analysis = await _analyzeSourceCode(
      code: sourceCode,
      framework: fromFramework,
    );
    
    // Step 2: Generate migration plan
    final plan = await _generateMigrationPlan(
      analysis: analysis,
      targetFramework: toFramework,
      customMappings: mappings,
    );
    
    // Step 3: Execute migration
    final migratedCode = await _executeMigration(
      sourceCode: sourceCode,
      plan: plan,
    );
    
    // Step 4: Validate migrated code
    final validation = await _validateMigration(
      code: migratedCode,
      framework: toFramework,
    );
    
    // Step 5: Generate migration report
    final report = await _generateMigrationReport(
      original: sourceCode,
      migrated: migratedCode,
      validation: validation,
    );
    
    return MigrationResult(
      originalCode: sourceCode,
      migratedCode: migratedCode,
      isValid: validation.isValid,
      issues: validation.issues,
      report: report,
    );
  }
  
  Future<CodeAnalysis> _analyzeSourceCode({
    required String code,
    required String framework,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'gemini-server',
      name: 'code_generation',
      arguments: {
        'instruction': 'Analyze this $framework code and identify components, patterns, and dependencies',
        'language': _getLanguageFromFramework(framework),
        'context': code,
      },
    );
    
    return CodeAnalysis.parse(result.content.first.text);
  }
  
  Future<MigrationPlan> _generateMigrationPlan({
    required CodeAnalysis analysis,
    required String targetFramework,
    Map<String, String>? customMappings,
  }) async {
    final prompt = '''Create a migration plan from ${analysis.framework} to $targetFramework.

Components to migrate:
${analysis.components.map((c) => '- ${c.name}: ${c.type}').join('\n')}

Dependencies:
${analysis.dependencies.join(', ')}

${customMappings != null ? 'Custom mappings:\n${customMappings.entries.map((e) => '${e.key} -> ${e.value}').join('\n')}' : ''}

Provide:
1. Component mappings
2. API transformations
3. Pattern conversions
4. Dependency replacements''';
    
    final result = await mcp.client.callTool(
      serverId: 'gemini-server',
      name: 'multi_modal_analysis',
      arguments: {
        'text': prompt,
        'model': 'gemini-1.5-pro',
      },
    );
    
    return MigrationPlan.parse(result.content.first.text);
  }
  
  Future<String> _executeMigration({
    required String sourceCode,
    required MigrationPlan plan,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'gemini-server',
      name: 'code_generation',
      arguments: {
        'instruction': 'Apply this migration plan to transform the code',
        'language': plan.targetLanguage,
        'context': sourceCode,
        'examples': plan.transformations.map((t) => {
          'input': t.from,
          'output': t.to,
        }).toList(),
      },
    );
    
    return result.content.first.text;
  }
  
  Future<ValidationResult> _validateMigration({
    required String code,
    required String framework,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'gemini-server',
      name: 'code_generation',
      arguments: {
        'instruction': 'Validate this $framework code for syntax errors, best practices, and completeness',
        'language': _getLanguageFromFramework(framework),
        'context': code,
      },
    );
    
    return ValidationResult.parse(result.content.first.text);
  }
  
  Future<String> _generateMigrationReport({
    required String original,
    required String migrated,
    required ValidationResult validation,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'gemini-server',
      name: 'multi_modal_analysis',
      arguments: {
        'text': '''Generate a migration report comparing:

Original code:
$original

Migrated code:
$migrated

Validation results:
${validation.toString()}

Include:
1. Summary of changes
2. Key transformations
3. Potential issues
4. Recommendations''',
        'model': 'gemini-1.5-pro',
      },
    );
    
    return result.content.first.text;
  }
  
  String _getLanguageFromFramework(String framework) {
    final languageMap = {
      'flutter': 'dart',
      'react': 'javascript',
      'react-native': 'javascript',
      'angular': 'typescript',
      'vue': 'javascript',
      'svelte': 'javascript',
      'django': 'python',
      'rails': 'ruby',
      'spring': 'java',
      'express': 'javascript',
    };
    
    return languageMap[framework.toLowerCase()] ?? 'unknown';
  }
}

class MigrationResult {
  final String originalCode;
  final String migratedCode;
  final bool isValid;
  final List<ValidationIssue> issues;
  final String report;
  
  MigrationResult({
    required this.originalCode,
    required this.migratedCode,
    required this.isValid,
    required this.issues,
    required this.report,
  });
}

class CodeAnalysis {
  final String framework;
  final List<Component> components;
  final List<String> dependencies;
  final Map<String, String> patterns;
  
  CodeAnalysis({
    required this.framework,
    required this.components,
    required this.dependencies,
    required this.patterns,
  });
  
  static CodeAnalysis parse(String text) {
    // Parse analysis results
    return CodeAnalysis(
      framework: '',
      components: [],
      dependencies: [],
      patterns: {},
    );
  }
}

class Component {
  final String name;
  final String type;
  final Map<String, dynamic> properties;
  
  Component({
    required this.name,
    required this.type,
    required this.properties,
  });
}

class MigrationPlan {
  final String targetLanguage;
  final List<Transformation> transformations;
  final Map<String, String> dependencyMap;
  
  MigrationPlan({
    required this.targetLanguage,
    required this.transformations,
    required this.dependencyMap,
  });
  
  static MigrationPlan parse(String text) {
    // Parse migration plan
    return MigrationPlan(
      targetLanguage: '',
      transformations: [],
      dependencyMap: {},
    );
  }
}

class Transformation {
  final String from;
  final String to;
  final String description;
  
  Transformation({
    required this.from,
    required this.to,
    required this.description,
  });
}

class ValidationResult {
  final bool isValid;
  final List<ValidationIssue> issues;
  
  ValidationResult({
    required this.isValid,
    required this.issues,
  });
  
  static ValidationResult parse(String text) {
    // Parse validation results
    return ValidationResult(
      isValid: true,
      issues: [],
    );
  }
  
  @override
  String toString() {
    return 'Valid: $isValid\nIssues: ${issues.map((i) => i.toString()).join('\n')}';
  }
}

class ValidationIssue {
  final String severity;
  final String message;
  final int? line;
  final String? suggestion;
  
  ValidationIssue({
    required this.severity,
    required this.message,
    this.line,
    this.suggestion,
  });
  
  @override
  String toString() {
    return '[$severity] $message${line != null ? ' (line $line)' : ''}${suggestion != null ? '\nSuggestion: $suggestion' : ''}';
  }
}
```

## Troubleshooting

### Common Issues

1. **API Key Issues**
   - Verify API key is valid
   - Check project has AI/ML APIs enabled
   - Ensure billing is active

2. **Safety Blocks**
   - Review content for potential safety issues
   - Adjust safety settings if appropriate
   - Consider using different prompts

3. **Context Length Errors**
   - Use context window manager
   - Split large documents
   - Summarize when possible

4. **Multi-Modal Errors**
   - Check file formats are supported
   - Verify file sizes are within limits
   - Ensure proper base64 encoding

5. **Rate Limiting**
   - Implement backoff strategies
   - Use caching for repeated queries
   - Monitor usage quotas

## See Also

- [Anthropic Claude Integration](/doc/integrations/anthropic-claude.md)
- [OpenAI GPT Integration](/doc/integrations/openai-gpt.md)
- [Local LLM Integration](/doc/integrations/local-llm.md)
- [Security Best Practices](/doc/advanced/security.md)