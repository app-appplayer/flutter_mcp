# OpenAI GPT Integration

Complete guide for integrating Flutter MCP with OpenAI's GPT models.

## Overview

This guide demonstrates how to integrate Flutter MCP with OpenAI's GPT API for:
- Text generation and completion
- Function calling and tool use
- Embeddings and semantic search
- Vision capabilities with GPT-4V
- Real-time streaming responses
- Fine-tuned model integration

## Setup

### API Configuration

```yaml
# pubspec.yaml
dependencies:
  flutter_mcp: ^1.0.0
  http: ^1.0.0
  dart_openai: ^5.0.0
```

```dart
// lib/openai_integration.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:dart_openai/dart_openai.dart';

class OpenAIIntegration {
  static const String _baseUrl = 'https://api.openai.com/v1';
  final String apiKey;
  final FlutterMCP mcp;
  
  OpenAIIntegration({
    required this.apiKey,
    required this.mcp,
  }) {
    OpenAI.apiKey = apiKey;
  }
  
  Future<String> generateText(String prompt, {String? model}) async {
    final completion = await OpenAI.instance.completion.create(
      model: model ?? 'gpt-4',
      messages: [
        OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.user,
          content: [
            OpenAIChatCompletionChoiceMessageContentItemModel.text(prompt),
          ],
        ),
      ],
      maxTokens: 1000,
    );
    
    return completion.choices.first.message.content?.first.text ?? '';
  }
  
  Stream<String> streamResponse(String prompt) async* {
    final stream = OpenAI.instance.completion.createStream(
      model: 'gpt-4',
      messages: [
        OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.user,
          content: [
            OpenAIChatCompletionChoiceMessageContentItemModel.text(prompt),
          ],
        ),
      ],
    );
    
    await for (final chunk in stream) {
      final content = chunk.choices.first.delta.content;
      if (content != null && content.isNotEmpty) {
        yield content.first.text ?? '';
      }
    }
  }
}
```

## MCP Server Implementation

### GPT-Powered MCP Server

```javascript
// server/gpt-mcp-server.js
const { Server } = require('@modelcontextprotocol/sdk/server/index.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const OpenAI = require('openai');

class GPTMCPServer {
  constructor(apiKey) {
    this.openai = new OpenAI({
      apiKey: apiKey,
    });
    
    this.server = new Server({
      name: 'gpt-assistant',
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
          name: 'text_generation',
          description: 'Generate text using GPT models',
          inputSchema: {
            type: 'object',
            properties: {
              prompt: { type: 'string' },
              model: { type: 'string', enum: ['gpt-4', 'gpt-4-turbo', 'gpt-3.5-turbo'] },
              temperature: { type: 'number', minimum: 0, maximum: 2 },
              maxTokens: { type: 'integer', minimum: 1 },
            },
            required: ['prompt'],
          },
        },
        {
          name: 'function_calling',
          description: 'Execute function calls with GPT',
          inputSchema: {
            type: 'object',
            properties: {
              messages: { type: 'array' },
              functions: { type: 'array' },
              functionCall: { type: 'string', enum: ['auto', 'none'] },
            },
            required: ['messages', 'functions'],
          },
        },
        {
          name: 'embeddings',
          description: 'Generate embeddings for text',
          inputSchema: {
            type: 'object',
            properties: {
              texts: { type: 'array', items: { type: 'string' } },
              model: { type: 'string', default: 'text-embedding-3-small' },
            },
            required: ['texts'],
          },
        },
        {
          name: 'vision_analysis',
          description: 'Analyze images with GPT-4V',
          inputSchema: {
            type: 'object',
            properties: {
              imageUrl: { type: 'string' },
              prompt: { type: 'string' },
              detail: { type: 'string', enum: ['low', 'high', 'auto'] },
            },
            required: ['imageUrl', 'prompt'],
          },
        },
      ],
    }));
    
    this.server.setRequestHandler('tools/call', async (request) => {
      const { name, arguments: args } = request.params;
      
      switch (name) {
        case 'text_generation':
          return await this.generateText(args);
          
        case 'function_calling':
          return await this.executeFunctionCall(args);
          
        case 'embeddings':
          return await this.generateEmbeddings(args);
          
        case 'vision_analysis':
          return await this.analyzeImage(args);
          
        default:
          throw new Error(`Unknown tool: ${name}`);
      }
    });
  }
  
  setupPrompts() {
    this.server.setRequestHandler('prompts/list', async () => ({
      prompts: [
        {
          name: 'code_assistant',
          description: 'Programming assistant prompt',
          arguments: [
            { name: 'language', type: 'string', required: true },
            { name: 'task', type: 'string', required: true },
          ],
        },
        {
          name: 'data_analyst',
          description: 'Data analysis prompt',
          arguments: [
            { name: 'data', type: 'string', required: true },
            { name: 'analysis_type', type: 'string', required: true },
          ],
        },
        {
          name: 'creative_writer',
          description: 'Creative writing prompt',
          arguments: [
            { name: 'genre', type: 'string', required: true },
            { name: 'topic', type: 'string', required: true },
          ],
        },
      ],
    }));
    
    this.server.setRequestHandler('prompts/get', async (request) => {
      const { name, arguments: args } = request.params;
      
      const prompts = {
        code_assistant: {
          messages: [
            {
              role: 'system',
              content: `You are an expert ${args.language} programmer. Help with: ${args.task}`,
            },
          ],
        },
        data_analyst: {
          messages: [
            {
              role: 'system',
              content: `You are a data analyst. Analyze the following data: ${args.data}
