# Anthropic Claude Integration

Complete guide for integrating Flutter MCP with Anthropic's Claude API.

## Overview

This guide demonstrates how to integrate Flutter MCP with Anthropic's Claude API for:
- Natural language processing
- Code generation and analysis
- Multi-modal AI capabilities
- Conversational AI interfaces
- Context-aware responses

## Setup

### API Configuration

```yaml
# pubspec.yaml
dependencies:
  flutter_mcp: ^1.0.0
  http: ^1.0.0
  crypto: ^3.0.0
```

```dart
// lib/claude_integration.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_mcp/flutter_mcp.dart';

class ClaudeIntegration {
  static const String _baseUrl = 'https://api.anthropic.com/v1';
  final String apiKey;
  final FlutterMCP mcp;
  
  ClaudeIntegration({
    required this.apiKey,
    required this.mcp,
  });
  
  Future<String> sendMessage(String message, {String? systemPrompt}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/messages'),
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': 'claude-3-opus-20240229',
        'messages': [
          {
            'role': 'user',
            'content': message,
          }
        ],
        if (systemPrompt != null) 'system': systemPrompt,
        'max_tokens': 4096,
      }),
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['content'][0]['text'];
    } else {
      throw Exception('Claude API error: ${response.statusCode}');
    }
  }
}
```

## MCP Server Implementation

### Claude-Powered MCP Server

```javascript
// server/claude-mcp-server.js
const { Server } = require('@modelcontextprotocol/sdk/server/index.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const Anthropic = require('@anthropic-ai/sdk');

class ClaudeMCPServer {
  constructor(apiKey) {
    this.anthropic = new Anthropic({
      apiKey: apiKey,
    });
    
    this.server = new Server({
      name: 'claude-assistant',
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
    // Code analysis tool
    this.server.setRequestHandler('tools/list', async () => ({
      tools: [
        {
          name: 'analyze_code',
          description: 'Analyze code using Claude',
          inputSchema: {
            type: 'object',
            properties: {
              code: { type: 'string' },
              language: { type: 'string' },
              task: { type: 'string', enum: ['review', 'optimize', 'explain', 'debug'] },
            },
            required: ['code', 'language', 'task'],
          },
        },
        {
          name: 'generate_code',
          description: 'Generate code using Claude',
          inputSchema: {
            type: 'object',
            properties: {
              description: { type: 'string' },
              language: { type: 'string' },
              framework: { type: 'string' },
            },
            required: ['description', 'language'],
          },
        },
        {
          name: 'natural_language_query',
          description: 'Process natural language queries',
          inputSchema: {
            type: 'object',
            properties: {
              query: { type: 'string' },
              context: { type: 'object' },
            },
            required: ['query'],
          },
        },
      ],
    }));
    
    this.server.setRequestHandler('tools/call', async (request) => {
      const { name, arguments: args } = request.params;
      
      switch (name) {
        case 'analyze_code':
          return await this.analyzeCode(args);
          
        case 'generate_code':
          return await this.generateCode(args);
          
        case 'natural_language_query':
          return await this.processNaturalLanguage(args);
          
        default:
          throw new Error(`Unknown tool: ${name}`);
      }
    });
  }
  
  setupPrompts() {
    this.server.setRequestHandler('prompts/list', async () => ({
      prompts: [
        {
          name: 'code_review',
          description: 'Comprehensive code review',
          arguments: [
            { name: 'code', type: 'string', required: true },
            { name: 'focus_areas', type: 'array', required: false },
          ],
        },
        {
          name: 'architecture_design',
          description: 'System architecture design',
          arguments: [
            { name: 'requirements', type: 'string', required: true },
            { name: 'constraints', type: 'array', required: false },
          ],
        },
        {
          name: 'documentation_generator',
          description: 'Generate technical documentation',
          arguments: [
            { name: 'code_base', type: 'string', required: true },
            { name: 'style', type: 'string', required: false },
          ],
        },
      ],
    }));
    
    this.server.setRequestHandler('prompts/get', async (request) => {
      const { name, arguments: args } = request.params;
      
      const prompts = {
        code_review: `Review the following code:
\`\`\`
${args.code}
\`\`\`

Focus areas: ${args.focus_areas?.join(', ') || 'general review'}

Please provide:
1. Code quality assessment
2. Performance considerations
3. Security issues
4. Best practice violations
5. Suggestions for improvement`,
        
        architecture_design: `Design a system architecture based on:

Requirements:
${args.requirements}

Constraints:
${args.constraints?.join('\n') || 'None specified'}

Please provide:
1. High-level architecture diagram description
2. Component breakdown
3. Technology stack recommendations
4. Scalability considerations
5. Security architecture`,
        
        documentation_generator: `Generate comprehensive documentation for:

${args.code_base}

Documentation style: ${args.style || 'technical'}

Include:
1. API documentation
2. Usage examples
3. Configuration options
4. Troubleshooting guide
5. Best practices`,
      };
      
      return {
        messages: [
          {
            role: 'user',
            content: prompts[name] || 'Invalid prompt',
          },
        ],
      };
    });
  }
  
  setupResources() {
    this.server.setRequestHandler('resources/list', async () => ({
      resources: [
        {
          uri: 'claude://conversations',
          name: 'Conversation History',
          description: 'Access Claude conversation history',
          mimeType: 'application/json',
        },
        {
          uri: 'claude://knowledge',
          name: 'Knowledge Base',
          description: 'Claude knowledge base entries',
          mimeType: 'application/json',
        },
      ],
    }));
    
    this.server.setRequestHandler('resources/read', async (request) => {
      const { uri } = request.params;
      
      if (uri === 'claude://conversations') {
        return {
          contents: [
            {
              uri,
              mimeType: 'application/json',
              text: JSON.stringify(this.conversationHistory),
            },
          ],
        };
      }
      
      if (uri === 'claude://knowledge') {
        return {
          contents: [
            {
              uri,
              mimeType: 'application/json',
              text: JSON.stringify(this.knowledgeBase),
            },
          ],
        };
      }
      
      throw new Error(`Unknown resource: ${uri}`);
    });
  }
  
  async analyzeCode({ code, language, task }) {
    const prompt = `Analyze the following ${language} code for ${task}:

\`\`\`${language}
${code}
\`\`\`

Provide detailed analysis focusing on ${task}.`;
    
    const message = await this.anthropic.messages.create({
      model: 'claude-3-opus-20240229',
      max_tokens: 4096,
      messages: [{ role: 'user', content: prompt }],
    });
    
    return {
      content: [
        {
          type: 'text',
          text: message.content[0].text,
        },
      ],
    };
  }
  
  async generateCode({ description, language, framework }) {
    const prompt = `Generate ${language} code${framework ? ` using ${framework}` : ''} for:

${description}

Include:
1. Implementation
2. Comments
3. Error handling
4. Best practices`;
    
    const message = await this.anthropic.messages.create({
      model: 'claude-3-opus-20240229',
      max_tokens: 4096,
      messages: [{ role: 'user', content: prompt }],
    });
    
    return {
      content: [
        {
          type: 'text',
          text: message.content[0].text,
        },
      ],
    };
  }
  
  async processNaturalLanguage({ query, context }) {
    const prompt = context 
      ? `Given the context: ${JSON.stringify(context)}\n\nAnswer: ${query}`
      : query;
    
    const message = await this.anthropic.messages.create({
      model: 'claude-3-opus-20240229',
      max_tokens: 4096,
      messages: [{ role: 'user', content: prompt }],
    });
    
    return {
      content: [
        {
          type: 'text',
          text: message.content[0].text,
        },
      ],
    };
  }
  
  async start() {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('Claude MCP Server started');
  }
}

// Start server
const apiKey = process.env.ANTHROPIC_API_KEY;
if (!apiKey) {
  console.error('ANTHROPIC_API_KEY environment variable is required');
  process.exit(1);
}