Analysis type: ${args.analysis_type}`,
            },
          ],
        },
        creative_writer: {
          messages: [
            {
              role: 'system',
              content: `You are a creative writer specializing in ${args.genre}. 
Write about: ${args.topic}`,
            },
          ],
        },
      };
      
      return prompts[name] || { messages: [] };
    });
  }
  
  setupResources() {
    this.server.setRequestHandler('resources/list', async () => ({
      resources: [
        {
          uri: 'gpt://models',
          name: 'Available Models',
          description: 'List of available GPT models',
          mimeType: 'application/json',
        },
        {
          uri: 'gpt://fine-tunes',
          name: 'Fine-tuned Models',
          description: 'Custom fine-tuned models',
          mimeType: 'application/json',
        },
      ],
    }));
    
    this.server.setRequestHandler('resources/read', async (request) => {
      const { uri } = request.params;
      
      if (uri === 'gpt://models') {
        const models = await this.openai.models.list();
        return {
          contents: [
            {
              uri,
              mimeType: 'application/json',
              text: JSON.stringify(models.data),
            },
          ],
        };
      }
      
      if (uri === 'gpt://fine-tunes') {
        const fineTunes = await this.openai.fineTuning.jobs.list();
        return {
          contents: [
            {
              uri,
              mimeType: 'application/json',
              text: JSON.stringify(fineTunes.data),
            },
          ],
        };
      }
      
      throw new Error(`Unknown resource: ${uri}`);
    });
  }
  
  async generateText({ prompt, model, temperature, maxTokens }) {
    const response = await this.openai.chat.completions.create({
      model: model || 'gpt-4',
      messages: [{ role: 'user', content: prompt }],
      temperature: temperature || 0.7,
      max_tokens: maxTokens || 1000,
    });
    
    return {
      content: [
        {
          type: 'text',
          text: response.choices[0].message.content,
        },
      ],
    };
  }
  
  async executeFunctionCall({ messages, functions, functionCall }) {
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4',
      messages: messages,
      functions: functions,
      function_call: functionCall || 'auto',
    });
    
    const message = response.choices[0].message;
    
    if (message.function_call) {
      return {
        content: [
          {
            type: 'function_call',
            name: message.function_call.name,
            arguments: message.function_call.arguments,
          },
        ],
      };
    }
    
    return {
      content: [
        {
          type: 'text',
          text: message.content,
        },
      ],
    };
  }
  
  async generateEmbeddings({ texts, model }) {
    const response = await this.openai.embeddings.create({
      model: model || 'text-embedding-3-small',
      input: texts,
    });
    
    return {
      content: [
        {
          type: 'embeddings',
          data: response.data.map(item => ({
            index: item.index,
            embedding: item.embedding,
          })),
        },
      ],
    };
  }
  
  async analyzeImage({ imageUrl, prompt, detail }) {
    const response = await this.openai.chat.completions.create({
      model: 'gpt-4-vision-preview',
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: prompt },
            { type: 'image_url', image_url: { url: imageUrl, detail: detail || 'auto' } },
          ],
        },
      ],
      max_tokens: 1000,
    });
    
    return {
      content: [
        {
          type: 'text',
          text: response.choices[0].message.content,
        },
      ],
    };
  }
  
  async start() {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('GPT MCP Server started');
  }
}

// Start server
const apiKey = process.env.OPENAI_API_KEY;
if (!apiKey) {
  console.error('OPENAI_API_KEY environment variable is required');
  process.exit(1);
}

const server = new GPTMCPServer(apiKey);
server.start().catch(console.error);
```

## Flutter Integration

### GPT-Powered MCP Client

```dart
// lib/gpt_mcp_client.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:convert';

class GPTMCPClient extends StatefulWidget {
  const GPTMCPClient({Key? key}) : super(key: key);

  @override
  State<GPTMCPClient> createState() => _GPTMCPClientState();
}

class _GPTMCPClientState extends State<GPTMCPClient> {
  final _mcp = FlutterMCP();
  final _promptController = TextEditingController();
  String _response = '';
  bool _isLoading = false;
  String _selectedModel = 'gpt-4';
  double _temperature = 0.7;
  
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
            id: 'gpt-server',
            command: 'node',
            args: ['gpt-mcp-server.js'],
            env: {
              'OPENAI_API_KEY': 'your-api-key',
            },
          ),
        ],
      ),
    );
  }
  
  Future<void> _generateText() async {
    setState(() {
      _isLoading = true;
      _response = '';
    });
    
    try {
      final result = await _mcp.client.callTool(
        serverId: 'gpt-server',
        name: 'text_generation',
        arguments: {
          'prompt': _promptController.text,
          'model': _selectedModel,
          'temperature': _temperature,
          'maxTokens': 1000,
        },
      );
      
      setState(() {
        _response = result.content.first.text;
      });
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _streamResponse() async {
    setState(() {
      _isLoading = true;
      _response = '';
    });
    
    try {
      final stream = _mcp.client.streamTool(
        serverId: 'gpt-server',
        name: 'text_generation_stream',
        arguments: {
          'prompt': _promptController.text,
          'model': _selectedModel,
          'temperature': _temperature,
        },
      );
      
      await for (final chunk in stream) {
        setState(() {
          _response += chunk.content.first.text;
        });
      }
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
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
        title: const Text('GPT MCP Integration'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedModel,
                      decoration: const InputDecoration(
                        labelText: 'Model',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'gpt-4',
                          child: Text('GPT-4'),
                        ),
                        DropdownMenuItem(
                          value: 'gpt-4-turbo',
                          child: Text('GPT-4 Turbo'),
                        ),
                        DropdownMenuItem(
                          value: 'gpt-3.5-turbo',
                          child: Text('GPT-3.5 Turbo'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedModel = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Temperature:'),
                        Expanded(
                          child: Slider(
                            value: _temperature,
                            min: 0,
                            max: 2,
                            divisions: 20,
                            label: _temperature.toStringAsFixed(1),
                            onChanged: (value) {
                              setState(() {
                                _temperature = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _promptController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter your prompt...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _generateText,
                  child: const Text('Generate'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _streamResponse,
                  child: const Text('Stream'),
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
                  child: _isLoading && _response.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : SelectableText(_response),
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
    _promptController.dispose();
    _mcp.dispose();
    super.dispose();
  }
}
```

### Advanced GPT Features

```dart
// lib/gpt_advanced_features.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:io';
import 'dart:convert';

class GPTAdvancedFeatures {
  final FlutterMCP mcp;
  
  GPTAdvancedFeatures({required this.mcp});
  
  // Function calling
  Future<Map<String, dynamic>> executeFunctionCall({
    required String message,
    required List<Map<String, dynamic>> functions,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'function_calling',
      arguments: {
        'messages': [
          {'role': 'user', 'content': message}
        ],
        'functions': functions,
        'functionCall': 'auto',
      },
    );
    
    final content = result.content.first;
    if (content.type == 'function_call') {
      return {
        'function': content.name,
        'arguments': jsonDecode(content.arguments),
      };
    }
    
    return {'text': content.text};
  }
  
  // Embeddings for semantic search
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    final result = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'embeddings',
      arguments: {
        'texts': texts,
        'model': 'text-embedding-3-small',
      },
    );
    
    final embeddings = result.content.first.data as List;
    return embeddings.map((e) => List<double>.from(e['embedding'])).toList();
  }
  
  // Vision analysis
  Future<String> analyzeImage(File imageFile, String prompt) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final dataUrl = 'data:image/jpeg;base64,$base64Image';
    
    final result = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'vision_analysis',
      arguments: {
        'imageUrl': dataUrl,
        'prompt': prompt,
        'detail': 'high',
      },
    );
    
    return result.content.first.text;
  }
  
  // Semantic search implementation
  Future<List<SearchResult>> semanticSearch({
    required String query,
    required List<String> documents,
  }) async {
    // Generate embeddings for query and documents
    final allTexts = [query, ...documents];
    final embeddings = await generateEmbeddings(allTexts);
    
    final queryEmbedding = embeddings.first;
    final docEmbeddings = embeddings.skip(1).toList();
    
    // Calculate cosine similarity
    final results = <SearchResult>[];
    for (int i = 0; i < documents.length; i++) {
      final similarity = cosineSimilarity(queryEmbedding, docEmbeddings[i]);
      results.add(SearchResult(
        document: documents[i],
        similarity: similarity,
        index: i,
      ));
    }
    
    // Sort by similarity
    results.sort((a, b) => b.similarity.compareTo(a.similarity));
    
    return results;
  }
  
  double cosineSimilarity(List<double> a, List<double> b) {
    double dotProduct = 0;
    double magnitudeA = 0;
    double magnitudeB = 0;
    
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      magnitudeA += a[i] * a[i];
      magnitudeB += b[i] * b[i];
    }
    
    return dotProduct / (sqrt(magnitudeA) * sqrt(magnitudeB));
  }
}

class SearchResult {
  final String document;
  final double similarity;
  final int index;
  
  SearchResult({
    required this.document,
    required this.similarity,
    required this.index,
  });
}
```