const server = new ClaudeMCPServer(apiKey);
server.start().catch(console.error);
```

## Flutter Integration

### Claude-Powered MCP Client

```dart
// lib/claude_mcp_client.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class ClaudeMCPClient extends StatefulWidget {
  const ClaudeMCPClient({Key? key}) : super(key: key);

  @override
  State<ClaudeMCPClient> createState() => _ClaudeMCPClientState();
}

class _ClaudeMCPClientState extends State<ClaudeMCPClient> {
  final _mcp = FlutterMCP();
  final _codeController = TextEditingController();
  String _analysisResult = '';
  bool _isLoading = false;
  
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
            id: 'claude-server',
            command: 'node',
            args: ['claude-mcp-server.js'],
            env: {
              'ANTHROPIC_API_KEY': 'your-api-key',
            },
          ),
        ],
      ),
    );
  }
  
  Future<void> _analyzeCode() async {
    setState(() {
      _isLoading = true;
      _analysisResult = '';
    });
    
    try {
      final result = await _mcp.client.callTool(
        serverId: 'claude-server',
        name: 'analyze_code',
        arguments: {
          'code': _codeController.text,
          'language': 'dart',
          'task': 'review',
        },
      );
      
      setState(() {
        _analysisResult = result.content.first.text;
      });
    } catch (e) {
      setState(() {
        _analysisResult = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _generateCode(String description) async {
    setState(() {
      _isLoading = true;
      _analysisResult = '';
    });
    
    try {
      final result = await _mcp.client.callTool(
        serverId: 'claude-server',
        name: 'generate_code',
        arguments: {
          'description': description,
          'language': 'dart',
          'framework': 'flutter',
        },
      );
      
      setState(() {
        _codeController.text = result.content.first.text;
        _analysisResult = 'Code generated successfully';
      });
    } catch (e) {
      setState(() {
        _analysisResult = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _askClaude(String query) async {
    setState(() {
      _isLoading = true;
      _analysisResult = '';
    });
    
    try {
      final result = await _mcp.client.callTool(
        serverId: 'claude-server',
        name: 'natural_language_query',
        arguments: {
          'query': query,
          'context': {
            'currentCode': _codeController.text,
            'language': 'dart',
          },
        },
      );
      
      setState(() {
        _analysisResult = result.content.first.text;
      });
    } catch (e) {
      setState(() {
        _analysisResult = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Claude MCP Integration'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: 'Enter code here...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _analyzeCode,
                  child: const Text('Analyze Code'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : () => _generateCode(
                    'Create a Flutter widget that displays a list of items',
                  ),
                  child: const Text('Generate Code'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : () => _askClaude(
                    'How can I improve this code?',
                  ),
                  child: const Text('Ask Claude'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Text(_analysisResult),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _codeController.dispose();
    _mcp.dispose();
    super.dispose();
  }
}
```

### Advanced Claude Features

```dart
// lib/claude_advanced_features.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:io';

class ClaudeAdvancedFeatures {
  final FlutterMCP mcp;
  
  ClaudeAdvancedFeatures({required this.mcp});
  
  // Multi-modal analysis
  Future<String> analyzeImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    
    final result = await mcp.client.callTool(
      serverId: 'claude-server',
      name: 'analyze_image',
      arguments: {
        'image': base64Image,
        'mimeType': 'image/jpeg',
        'task': 'describe',
      },
    );
    
    return result.content.first.text;
  }
  
  // Streaming responses
  Stream<String> streamCodeGeneration(String description) async* {
    final stream = mcp.client.streamTool(
      serverId: 'claude-server',
      name: 'generate_code_stream',
      arguments: {
        'description': description,
        'language': 'dart',
        'stream': true,
      },
    );
    
    await for (final chunk in stream) {
      yield chunk.content.first.text;
    }
  }
  
  // Context-aware conversations
  Future<String> continueConversation(
    List<Map<String, String>> history,
    String newMessage,
  ) async {
    final result = await mcp.client.callTool(
      serverId: 'claude-server',
      name: 'conversation',
      arguments: {
        'history': history,
        'message': newMessage,
        'model': 'claude-3-opus-20240229',
      },
    );
    
    return result.content.first.text;
  }
  
  // Code transformation
  Future<String> transformCode({
    required String sourceCode,
    required String fromLanguage,
    required String toLanguage,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'claude-server',
      name: 'transform_code',
      arguments: {
        'code': sourceCode,
        'from': fromLanguage,
        'to': toLanguage,
        'preserveLogic': true,
      },
    );
    
    return result.content.first.text;
  }
  
  // Architecture generation
  Future<Map<String, dynamic>> generateArchitecture(
    String requirements,
  ) async {
    final result = await mcp.client.callTool(
      serverId: 'claude-server',
      name: 'generate_architecture',
      arguments: {
        'requirements': requirements,
        'outputFormat': 'json',
        'includeDataFlow': true,
        'includeDiagrams': true,
      },
    );
    
    return jsonDecode(result.content.first.text);
  }
}
```

### Claude-Powered UI Components

```dart
// lib/widgets/claude_assistant_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class ClaudeAssistantWidget extends StatefulWidget {
  final FlutterMCP mcp;
  final String serverId;
  
  const ClaudeAssistantWidget({
    Key? key,
    required this.mcp,
    required this.serverId,
  }) : super(key: key);

  @override
  State<ClaudeAssistantWidget> createState() => _ClaudeAssistantWidgetState();
}

class _ClaudeAssistantWidgetState extends State<ClaudeAssistantWidget> {
  final _messageController = TextEditingController();
  final _messages = <ChatMessage>[];
  bool _isTyping = false;
  
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _messageController.clear();
      _isTyping = true;
    });
    
    try {
      final result = await widget.mcp.client.callTool(
        serverId: widget.serverId,
        name: 'natural_language_query',
        arguments: {
          'query': text,
          'context': {
            'previousMessages': _messages.map((m) => {
              'role': m.isUser ? 'user' : 'assistant',
              'content': m.text,
            }).toList(),
          },
        },
      );
      
      setState(() {
        _messages.add(ChatMessage(
          text: result.content.first.text,
          isUser: false,
          timestamp: DateTime.now(),
        ));
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
        _isTyping = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: _messages.length + (_isTyping ? 1 : 0),
            itemBuilder: (context, index) {
              if (_isTyping && index == 0) {
                return const TypingIndicator();
              }
              
              final messageIndex = _isTyping ? index - 1 : index;
              final message = _messages[_messages.length - 1 - messageIndex];
              
              return ChatBubble(message: message);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Ask Claude...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  
  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
  });
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  
  const ChatBubble({Key? key, required this.message}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.all(8.0),
        padding: const EdgeInsets.all(12.0),
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
        child: Text(message.text),
      ),
    );
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
      duration: const Duration(seconds: 1),
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
        margin: const EdgeInsets.all(8.0),
        padding: const EdgeInsets.all(12.0),
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
                final value = (_controller.value + index * 0.2) % 1.0;
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(value),
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

## Configuration

### Environment Variables

```dart
// lib/config/claude_config.dart
class ClaudeConfig {
  static const String apiKey = String.fromEnvironment(
    'ANTHROPIC_API_KEY',
    defaultValue: '',
  );
  
  static const String model = String.fromEnvironment(
    'CLAUDE_MODEL',
    defaultValue: 'claude-3-opus-20240229',
  );
  
  static const int maxTokens = int.fromEnvironment(
    'CLAUDE_MAX_TOKENS',
    defaultValue: 4096,
  );
  
  static const double temperature = double.fromEnvironment(
    'CLAUDE_TEMPERATURE',
    defaultValue: 0.7,
  );
}
```

### Server Configuration

```json
// claude-mcp-config.json
{
  "server": {
    "name": "claude-assistant",
    "version": "1.0.0"
  },
  "models": {
    "primary": "claude-3-opus-20240229",
    "fallback": "claude-3-sonnet-20240229",
    "fast": "claude-3-haiku-20240307"
  },
  "features": {
    "streaming": true,
    "multiModal": true,
    "contextWindow": 200000,
    "caching": true
  },
  "security": {
    "rateLimit": {
      "requests": 100,
      "window": "1h"
    },
    "allowedOrigins": ["*"],
    "requireAuth": true
  }
}
```

## Best Practices

### 1. API Key Security

```dart
// lib/security/api_key_manager.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiKeyManager {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'anthropic_api_key';
  
  static Future<void> saveApiKey(String apiKey) async {
    await _storage.write(key: _keyName, value: apiKey);
  }
  
  static Future<String?> getApiKey() async {
    return await _storage.read(key: _keyName);
  }
  
  static Future<void> deleteApiKey() async {
    await _storage.delete(key: _keyName);
  }
}
```

### 2. Context Management

```dart
// lib/claude/context_manager.dart
class ClaudeContextManager {
  static const int maxContextLength = 100000;
  final List<ContextEntry> _context = [];
  
  void addToContext(String content, {String? metadata}) {
    _context.add(ContextEntry(
      content: content,
      timestamp: DateTime.now(),
      metadata: metadata,
    ));
    
    _trimContext();
  }
  
  void _trimContext() {
    int totalLength = 0;
    int cutoffIndex = _context.length;
    
    for (int i = _context.length - 1; i >= 0; i--) {
      totalLength += _context[i].content.length;
      if (totalLength > maxContextLength) {
        cutoffIndex = i + 1;
        break;
      }
    }
    
    if (cutoffIndex < _context.length) {
      _context.removeRange(0, cutoffIndex);
    }
  }
  
  String getFullContext() {
    return _context.map((e) => e.content).join('\n\n');
  }
  
  void clearContext() {
    _context.clear();
  }
}

class ContextEntry {
  final String content;
  final DateTime timestamp;
  final String? metadata;
  
  ContextEntry({
    required this.content,
    required this.timestamp,
    this.metadata,
  });
}
```

### 3. Error Handling

```dart
// lib/claude/error_handler.dart
class ClaudeErrorHandler {
  static String getErrorMessage(dynamic error) {
    if (error is ClaudeAPIError) {
      switch (error.code) {
        case 'rate_limit_exceeded':
          return 'Too many requests. Please try again later.';
        case 'invalid_api_key':
          return 'Invalid API key. Please check your configuration.';
        case 'context_length_exceeded':
          return 'Message too long. Please shorten your request.';
        default:
          return error.message;
      }
    }
    
    return 'An unexpected error occurred. Please try again.';
  }
  
  static Future<T> retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    int attempts = 0;
    Duration delay = initialDelay;
    
    while (attempts < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempts++;
        if (attempts >= maxRetries) {
          rethrow;
        }
        
        await Future.delayed(delay);
        delay *= 2; // Exponential backoff
      }
    }
    
    throw Exception('Operation failed after $maxRetries attempts');
  }
}

class ClaudeAPIError extends Error {
  final String code;
  final String message;
  
  ClaudeAPIError({required this.code, required this.message});
}
```

## Advanced Use Cases

### 1. Code Review Assistant

```dart
// lib/features/code_review_assistant.dart
class CodeReviewAssistant extends StatefulWidget {
  final FlutterMCP mcp;
  
  const CodeReviewAssistant({Key? key, required this.mcp}) : super(key: key);

  @override
  State<CodeReviewAssistant> createState() => _CodeReviewAssistantState();
}

class _CodeReviewAssistantState extends State<CodeReviewAssistant> {
  final _diffController = TextEditingController();
  CodeReview? _review;
  bool _isLoading = false;
  
  Future<void> _reviewCode() async {
    setState(() {
      _isLoading = true;
      _review = null;
    });
    
    try {
      final result = await widget.mcp.client.callTool(
        serverId: 'claude-server',
        name: 'code_review',
        arguments: {
          'diff': _diffController.text,
          'type': 'comprehensive',
          'includeSuggestions': true,
        },
      );
      
      setState(() {
        _review = CodeReview.fromJson(jsonDecode(result.content.first.text));
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Code Review Assistant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.rate_review),
            onPressed: _isLoading ? null : _reviewCode,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _diffController,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: 'Paste your git diff here...',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          const Divider(),
          Expanded(
            flex: 3,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _review == null
                    ? const Center(child: Text('Submit code for review'))
                    : CodeReviewDisplay(review: _review!),
          ),
        ],
      ),
    );
  }
}

class CodeReview {
  final String summary;
  final List<Issue> issues;
  final List<Suggestion> suggestions;
  final double qualityScore;
  
  CodeReview({
    required this.summary,
    required this.issues,
    required this.suggestions,
    required this.qualityScore,
  });
  
  factory CodeReview.fromJson(Map<String, dynamic> json) {
    return CodeReview(
      summary: json['summary'],
      issues: (json['issues'] as List)
          .map((i) => Issue.fromJson(i))
          .toList(),
      suggestions: (json['suggestions'] as List)
          .map((s) => Suggestion.fromJson(s))
          .toList(),
      qualityScore: json['qualityScore'].toDouble(),
    );
  }
}

class Issue {
  final String severity;
  final String message;
  final String? file;
  final int? line;
  
  Issue({
    required this.severity,
    required this.message,
    this.file,
    this.line,
  });
  
  factory Issue.fromJson(Map<String, dynamic> json) {
    return Issue(
      severity: json['severity'],
      message: json['message'],
      file: json['file'],
      line: json['line'],
    );
  }
}

class Suggestion {
  final String type;
  final String description;
  final String? code;
  
  Suggestion({
    required this.type,
    required this.description,
    this.code,
  });
  
  factory Suggestion.fromJson(Map<String, dynamic> json) {
    return Suggestion(
      type: json['type'],
      description: json['description'],
      code: json['code'],
    );
  }
}
```

### 2. Documentation Generator

```dart
// lib/features/documentation_generator.dart
class DocumentationGenerator {
  final FlutterMCP mcp;
  
  DocumentationGenerator({required this.mcp});
  
  Future<String> generateApiDocs(String sourceCode) async {
    final result = await mcp.client.callTool(
      serverId: 'claude-server',
      name: 'generate_documentation',
      arguments: {
        'code': sourceCode,
        'format': 'markdown',
        'includeExamples': true,
        'includeTypes': true,
      },
    );
    
    return result.content.first.text;
  }
  
  Future<String> generateReadme(String projectPath) async {
    final files = await _scanProject(projectPath);
    
    final result = await mcp.client.callTool(
      serverId: 'claude-server',
      name: 'generate_readme',
      arguments: {
        'files': files,
        'projectType': 'flutter',
        'includeBadges': true,
        'includeExamples': true,
      },
    );
    
    return result.content.first.text;
  }
  
  Future<List<Map<String, String>>> _scanProject(String path) async {
    final directory = Directory(path);
    final files = <Map<String, String>>[];
    
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add({
          'path': entity.path,
          'content': await entity.readAsString(),
        });
      }
    }
    
    return files;
  }
}
```

## Troubleshooting

### Common Issues

1. **API Key Issues**
   - Verify API key is valid
   - Check environment variables
   - Ensure proper key storage

2. **Rate Limiting**
   - Implement exponential backoff
   - Cache responses when possible
   - Use streaming for large responses

3. **Context Length**
   - Trim context periodically
   - Use summarization for long conversations
   - Split large requests

4. **Connection Errors**
   - Check network connectivity
   - Verify server is running
   - Check firewall settings

## See Also

- [OpenAI GPT Integration](/doc/integrations/openai-gpt.md)
- [Google Gemini Integration](/doc/integrations/google-gemini.md)
- [Local LLM Integration](/doc/integrations/local-llm.md)
- [Security Best Practices](/doc/advanced/security.md)