### Function Calling Widget

```dart
// lib/widgets/function_calling_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class FunctionCallingWidget extends StatefulWidget {
  final FlutterMCP mcp;
  
  const FunctionCallingWidget({Key? key, required this.mcp}) : super(key: key);

  @override
  State<FunctionCallingWidget> createState() => _FunctionCallingWidgetState();
}

class _FunctionCallingWidgetState extends State<FunctionCallingWidget> {
  final _controller = TextEditingController();
  final _results = <FunctionCallResult>[];
  bool _isLoading = false;
  
  final _availableFunctions = [
    {
      'name': 'get_weather',
      'description': 'Get the current weather for a location',
      'parameters': {
        'type': 'object',
        'properties': {
          'location': {
            'type': 'string',
            'description': 'The city and state, e.g. San Francisco, CA',
          },
          'unit': {
            'type': 'string',
            'enum': ['celsius', 'fahrenheit'],
            'description': 'The temperature unit',
          },
        },
        'required': ['location'],
      },
    },
    {
      'name': 'search_web',
      'description': 'Search the web for information',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The search query',
          },
          'num_results': {
            'type': 'integer',
            'description': 'Number of results to return',
            'default': 5,
          },
        },
        'required': ['query'],
      },
    },
    {
      'name': 'calculate',
      'description': 'Perform mathematical calculations',
      'parameters': {
        'type': 'object',
        'properties': {
          'expression': {
            'type': 'string',
            'description': 'The mathematical expression to evaluate',
          },
        },
        'required': ['expression'],
      },
    },
  ];
  
  Future<void> _processFunctionCall() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _results.add(FunctionCallResult(
        type: 'user',
        content: message,
        timestamp: DateTime.now(),
      ));
    });
    
    try {
      final advanced = GPTAdvancedFeatures(mcp: widget.mcp);
      final result = await advanced.executeFunctionCall(
        message: message,
        functions: _availableFunctions,
      );
      
      if (result.containsKey('function')) {
        // Function was called
        final functionName = result['function'];
        final arguments = result['arguments'];
        
        setState(() {
          _results.add(FunctionCallResult(
            type: 'function',
            content: 'Calling $functionName with $arguments',
            timestamp: DateTime.now(),
          ));
        });
        
        // Execute the actual function
        final functionResult = await _executeFunction(functionName, arguments);
        
        setState(() {
          _results.add(FunctionCallResult(
            type: 'result',
            content: functionResult,
            timestamp: DateTime.now(),
          ));
        });
      } else {
        // Regular text response
        setState(() {
          _results.add(FunctionCallResult(
            type: 'assistant',
            content: result['text'],
            timestamp: DateTime.now(),
          ));
        });
      }
    } catch (e) {
      setState(() {
        _results.add(FunctionCallResult(
          type: 'error',
          content: 'Error: $e',
          timestamp: DateTime.now(),
        ));
      });
    } finally {
      setState(() {
        _isLoading = false;
        _controller.clear();
      });
    }
  }
  
  Future<String> _executeFunction(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    switch (name) {
      case 'get_weather':
        // Simulate weather API call
        final location = arguments['location'];
        final unit = arguments['unit'] ?? 'celsius';
        return 'Weather in $location: 22°${unit == 'celsius' ? 'C' : 'F'}, Partly cloudy';
        
      case 'search_web':
        // Simulate web search
        final query = arguments['query'];
        final numResults = arguments['num_results'] ?? 5;
        return 'Found $numResults results for "$query":\n'
            '1. Result 1\n'
            '2. Result 2\n'
            '3. Result 3';
        
      case 'calculate':
        // Simulate calculation
        final expression = arguments['expression'];
        try {
          // In real implementation, use a proper math parser
          return 'Result: ${expression} = 42';
        } catch (e) {
          return 'Error evaluating expression: $e';
        }
        
      default:
        return 'Unknown function: $name';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final result = _results[_results.length - 1 - index];
              return FunctionCallResultCard(result: result);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Ask something...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _processFunctionCall(),
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
                onPressed: _isLoading ? null : _processFunctionCall,
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
    super.dispose();
  }
}

class FunctionCallResult {
  final String type;
  final String content;
  final DateTime timestamp;
  
  FunctionCallResult({
    required this.type,
    required this.content,
    required this.timestamp,
  });
}

class FunctionCallResultCard extends StatelessWidget {
  final FunctionCallResult result;
  
  const FunctionCallResultCard({Key? key, required this.result}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    IconData icon;
    
    switch (result.type) {
      case 'user':
        backgroundColor = Colors.blue.shade50;
        icon = Icons.person;
        break;
      case 'assistant':
        backgroundColor = Colors.green.shade50;
        icon = Icons.smart_toy;
        break;
      case 'function':
        backgroundColor = Colors.orange.shade50;
        icon = Icons.functions;
        break;
      case 'result':
        backgroundColor = Colors.purple.shade50;
        icon = Icons.check_circle;
        break;
      case 'error':
        backgroundColor = Colors.red.shade50;
        icon = Icons.error;
        break;
      default:
        backgroundColor = Colors.grey.shade50;
        icon = Icons.info;
    }
    
    return Card(
      color: backgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(result.content),
            ),
            Text(
              '${result.timestamp.hour}:${result.timestamp.minute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
```

### Vision Analysis Widget

```dart
// lib/widgets/vision_analysis_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class VisionAnalysisWidget extends StatefulWidget {
  final FlutterMCP mcp;
  
  const VisionAnalysisWidget({Key? key, required this.mcp}) : super(key: key);

  @override
  State<VisionAnalysisWidget> createState() => _VisionAnalysisWidgetState();
}

class _VisionAnalysisWidgetState extends State<VisionAnalysisWidget> {
  File? _selectedImage;
  String _analysis = '';
  bool _isLoading = false;
  final _promptController = TextEditingController(
    text: 'What is in this image?',
  );
  
  Future<void> _selectImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _analysis = '';
      });
    }
  }
  
  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;
    
    setState(() {
      _isLoading = true;
      _analysis = '';
    });
    
    try {
      final advanced = GPTAdvancedFeatures(mcp: widget.mcp);
      final result = await advanced.analyzeImage(
        _selectedImage!,
        _promptController.text,
      );
      
      setState(() {
        _analysis = result;
      });
    } catch (e) {
      setState(() {
        _analysis = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _selectedImage == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text('No image selected'),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    Center(
                      child: Image.file(
                        _selectedImage!,
                        fit: BoxFit.contain,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _selectedImage = null;
                            _analysis = '';
                          });
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promptController,
                  decoration: const InputDecoration(
                    hintText: 'Ask about the image...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _selectedImage == null || _isLoading
                    ? null
                    : _analyzeImage,
                child: const Text('Analyze'),
              ),
            ],
          ),
        ),
        Container(
          height: 150,
          width: double.infinity,
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Text(_analysis),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
                onPressed: () => _selectImage(ImageSource.camera),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.photo),
                label: const Text('Gallery'),
                onPressed: () => _selectImage(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }
}
```

## Configuration

### Environment Variables

```dart
// lib/config/openai_config.dart
class OpenAIConfig {
  static const String apiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );
  
  static const String organization = String.fromEnvironment(
    'OPENAI_ORGANIZATION',
    defaultValue: '',
  );
  
  static const String defaultModel = String.fromEnvironment(
    'OPENAI_DEFAULT_MODEL',
    defaultValue: 'gpt-4',
  );
  
  static const int maxTokens = int.fromEnvironment(
    'OPENAI_MAX_TOKENS',
    defaultValue: 1000,
  );
  
  static const double defaultTemperature = double.fromEnvironment(
    'OPENAI_DEFAULT_TEMPERATURE',
    defaultValue: 0.7,
  );
}
```

### Fine-tuning Configuration

```dart
// lib/config/fine_tuning_config.dart
class FineTuningConfig {
  final String baseModel;
  final String trainingFile;
  final String validationFile;
  final Map<String, dynamic> hyperparameters;
  
  FineTuningConfig({
    required this.baseModel,
    required this.trainingFile,
    required this.validationFile,
    this.hyperparameters = const {},
  });
  
  Map<String, dynamic> toJson() => {
    'model': baseModel,
    'training_file': trainingFile,
    'validation_file': validationFile,
    'hyperparameters': hyperparameters,
  };
}

class FineTuningManager {
  final FlutterMCP mcp;
  
  FineTuningManager({required this.mcp});
  
  Future<String> createFineTuningJob(FineTuningConfig config) async {
    final result = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'create_fine_tuning',
      arguments: config.toJson(),
    );
    
    return result.content.first.text;
  }
  
  Future<List<FineTuningJob>> listFineTuningJobs() async {
    final result = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'list_fine_tuning_jobs',
      arguments: {},
    );
    
    final data = jsonDecode(result.content.first.text) as List;
    return data.map((job) => FineTuningJob.fromJson(job)).toList();
  }
}

class FineTuningJob {
  final String id;
  final String model;
  final String status;
  final DateTime createdAt;
  final String? fineTunedModel;
  
  FineTuningJob({
    required this.id,
    required this.model,
    required this.status,
    required this.createdAt,
    this.fineTunedModel,
  });
  
  factory FineTuningJob.fromJson(Map<String, dynamic> json) {
    return FineTuningJob(
      id: json['id'],
      model: json['model'],
      status: json['status'],
      createdAt: DateTime.parse(json['created_at']),
      fineTunedModel: json['fine_tuned_model'],
    );
  }
}
```

## Best Practices

### 1. Rate Limiting

```dart
// lib/utils/rate_limiter.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class RateLimiter {
  final int maxRequests;
  final Duration window;
  final List<DateTime> _requests = [];
  
  RateLimiter({
    required this.maxRequests,
    required this.window,
  });
  
  Future<T> execute<T>(Future<T> Function() operation) async {
    await _waitIfNeeded();
    _requests.add(DateTime.now());
    _cleanup();
    
    return await operation();
  }
  
  Future<void> _waitIfNeeded() async {
    _cleanup();
    
    if (_requests.length >= maxRequests) {
      final oldestRequest = _requests.first;
      final timeSince = DateTime.now().difference(oldestRequest);
      
      if (timeSince < window) {
        final waitTime = window - timeSince;
        await Future.delayed(waitTime);
      }
    }
  }
  
  void _cleanup() {
    final cutoff = DateTime.now().subtract(window);
    _requests.removeWhere((time) => time.isBefore(cutoff));
  }
}

// Usage with MCP
class RateLimitedGPTClient {
  final FlutterMCP mcp;
  final RateLimiter rateLimiter = RateLimiter(
    maxRequests: 60,
    window: Duration(minutes: 1),
  );
  
  RateLimitedGPTClient({required this.mcp});
  
  Future<String> generateText(String prompt) async {
    return await rateLimiter.execute(() async {
      final result = await mcp.client.callTool(
        serverId: 'gpt-server',
        name: 'text_generation',
        arguments: {'prompt': prompt},
      );
      
      return result.content.first.text;
    });
  }
}
```

### 2. Token Management

```dart
// lib/utils/token_manager.dart
import 'package:tiktoken/tiktoken.dart';

class TokenManager {
  final encoding = getEncoding('cl100k_base');
  
  int countTokens(String text) {
    return encoding.encode(text).length;
  }
  
  String truncateToTokenLimit(String text, int maxTokens) {
    final tokens = encoding.encode(text);
    
    if (tokens.length <= maxTokens) {
      return text;
    }
    
    final truncatedTokens = tokens.take(maxTokens).toList();
    return encoding.decode(truncatedTokens);
  }
  
  int estimateCost({
    required String model,
    required int inputTokens,
    required int outputTokens,
  }) {
    // Prices per 1K tokens (as of 2024)
    final prices = {
      'gpt-4': {'input': 0.03, 'output': 0.06},
      'gpt-4-turbo': {'input': 0.01, 'output': 0.03},
      'gpt-3.5-turbo': {'input': 0.0005, 'output': 0.0015},
    };
    
    final modelPrices = prices[model] ?? prices['gpt-4']!;
    
    final inputCost = (inputTokens / 1000) * modelPrices['input']!;
    final outputCost = (outputTokens / 1000) * modelPrices['output']!;
    
    return ((inputCost + outputCost) * 100).round(); // Return cents
  }
}
```

### 3. Caching Responses

```dart
// lib/utils/response_cache.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:crypto/crypto.dart';

class ResponseCache {
  final Map<String, CachedResponse> _cache = {};
  final Duration ttl;
  
  ResponseCache({this.ttl = const Duration(minutes: 15)});
  
  String _generateKey(String toolName, Map<String, dynamic> arguments) {
    final input = '$toolName:${jsonEncode(arguments)}';
    return md5.convert(utf8.encode(input)).toString();
  }
  
  Future<T> getOrExecute<T>({
    required String toolName,
    required Map<String, dynamic> arguments,
    required Future<T> Function() execute,
  }) async {
    final key = _generateKey(toolName, arguments);
    
    // Check cache
    final cached = _cache[key];
    if (cached != null && !cached.isExpired) {
      return cached.data as T;
    }
    
    // Execute and cache
    final result = await execute();
    _cache[key] = CachedResponse(
      data: result,
      timestamp: DateTime.now(),
      ttl: ttl,
    );
    
    return result;
  }
  
  void clear() {
    _cache.clear();
  }
  
  void evictExpired() {
    _cache.removeWhere((key, value) => value.isExpired);
  }
}

class CachedResponse {
  final dynamic data;
  final DateTime timestamp;
  final Duration ttl;
  
  CachedResponse({
    required this.data,
    required this.timestamp,
    required this.ttl,
  });
  
  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
}
```

## Advanced Use Cases

### 1. Conversation Memory

```dart
// lib/features/conversation_memory.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class ConversationMemory {
  final List<Message> _messages = [];
  final int maxMessages;
  final int maxTokens;
  final TokenManager tokenManager = TokenManager();
  
  ConversationMemory({
    this.maxMessages = 10,
    this.maxTokens = 4000,
  });
  
  void addMessage(String role, String content) {
    _messages.add(Message(
      role: role,
      content: content,
      timestamp: DateTime.now(),
    ));
    
    _trim();
  }
  
  void _trim() {
    // Trim by message count
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
    
    // Trim by token count
    int totalTokens = 0;
    int cutoffIndex = -1;
    
    for (int i = _messages.length - 1; i >= 0; i--) {
      final messageTokens = tokenManager.countTokens(
        '${_messages[i].role}: ${_messages[i].content}'
      );
      
      totalTokens += messageTokens;
      
      if (totalTokens > maxTokens) {
        cutoffIndex = i + 1;
        break;
      }
    }
    
    if (cutoffIndex > 0) {
      _messages.removeRange(0, cutoffIndex);
    }
  }
  
  List<Map<String, String>> getMessages() {
    return _messages.map((m) => {
      'role': m.role,
      'content': m.content,
    }).toList();
  }
  
  String getFormattedContext() {
    return _messages.map((m) => '${m.role}: ${m.content}').join('\n\n');
  }
  
  void clear() {
    _messages.clear();
  }
}

class Message {
  final String role;
  final String content;
  final DateTime timestamp;
  
  Message({
    required this.role,
    required this.content,
    required this.timestamp,
  });
}
```

### 2. Multi-Agent System

```dart
// lib/features/multi_agent_system.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class Agent {
  final String id;
  final String name;
  final String role;
  final Map<String, dynamic> configuration;
  
  Agent({
    required this.id,
    required this.name,
    required this.role,
    required this.configuration,
  });
}

class MultiAgentSystem {
  final FlutterMCP mcp;
  final Map<String, Agent> agents = {};
  
  MultiAgentSystem({required this.mcp});
  
  void registerAgent(Agent agent) {
    agents[agent.id] = agent;
  }
  
  Future<String> executeTask({
    required String task,
    required List<String> agentIds,
  }) async {
    final results = <String, String>{};
    
    // Execute task with each agent
    for (final agentId in agentIds) {
      final agent = agents[agentId];
      if (agent == null) continue;
      
      final result = await mcp.client.callTool(
        serverId: 'gpt-server',
        name: 'agent_execution',
        arguments: {
          'task': task,
          'agent_role': agent.role,
          'agent_config': agent.configuration,
          'context': results,
        },
      );
      
      results[agentId] = result.content.first.text;
    }
    
    // Synthesize results
    final synthesis = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'synthesis',
      arguments: {
        'task': task,
        'agent_results': results,
      },
    );
    
    return synthesis.content.first.text;
  }
  
  Future<String> collaborativeTask({
    required String task,
    required List<String> agentIds,
    int maxRounds = 3,
  }) async {
    var currentState = task;
    
    for (int round = 0; round < maxRounds; round++) {
      for (final agentId in agentIds) {
        final agent = agents[agentId];
        if (agent == null) continue;
        
        final result = await mcp.client.callTool(
          serverId: 'gpt-server',
          name: 'collaborative_step',
          arguments: {
            'current_state': currentState,
            'agent_role': agent.role,
            'agent_config': agent.configuration,
            'round': round,
          },
        );
        
        currentState = result.content.first.text;
      }
    }
    
    return currentState;
  }
}
```

### 3. Code Generation Pipeline

```dart
// lib/features/code_generation_pipeline.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class CodeGenerationPipeline {
  final FlutterMCP mcp;
  
  CodeGenerationPipeline({required this.mcp});
  
  Future<GeneratedCode> generateFullStack({
    required String requirements,
    required String language,
    required String framework,
  }) async {
    // Step 1: Architecture design
    final architecture = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'design_architecture',
      arguments: {
        'requirements': requirements,
        'language': language,
        'framework': framework,
      },
    );
    
    // Step 2: Generate backend code
    final backend = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'generate_backend',
      arguments: {
        'architecture': architecture.content.first.text,
        'language': language,
        'framework': framework,
      },
    );
    
    // Step 3: Generate frontend code
    final frontend = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'generate_frontend',
      arguments: {
        'architecture': architecture.content.first.text,
        'backend_api': backend.content.first.text,
        'framework': 'flutter',
      },
    );
    
    // Step 4: Generate tests
    final tests = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'generate_tests',
      arguments: {
        'backend': backend.content.first.text,
        'frontend': frontend.content.first.text,
        'test_framework': 'jest',
      },
    );
    
    // Step 5: Generate documentation
    final documentation = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'generate_documentation',
      arguments: {
        'architecture': architecture.content.first.text,
        'backend': backend.content.first.text,
        'frontend': frontend.content.first.text,
      },
    );
    
    return GeneratedCode(
      architecture: architecture.content.first.text,
      backend: backend.content.first.text,
      frontend: frontend.content.first.text,
      tests: tests.content.first.text,
      documentation: documentation.content.first.text,
    );
  }
  
  Future<String> optimizeCode({
    required String code,
    required String language,
    required List<String> optimizationGoals,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'optimize_code',
      arguments: {
        'code': code,
        'language': language,
        'goals': optimizationGoals,
      },
    );
    
    return result.content.first.text;
  }
  
  Future<CodeReview> reviewCode({
    required String code,
    required String language,
    required List<String> checkpoints,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'gpt-server',
      name: 'review_code',
      arguments: {
        'code': code,
        'language': language,
        'checkpoints': checkpoints,
      },
    );
    
    return CodeReview.fromJson(jsonDecode(result.content.first.text));
  }
}

class GeneratedCode {
  final String architecture;
  final String backend;
  final String frontend;
  final String tests;
  final String documentation;
  
  GeneratedCode({
    required this.architecture,
    required this.backend,
    required this.frontend,
    required this.tests,
    required this.documentation,
  });
}

class CodeReview {
  final double score;
  final List<Issue> issues;
  final List<Suggestion> suggestions;
  final Map<String, dynamic> metrics;
  
  CodeReview({
    required this.score,
    required this.issues,
    required this.suggestions,
    required this.metrics,
  });
  
  factory CodeReview.fromJson(Map<String, dynamic> json) {
    return CodeReview(
      score: json['score'].toDouble(),
      issues: (json['issues'] as List)
          .map((i) => Issue.fromJson(i))
          .toList(),
      suggestions: (json['suggestions'] as List)
          .map((s) => Suggestion.fromJson(s))
          .toList(),
      metrics: json['metrics'],
    );
  }
}
```

## Troubleshooting

### Common Issues

1. **API Key Issues**
   - Verify API key is valid and has proper permissions
   - Check organization settings if applicable
   - Ensure billing is active

2. **Rate Limiting**
   - Implement exponential backoff
   - Use rate limiter utility
   - Consider upgrading tier

3. **Token Limits**
   - Count tokens before sending
   - Truncate long texts
   - Use conversation memory management

4. **Model Selection**
   - Choose appropriate model for task
   - Consider cost vs performance
   - Use GPT-3.5 for simpler tasks

5. **Function Calling**
   - Ensure function schemas are valid
   - Handle edge cases in function responses
   - Provide clear function descriptions

## See Also

- [Anthropic Claude Integration](/doc/integrations/anthropic-claude.md)
- [Google Gemini Integration](/doc/integrations/google-gemini.md)
- [Local LLM Integration](/doc/integrations/local-llm.md)
- [Security Best Practices](/doc/advanced/security.md)