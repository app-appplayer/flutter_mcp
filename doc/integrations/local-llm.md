# Local LLM Integration

Complete guide for integrating Flutter MCP with local Large Language Models.

## Overview

This guide demonstrates how to integrate Flutter MCP with local LLMs for:
- Running models on-device without internet
- Privacy-focused AI applications
- Custom fine-tuned models
- Specialized domain models
- Edge computing scenarios

## Supported Models

### Open Source Models
- LLaMA (7B, 13B, 70B)
- Mistral (7B, Mixtral 8x7B)
- Phi-2 and Phi-3
- Gemma (2B, 7B)
- GPT4All models
- GGUF quantized models

### Frameworks
- llama.cpp
- Ollama
- LocalAI
- GPT4All
- MLX (Apple Silicon)
- ONNX Runtime

## Setup

### Dependencies

```yaml
# pubspec.yaml
dependencies:
  flutter_mcp: ^1.0.0
  http: ^1.0.0
  ffi: ^2.0.0
  path_provider: ^2.0.0
```

### Platform-Specific Setup

#### Android
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

```groovy
// android/app/build.gradle
android {
    defaultConfig {
        ndk {
            abiFilters 'arm64-v8a', 'x86_64'
        }
    }
}
```

#### iOS
```xml
<!-- ios/Runner/Info.plist -->
<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
</array>
```

## MCP Server Implementation

### Local LLM MCP Server

```javascript
// server/local-llm-server.js
const { Server } = require('@modelcontextprotocol/sdk/server/index.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const { spawn } = require('child_process');
const axios = require('axios');

class LocalLLMServer {
  constructor(config) {
    this.config = config;
    this.activeModels = new Map();
    
    this.server = new Server({
      name: 'local-llm-server',
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
    this.initializeBackends();
  }
  
  initializeBackends() {
    // Initialize different backends based on config
    if (this.config.ollama) {
      this.ollamaBaseUrl = this.config.ollama.baseUrl || 'http://localhost:11434';
    }
    
    if (this.config.llamaCpp) {
      this.startLlamaCppServer();
    }
    
    if (this.config.localAI) {
      this.localAIBaseUrl = this.config.localAI.baseUrl || 'http://localhost:8080';
    }
  }
  
  setupTools() {
    this.server.setRequestHandler('tools/list', async () => ({
      tools: [
        {
          name: 'load_model',
          description: 'Load a local model into memory',
          inputSchema: {
            type: 'object',
            properties: {
              backend: { type: 'string', enum: ['ollama', 'llamacpp', 'localai', 'gpt4all'] },
              modelName: { type: 'string' },
              modelPath: { type: 'string' },
              parameters: { type: 'object' },
            },
            required: ['backend', 'modelName'],
          },
        },
        {
          name: 'generate_text',
          description: 'Generate text using loaded model',
          inputSchema: {
            type: 'object',
            properties: {
              modelId: { type: 'string' },
              prompt: { type: 'string' },
              temperature: { type: 'number' },
              maxTokens: { type: 'integer' },
              topP: { type: 'number' },
              topK: { type: 'integer' },
              stream: { type: 'boolean' },
            },
            required: ['modelId', 'prompt'],
          },
        },
        {
          name: 'unload_model',
          description: 'Unload model from memory',
          inputSchema: {
            type: 'object',
            properties: {
              modelId: { type: 'string' },
            },
            required: ['modelId'],
          },
        },
        {
          name: 'get_model_info',
          description: 'Get information about loaded model',
          inputSchema: {
            type: 'object',
            properties: {
              modelId: { type: 'string' },
            },
            required: ['modelId'],
          },
        },
      ],
    }));
    
    this.server.setRequestHandler('tools/call', async (request) => {
      const { name, arguments: args } = request.params;
      
      switch (name) {
        case 'load_model':
          return await this.loadModel(args);
          
        case 'generate_text':
          return await this.generateText(args);
          
        case 'unload_model':
          return await this.unloadModel(args);
          
        case 'get_model_info':
          return await this.getModelInfo(args);
          
        default:
          throw new Error(`Unknown tool: ${name}`);
      }
    });
  }
  
  setupPrompts() {
    this.server.setRequestHandler('prompts/list', async () => ({
      prompts: [
        {
          name: 'chat_assistant',
          description: 'General chat assistant prompt',
          arguments: [
            { name: 'model', type: 'string', required: true },
            { name: 'temperature', type: 'number', required: false },
          ],
        },
        {
          name: 'code_completion',
          description: 'Code completion and generation',
          arguments: [
            { name: 'model', type: 'string', required: true },
            { name: 'language', type: 'string', required: true },
          ],
        },
        {
          name: 'summarization',
          description: 'Text summarization',
          arguments: [
            { name: 'model', type: 'string', required: true },
            { name: 'maxLength', type: 'integer', required: false },
          ],
        },
      ],
    }));
    
    this.server.setRequestHandler('prompts/get', async (request) => {
      const { name, arguments: args } = request.params;
      
      const prompts = {
        chat_assistant: {
          messages: [
            {
              role: 'system',
              content: `You are a helpful assistant running on ${args.model}. Temperature: ${args.temperature || 0.7}`,
            },
          ],
        },
        code_completion: {
          messages: [
            {
              role: 'system',
              content: `You are a code assistant specialized in ${args.language} running on ${args.model}.`,
            },
          ],
        },
        summarization: {
          messages: [
            {
              role: 'system',
              content: `You are a summarization assistant running on ${args.model}. Max length: ${args.maxLength || 200} words.`,
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
          uri: 'local://models',
          name: 'Available Local Models',
          description: 'List of available local models',
          mimeType: 'application/json',
        },
        {
          uri: 'local://system',
          name: 'System Information',
          description: 'System resources and capabilities',
          mimeType: 'application/json',
        },
      ],
    }));
    
    this.server.setRequestHandler('resources/read', async (request) => {
      const { uri } = request.params;
      
      if (uri === 'local://models') {
        const models = await this.listAvailableModels();
        return {
          contents: [
            {
              uri,
              mimeType: 'application/json',
              text: JSON.stringify(models),
            },
          ],
        };
      }
      
      if (uri === 'local://system') {
        const systemInfo = await this.getSystemInfo();
        return {
          contents: [
            {
              uri,
              mimeType: 'application/json',
              text: JSON.stringify(systemInfo),
            },
          ],
        };
      }
      
      throw new Error(`Unknown resource: ${uri}`);
    });
  }
  
  async loadModel({ backend, modelName, modelPath, parameters }) {
    const modelId = `${backend}-${modelName}`;
    
    if (this.activeModels.has(modelId)) {
      return {
        content: [
          {
            type: 'text',
            text: `Model ${modelId} already loaded`,
          },
        ],
      };
    }
    
    let model;
    
    switch (backend) {
      case 'ollama':
        model = await this.loadOllamaModel(modelName, parameters);
        break;
        
      case 'llamacpp':
        model = await this.loadLlamaCppModel(modelPath, parameters);
        break;
        
      case 'localai':
        model = await this.loadLocalAIModel(modelName, parameters);
        break;
        
      case 'gpt4all':
        model = await this.loadGPT4AllModel(modelPath, parameters);
        break;
        
      default:
        throw new Error(`Unknown backend: ${backend}`);
    }
    
    this.activeModels.set(modelId, model);
    
    return {
      content: [
        {
          type: 'text',
          text: `Model ${modelId} loaded successfully`,
        },
      ],
    };
  }
  
  async generateText({ modelId, prompt, temperature, maxTokens, topP, topK, stream }) {
    const model = this.activeModels.get(modelId);
    
    if (!model) {
      throw new Error(`Model ${modelId} not loaded`);
    }
    
    const parameters = {
      prompt,
      temperature: temperature || 0.7,
      max_tokens: maxTokens || 512,
      top_p: topP || 0.9,
      top_k: topK || 40,
    };
    
    if (stream) {
      // Return streaming response
      return {
        content: [
          {
            type: 'stream',
            generator: this.generateStream(model, parameters),
          },
        ],
      };
    } else {
      const response = await model.generate(parameters);
      return {
        content: [
          {
            type: 'text',
            text: response,
          },
        ],
      };
    }
  }
  
  async *generateStream(model, parameters) {
    const stream = await model.generateStream(parameters);
    
    for await (const chunk of stream) {
      yield {
        type: 'text',
        text: chunk,
      };
    }
  }
  
  async unloadModel({ modelId }) {
    const model = this.activeModels.get(modelId);
    
    if (!model) {
      throw new Error(`Model ${modelId} not loaded`);
    }
    
    await model.unload();
    this.activeModels.delete(modelId);
    
    return {
      content: [
        {
          type: 'text',
          text: `Model ${modelId} unloaded`,
        },
      ],
    };
  }
  
  async getModelInfo({ modelId }) {
    const model = this.activeModels.get(modelId);
    
    if (!model) {
      throw new Error(`Model ${modelId} not loaded`);
    }
    
    const info = await model.getInfo();
    
    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify(info, null, 2),
        },
      ],
    };
  }
  
  // Backend-specific implementations
  async loadOllamaModel(modelName, parameters) {
    // Check if model exists
    const response = await axios.get(`${this.ollamaBaseUrl}/api/tags`);
    const models = response.data.models;
    
    if (!models.find(m => m.name === modelName)) {
      // Pull model if not exists
      await axios.post(`${this.ollamaBaseUrl}/api/pull`, {
        name: modelName,
      });
    }
    
    return {
      backend: 'ollama',
      modelName,
      generate: async (params) => {
        const response = await axios.post(`${this.ollamaBaseUrl}/api/generate`, {
          model: modelName,
          prompt: params.prompt,
          options: {
            temperature: params.temperature,
            num_predict: params.max_tokens,
            top_p: params.top_p,
            top_k: params.top_k,
          },
          stream: false,
        });
        
        return response.data.response;
      },
      generateStream: async function* (params) {
        const response = await axios.post(`${this.ollamaBaseUrl}/api/generate`, {
          model: modelName,
          prompt: params.prompt,
          options: {
            temperature: params.temperature,
            num_predict: params.max_tokens,
            top_p: params.top_p,
            top_k: params.top_k,
          },
          stream: true,
        }, {
          responseType: 'stream',
        });
        
        for await (const chunk of response.data) {
          const data = JSON.parse(chunk.toString());
          if (data.response) {
            yield data.response;
          }
        }
      },
      unload: async () => {
        // Ollama manages memory automatically
      },
      getInfo: async () => {
        const response = await axios.get(`${this.ollamaBaseUrl}/api/show`, {
          params: { name: modelName },
        });
        return response.data;
      },
    };
  }
  
  async loadLlamaCppModel(modelPath, parameters) {
    const port = 8081 + this.activeModels.size;
    
    // Start llama.cpp server
    const server = spawn(this.config.llamaCpp.serverPath, [
      '-m', modelPath,
      '--port', port.toString(),
      '--threads', (parameters.threads || 4).toString(),
      '--ctx-size', (parameters.contextSize || 2048).toString(),
      '--batch-size', (parameters.batchSize || 512).toString(),
      '--n-gpu-layers', (parameters.gpuLayers || 0).toString(),
    ]);
    
    // Wait for server to start
    await new Promise((resolve) => setTimeout(resolve, 2000));
    
    const baseUrl = `http://localhost:${port}`;
    
    return {
      backend: 'llamacpp',
      modelPath,
      server,
      generate: async (params) => {
        const response = await axios.post(`${baseUrl}/completion`, {
          prompt: params.prompt,
          temperature: params.temperature,
          max_tokens: params.max_tokens,
          top_p: params.top_p,
          top_k: params.top_k,
        });
        
        return response.data.content;
      },
      generateStream: async function* (params) {
        const response = await axios.post(`${baseUrl}/completion`, {
          prompt: params.prompt,
          temperature: params.temperature,
          max_tokens: params.max_tokens,
          top_p: params.top_p,
          top_k: params.top_k,
          stream: true,
        }, {
          responseType: 'stream',
        });
        
        for await (const chunk of response.data) {
          const data = JSON.parse(chunk.toString());
          if (data.content) {
            yield data.content;
          }
        }
      },
      unload: async () => {
        server.kill();
      },
      getInfo: async () => {
        const response = await axios.get(`${baseUrl}/model`);
        return response.data;
      },
    };
  }
  
  async listAvailableModels() {
    const models = [];
    
    // List Ollama models
    if (this.config.ollama) {
      try {
        const response = await axios.get(`${this.ollamaBaseUrl}/api/tags`);
        models.push(...response.data.models.map(m => ({
          backend: 'ollama',
          name: m.name,
          size: m.size,
          modified: m.modified_at,
        })));
      } catch (e) {
        console.error('Failed to list Ollama models:', e);
      }
    }
    
    // List LocalAI models
    if (this.config.localAI) {
      try {
        const response = await axios.get(`${this.localAIBaseUrl}/models`);
        models.push(...response.data.data.map(m => ({
          backend: 'localai',
          name: m.id,
          created: m.created,
        })));
      } catch (e) {
        console.error('Failed to list LocalAI models:', e);
      }
    }
    
    return models;
  }
  
  async getSystemInfo() {
    const os = require('os');
    
    return {
      platform: os.platform(),
      arch: os.arch(),
      cpus: os.cpus().length,
      memory: {
        total: os.totalmem(),
        free: os.freemem(),
      },
      loadAverage: os.loadavg(),
      activeModels: Array.from(this.activeModels.keys()),
    };
  }
  
  async start() {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('Local LLM MCP Server started');
  }
}

// Start server
const config = {
  ollama: {
    baseUrl: process.env.OLLAMA_BASE_URL || 'http://localhost:11434',
  },
  llamaCpp: {
    serverPath: process.env.LLAMA_CPP_SERVER || './server',
  },
  localAI: {
    baseUrl: process.env.LOCAL_AI_BASE_URL || 'http://localhost:8080',
  },
};

const server = new LocalLLMServer(config);
server.start().catch(console.error);
```

## Flutter Integration

### Local LLM Client

```dart
// lib/local_llm_client.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:io';
import 'dart:async';

class LocalLLMClient extends StatefulWidget {
  const LocalLLMClient({Key? key}) : super(key: key);

  @override
  State<LocalLLMClient> createState() => _LocalLLMClientState();
}

class _LocalLLMClientState extends State<LocalLLMClient> {
  final _mcp = FlutterMCP();
  final _promptController = TextEditingController();
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _selectedModel;
  List<LocalModel> _availableModels = [];
  
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
            id: 'local-llm',
            command: 'node',
            args: ['local-llm-server.js'],
          ),
        ],
      ),
    );
    
    await _loadAvailableModels();
  }
  
  Future<void> _loadAvailableModels() async {
    try {
      final resource = await _mcp.client.readResource(
        serverId: 'local-llm',
        uri: 'local://models',
      );
      
      final models = jsonDecode(resource.contents.first.text) as List;
      setState(() {
        _availableModels = models.map((m) => LocalModel.fromJson(m)).toList();
      });
    } catch (e) {
      print('Failed to load models: $e');
    }
  }
  
  Future<void> _loadModel(LocalModel model) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      await _mcp.client.callTool(
        serverId: 'local-llm',
        name: 'load_model',
        arguments: {
          'backend': model.backend,
          'modelName': model.name,
        },
      );
      
      setState(() {
        _selectedModel = '${model.backend}-${model.name}';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model ${model.name} loaded')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load model: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _sendMessage() async {
    if (_selectedModel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a model first')),
      );
      return;
    }
    
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    
    setState(() {
      _messages.add(ChatMessage(
        text: prompt,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _promptController.clear();
      _isLoading = true;
    });
    
    try {
      // Stream the response
      final stream = _mcp.client.streamTool(
        serverId: 'local-llm',
        name: 'generate_text',
        arguments: {
          'modelId': _selectedModel,
          'prompt': prompt,
          'temperature': 0.7,
          'maxTokens': 512,
          'stream': true,
        },
      );
      
      String response = '';
      setState(() {
        _messages.add(ChatMessage(
          text: '',
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
      
      await for (final chunk in stream) {
        response += chunk.content.first.text;
        setState(() {
          _messages.last = ChatMessage(
            text: response,
            isUser: false,
            timestamp: _messages.last.timestamp,
          );
        });
      }
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local LLM Chat'),
        actions: [
          PopupMenuButton<LocalModel>(
            icon: const Icon(Icons.model_training),
            enabled: !_isLoading,
            itemBuilder: (context) => _availableModels.map((model) {
              final modelId = '${model.backend}-${model.name}';
              return PopupMenuItem(
                value: model,
                child: ListTile(
                  title: Text(model.name),
                  subtitle: Text(model.backend),
                  trailing: _selectedModel == modelId
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                ),
              );
            }).toList(),
            onSelected: _loadModel,
          ),
          IconButton(
            icon: const Icon(Icons.info),
            onPressed: _showSystemInfo,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_selectedModel != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              child: Row(
                children: [
                  const Icon(Icons.memory, size: 16),
                  const SizedBox(width: 8),
                  Text('Model: $_selectedModel'),
                ],
              ),
            ),
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
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promptController,
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
  
  Future<void> _showSystemInfo() async {
    try {
      final resource = await _mcp.client.readResource(
        serverId: 'local-llm',
        uri: 'local://system',
      );
      
      final info = jsonDecode(resource.contents.first.text);
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('System Information'),
          content: SingleChildScrollView(
            child: Text(
              const JsonEncoder.withIndent('  ').convert(info),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get system info: $e')),
      );
    }
  }
  
  @override
  void dispose() {
    _promptController.dispose();
    _mcp.dispose();
    super.dispose();
  }
}

class LocalModel {
  final String backend;
  final String name;
  final int? size;
  final String? modified;
  
  LocalModel({
    required this.backend,
    required this.name,
    this.size,
    this.modified,
  });
  
  factory LocalModel.fromJson(Map<String, dynamic> json) {
    return LocalModel(
      backend: json['backend'],
      name: json['name'],
      size: json['size'],
      modified: json['modified'],
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
        child: SelectableText(message.text),
      ),
    );
  }
}
```

### Advanced Local LLM Features

```dart
// lib/local_llm_advanced.dart
import 'package:flutter_mcp/flutter_mcp.dart';
import 'dart:io';
import 'dart:typed_data';

class LocalLLMAdvanced {
  final FlutterMCP mcp;
  
  LocalLLMAdvanced({required this.mcp});
  
  // Model management
  Future<ModelInfo> getModelInfo(String modelId) async {
    final result = await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'get_model_info',
      arguments: {'modelId': modelId},
    );
    
    return ModelInfo.fromJson(jsonDecode(result.content.first.text));
  }
  
  Future<void> unloadModel(String modelId) async {
    await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'unload_model',
      arguments: {'modelId': modelId},
    );
  }
  
  // Batch processing
  Future<List<String>> batchGenerate({
    required String modelId,
    required List<String> prompts,
    Map<String, dynamic>? parameters,
  }) async {
    final results = <String>[];
    
    for (final prompt in prompts) {
      final result = await mcp.client.callTool(
        serverId: 'local-llm',
        name: 'generate_text',
        arguments: {
          'modelId': modelId,
          'prompt': prompt,
          ...?parameters,
        },
      );
      
      results.add(result.content.first.text);
    }
    
    return results;
  }
  
  // Custom model loading with quantization
  Future<void> loadQuantizedModel({
    required String modelPath,
    required int quantizationBits,
    Map<String, dynamic>? parameters,
  }) async {
    await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'load_model',
      arguments: {
        'backend': 'llamacpp',
        'modelName': path.basename(modelPath),
        'modelPath': modelPath,
        'parameters': {
          'quantization': quantizationBits,
          ...?parameters,
        },
      },
    );
  }
  
  // Fine-tuning support
  Future<String> fineTuneModel({
    required String baseModel,
    required String trainingData,
    required Map<String, dynamic> hyperparameters,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'fine_tune',
      arguments: {
        'baseModel': baseModel,
        'trainingData': trainingData,
        'hyperparameters': hyperparameters,
      },
    );
    
    return result.content.first.text; // Returns fine-tuned model ID
  }
  
  // Context management
  Future<String> generateWithContext({
    required String modelId,
    required String prompt,
    required List<String> contextDocuments,
    Map<String, dynamic>? parameters,
  }) async {
    final context = contextDocuments.join('\n\n');
    final fullPrompt = '''Context:
$context

Question: $prompt

Answer:''';
    
    final result = await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'generate_text',
      arguments: {
        'modelId': modelId,
        'prompt': fullPrompt,
        ...?parameters,
      },
    );
    
    return result.content.first.text;
  }
}

class ModelInfo {
  final String id;
  final String backend;
  final String name;
  final int contextSize;
  final int vocabSize;
  final Map<String, dynamic> parameters;
  final Map<String, dynamic> capabilities;
  
  ModelInfo({
    required this.id,
    required this.backend,
    required this.name,
    required this.contextSize,
    required this.vocabSize,
    required this.parameters,
    required this.capabilities,
  });
  
  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'],
      backend: json['backend'],
      name: json['name'],
      contextSize: json['contextSize'],
      vocabSize: json['vocabSize'],
      parameters: json['parameters'],
      capabilities: json['capabilities'],
    );
  }
}
```

### Platform-Specific Implementations

#### Android Integration

```dart
// lib/platform/android_llm.dart
import 'package:flutter/services.dart';
import 'dart:io';

class AndroidLLM {
  static const platform = MethodChannel('com.example.flutter_mcp/llm');
  
  // Load model using Android's Neural Networks API
  static Future<void> loadModelNNAPI(String modelPath) async {
    try {
      await platform.invokeMethod('loadModelNNAPI', {
        'modelPath': modelPath,
      });
    } on PlatformException catch (e) {
      print('Failed to load model: ${e.message}');
    }
  }
  
  // Use GPU acceleration if available
  static Future<bool> enableGPUAcceleration() async {
    try {
      return await platform.invokeMethod('enableGPU');
    } on PlatformException {
      return false;
    }
  }
}
```

```java
// android/app/src/main/java/com/example/flutter_mcp/LLMPlugin.java
package com.example.flutter_mcp;

import android.os.Build;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class LLMPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    
    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(
            binding.getBinaryMessenger(),
            "com.example.flutter_mcp/llm"
        );
        channel.setMethodCallHandler(this);
    }
    
    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (call.method.equals("loadModelNNAPI")) {
            String modelPath = call.argument("modelPath");
            loadModelWithNNAPI(modelPath, result);
        } else if (call.method.equals("enableGPU")) {
            result.success(enableGPUIfAvailable());
        } else {
            result.notImplemented();
        }
    }
    
    private void loadModelWithNNAPI(String modelPath, MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // Android Neural Networks API implementation
            try {
                // Load model using NNAPI
                result.success(null);
            } catch (Exception e) {
                result.error("MODEL_LOAD_ERROR", e.getMessage(), null);
            }
        } else {
            result.error("UNSUPPORTED", "NNAPI requires Android P or higher", null);
        }
    }
    
    private boolean enableGPUIfAvailable() {
        // Check for GPU support
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.P;
    }
}
```

#### iOS Integration

```dart
// lib/platform/ios_llm.dart
import 'package:flutter/services.dart';

class iOSLLM {
  static const platform = MethodChannel('com.example.flutter_mcp/llm');
  
  // Load model using Core ML
  static Future<void> loadModelCoreML(String modelPath) async {
    try {
      await platform.invokeMethod('loadModelCoreML', {
        'modelPath': modelPath,
      });
    } on PlatformException catch (e) {
      print('Failed to load model: ${e.message}');
    }
  }
  
  // Use Metal Performance Shaders for acceleration
  static Future<bool> enableMetalAcceleration() async {
    try {
      return await platform.invokeMethod('enableMetal');
    } on PlatformException {
      return false;
    }
  }
}
```

```swift
// ios/Runner/LLMPlugin.swift
import Flutter
import CoreML
import Metal

@available(iOS 11.0, *)
public class LLMPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.example.flutter_mcp/llm",
            binaryMessenger: registrar.messenger()
        )
        let instance = LLMPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModelCoreML":
            if let args = call.arguments as? [String: Any],
               let modelPath = args["modelPath"] as? String {
                loadCoreMLModel(modelPath: modelPath, result: result)
            }
        case "enableMetal":
            result(enableMetalIfAvailable())
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func loadCoreMLModel(modelPath: String, result: FlutterResult) {
        guard #available(iOS 11.0, *) else {
            result(FlutterError(
                code: "UNSUPPORTED",
                message: "Core ML requires iOS 11.0+",
                details: nil
            ))
            return
        }
        
        do {
            let modelURL = URL(fileURLWithPath: modelPath)
            let model = try MLModel(contentsOf: modelURL)
            // Store model reference
            result(nil)
        } catch {
            result(FlutterError(
                code: "MODEL_LOAD_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }
    
    private func enableMetalIfAvailable() -> Bool {
        guard #available(iOS 8.0, *) else { return false }
        return MTLCreateSystemDefaultDevice() != nil
    }
}
```

### Model Optimization

```dart
// lib/optimization/model_optimizer.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class ModelOptimizer {
  final FlutterMCP mcp;
  
  ModelOptimizer({required this.mcp});
  
  // Quantize model for smaller size and faster inference
  Future<String> quantizeModel({
    required String modelPath,
    required QuantizationType type,
    Map<String, dynamic>? options,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'quantize_model',
      arguments: {
        'modelPath': modelPath,
        'quantization': type.toString(),
        'options': options,
      },
    );
    
    return result.content.first.text; // Returns quantized model path
  }
  
  // Optimize for mobile deployment
  Future<OptimizationResult> optimizeForMobile({
    required String modelPath,
    required TargetPlatform platform,
    required DeviceCapabilities capabilities,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'optimize_mobile',
      arguments: {
        'modelPath': modelPath,
        'platform': platform.toString(),
        'capabilities': capabilities.toJson(),
      },
    );
    
    return OptimizationResult.fromJson(
      jsonDecode(result.content.first.text),
    );
  }
  
  // Prune model to reduce size
  Future<String> pruneModel({
    required String modelPath,
    required double sparsityTarget,
    List<String>? layersToPreserve,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'prune_model',
      arguments: {
        'modelPath': modelPath,
        'sparsity': sparsityTarget,
        'preserveLayers': layersToPreserve,
      },
    );
    
    return result.content.first.text; // Returns pruned model path
  }
  
  // Benchmark model performance
  Future<BenchmarkResult> benchmarkModel({
    required String modelId,
    required List<String> testPrompts,
    int runs = 5,
  }) async {
    final result = await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'benchmark',
      arguments: {
        'modelId': modelId,
        'prompts': testPrompts,
        'runs': runs,
      },
    );
    
    return BenchmarkResult.fromJson(
      jsonDecode(result.content.first.text),
    );
  }
}

enum QuantizationType {
  int8,
  int4,
  fp16,
  dynamic,
}

enum TargetPlatform {
  android,
  ios,
  desktop,
}

class DeviceCapabilities {
  final bool hasGPU;
  final bool hasNPU;
  final int availableRAM;
  final int availableStorage;
  final String cpuArchitecture;
  
  DeviceCapabilities({
    required this.hasGPU,
    required this.hasNPU,
    required this.availableRAM,
    required this.availableStorage,
    required this.cpuArchitecture,
  });
  
  Map<String, dynamic> toJson() => {
    'hasGPU': hasGPU,
    'hasNPU': hasNPU,
    'availableRAM': availableRAM,
    'availableStorage': availableStorage,
    'cpuArchitecture': cpuArchitecture,
  };
}

class OptimizationResult {
  final String optimizedModelPath;
  final double compressionRatio;
  final double speedupFactor;
  final Map<String, dynamic> metrics;
  
  OptimizationResult({
    required this.optimizedModelPath,
    required this.compressionRatio,
    required this.speedupFactor,
    required this.metrics,
  });
  
  factory OptimizationResult.fromJson(Map<String, dynamic> json) {
    return OptimizationResult(
      optimizedModelPath: json['optimizedModelPath'],
      compressionRatio: json['compressionRatio'],
      speedupFactor: json['speedupFactor'],
      metrics: json['metrics'],
    );
  }
}

class BenchmarkResult {
  final double averageLatency;
  final double throughput;
  final double memoryUsage;
  final Map<String, double> percentiles;
  
  BenchmarkResult({
    required this.averageLatency,
    required this.throughput,
    required this.memoryUsage,
    required this.percentiles,
  });
  
  factory BenchmarkResult.fromJson(Map<String, dynamic> json) {
    return BenchmarkResult(
      averageLatency: json['averageLatency'],
      throughput: json['throughput'],
      memoryUsage: json['memoryUsage'],
      percentiles: Map<String, double>.from(json['percentiles']),
    );
  }
}
```

## Configuration

### Backend Configuration

```dart
// lib/config/local_llm_config.dart
class LocalLLMConfig {
  static const Map<String, dynamic> backends = {
    'ollama': {
      'baseUrl': 'http://localhost:11434',
      'defaultModels': [
        'llama3:8b',
        'mistral:7b',
        'phi3:mini',
        'gemma:2b',
      ],
    },
    'llamacpp': {
      'serverPath': './llama.cpp/server',
      'defaultParams': {
        'threads': 4,
        'contextSize': 2048,
        'batchSize': 512,
      },
    },
    'localai': {
      'baseUrl': 'http://localhost:8080',
      'modelsPath': './models',
    },
    'gpt4all': {
      'modelsPath': '~/.gpt4all/models',
      'defaultModel': 'ggml-gpt4all-j-v1.3-groovy.bin',
    },
  };
  
  static Map<String, dynamic> getBackendConfig(String backend) {
    return backends[backend] ?? {};
  }
  
  static List<String> getDefaultModels(String backend) {
    final config = getBackendConfig(backend);
    return config['defaultModels'] ?? [];
  }
}
```

### Model Registry

```dart
// lib/config/model_registry.dart
class ModelRegistry {
  static const Map<String, ModelSpec> models = {
    'llama3-8b': ModelSpec(
      name: 'LLaMA 3 8B',
      size: '8B parameters',
      quantizations: ['Q4_K_M', 'Q5_K_S', 'Q8_0'],
      contextSize: 8192,
      requirements: ModelRequirements(
        minRAM: 6000, // MB
        minStorage: 4500, // MB
        gpu: false,
      ),
    ),
    'mistral-7b': ModelSpec(
      name: 'Mistral 7B',
      size: '7B parameters',
      quantizations: ['Q4_K_M', 'Q5_K_S', 'Q8_0'],
      contextSize: 32768,
      requirements: ModelRequirements(
        minRAM: 5000,
        minStorage: 4000,
        gpu: false,
      ),
    ),
    'phi3-mini': ModelSpec(
      name: 'Phi-3 Mini',
      size: '3.8B parameters',
      quantizations: ['Q4_K_M', 'Q5_K_S'],
      contextSize: 4096,
      requirements: ModelRequirements(
        minRAM: 2500,
        minStorage: 2000,
        gpu: false,
      ),
    ),
  };
  
  static ModelSpec? getModelSpec(String modelId) {
    return models[modelId];
  }
  
  static List<ModelSpec> getCompatibleModels(DeviceCapabilities device) {
    return models.values.where((spec) {
      return spec.requirements.minRAM <= device.availableRAM &&
             spec.requirements.minStorage <= device.availableStorage &&
             (!spec.requirements.gpu || device.hasGPU);
    }).toList();
  }
}

class ModelSpec {
  final String name;
  final String size;
  final List<String> quantizations;
  final int contextSize;
  final ModelRequirements requirements;
  
  const ModelSpec({
    required this.name,
    required this.size,
    required this.quantizations,
    required this.contextSize,
    required this.requirements,
  });
}

class ModelRequirements {
  final int minRAM;
  final int minStorage;
  final bool gpu;
  
  const ModelRequirements({
    required this.minRAM,
    required this.minStorage,
    required this.gpu,
  });
}
```

## Best Practices

### 1. Memory Management

```dart
// lib/utils/memory_manager.dart
import 'dart:io';

class LocalLLMMemoryManager {
  static int _currentMemoryUsage = 0;
  static final Map<String, int> _modelMemoryUsage = {};
  
  static Future<bool> canLoadModel(String modelId, int estimatedSize) async {
    final availableMemory = await getAvailableMemory();
    final projectedUsage = _currentMemoryUsage + estimatedSize;
    
    return projectedUsage < availableMemory * 0.8; // Keep 20% buffer
  }
  
  static void trackModelLoad(String modelId, int memoryUsage) {
    _modelMemoryUsage[modelId] = memoryUsage;
    _currentMemoryUsage += memoryUsage;
  }
  
  static void trackModelUnload(String modelId) {
    final usage = _modelMemoryUsage.remove(modelId);
    if (usage != null) {
      _currentMemoryUsage -= usage;
    }
  }
  
  static Future<int> getAvailableMemory() async {
    if (Platform.isAndroid) {
      // Android-specific memory check
      try {
        final info = await Process.run('cat', ['/proc/meminfo']);
        final lines = info.stdout.toString().split('\n');
        final memAvailable = lines.firstWhere(
          (line) => line.startsWith('MemAvailable:'),
        );
        final match = RegExp(r'(\d+)').firstMatch(memAvailable);
        if (match != null) {
          return int.parse(match.group(1)!) ~/ 1024; // Convert to MB
        }
      } catch (e) {
        print('Failed to get memory info: $e');
      }
    } else if (Platform.isIOS) {
      // iOS memory check would use platform channel
    }
    
    // Fallback estimate
    return 2048; // 2GB default
  }
  
  static Future<void> optimizeMemory() async {
    // Unload least recently used models if memory is low
    final availableMemory = await getAvailableMemory();
    final memoryThreshold = availableMemory * 0.2; // 20% threshold
    
    if (_currentMemoryUsage > availableMemory - memoryThreshold) {
      // Implement LRU eviction
      print('Memory optimization needed');
    }
  }
}
```

### 2. Performance Optimization

```dart
// lib/utils/performance_optimizer.dart
class LocalLLMPerformanceOptimizer {
  static const Map<String, dynamic> platformOptimizations = {
    'android': {
      'useGPU': true,
      'useNNAPI': true,
      'threadCount': 4,
      'cpuAffinity': [4, 5, 6, 7], // Big cores
    },
    'ios': {
      'useMetal': true,
      'useCoreML': true,
      'useNeuralEngine': true,
      'threadCount': 6,
    },
    'desktop': {
      'useGPU': true,
      'threadCount': 8,
      'vectorExtensions': ['AVX2', 'AVX512'],
    },
  };
  
  static Map<String, dynamic> getOptimalSettings(
    TargetPlatform platform,
    DeviceCapabilities device,
  ) {
    final baseSettings = platformOptimizations[platform.toString()] ?? {};
    
    // Adjust based on device capabilities
    if (!device.hasGPU) {
      baseSettings['useGPU'] = false;
      baseSettings['useMetal'] = false;
    }
    
    if (device.availableRAM < 4096) {
      baseSettings['threadCount'] = 2;
      baseSettings['batchSize'] = 256;
    }
    
    return baseSettings;
  }
  
  static Future<void> warmupModel(
    FlutterMCP mcp,
    String modelId,
  ) async {
    // Warm up model with dummy inference
    const warmupPrompt = 'Hello, this is a warmup prompt.';
    
    await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'generate_text',
      arguments: {
        'modelId': modelId,
        'prompt': warmupPrompt,
        'maxTokens': 10,
      },
    );
  }
  
  static Future<void> optimizeBatching(
    List<String> prompts,
    int batchSize,
  ) async {
    // Group prompts into optimal batches
    final batches = <List<String>>[];
    
    for (int i = 0; i < prompts.length; i += batchSize) {
      final end = (i + batchSize < prompts.length) 
          ? i + batchSize 
          : prompts.length;
      batches.add(prompts.sublist(i, end));
    }
    
    // Process batches in parallel when possible
    await Future.wait(
      batches.map((batch) => processBatch(batch)),
    );
  }
  
  static Future<void> processBatch(List<String> batch) async {
    // Batch processing implementation
  }
}
```

### 3. Error Handling

```dart
// lib/utils/error_handler.dart
class LocalLLMErrorHandler {
  static Future<T> handleWithRetry<T>({
    required Future<T> Function() operation,
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
  }) async {
    int attempt = 0;
    
    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        
        if (e is ModelNotLoadedError) {
          // Try to reload model
          await reloadModel(e.modelId);
        } else if (e is OutOfMemoryError) {
          // Free up memory and retry
          await freeMemory();
        } else if (e is ConnectionError) {
          // Check backend status
          await checkBackendStatus();
        }
        
        if (attempt >= maxRetries) {
          rethrow;
        }
        
        await Future.delayed(delay * attempt);
      }
    }
    
    throw Exception('Operation failed after $maxRetries attempts');
  }
  
  static Future<void> reloadModel(String modelId) async {
    // Reload model implementation
  }
  
  static Future<void> freeMemory() async {
    // Memory cleanup implementation
  }
  
  static Future<void> checkBackendStatus() async {
    // Backend health check implementation
  }
}

class ModelNotLoadedError extends Error {
  final String modelId;
  ModelNotLoadedError(this.modelId);
}

class OutOfMemoryError extends Error {
  final int requiredMemory;
  final int availableMemory;
  
  OutOfMemoryError({
    required this.requiredMemory,
    required this.availableMemory,
  });
}

class ConnectionError extends Error {
  final String backend;
  final String message;
  
  ConnectionError({
    required this.backend,
    required this.message,
  });
}
```

## Advanced Use Cases

### 1. Privacy-Focused Assistant

```dart
// lib/features/privacy_assistant.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class PrivacyAssistant {
  final FlutterMCP mcp;
  final LocalLLMAdvanced llm;
  
  PrivacyAssistant({required this.mcp})
      : llm = LocalLLMAdvanced(mcp: mcp);
  
  Future<String> processPrivateData({
    required String data,
    required String task,
    required String modelId,
  }) async {
    // Ensure model is loaded locally
    await _ensureLocalModel(modelId);
    
    // Disable any network connections
    await _disableNetworking();
    
    try {
      // Process data entirely offline
      final result = await llm.generateWithContext(
        modelId: modelId,
        prompt: task,
        contextDocuments: [data],
        parameters: {
          'temperature': 0.3, // Lower temperature for consistency
          'maxTokens': 1000,
        },
      );
      
      // Sanitize output
      return _sanitizeOutput(result);
    } finally {
      // Re-enable networking
      await _enableNetworking();
    }
  }
  
  Future<void> _ensureLocalModel(String modelId) async {
    final info = await llm.getModelInfo(modelId);
    if (info.backend != 'local') {
      throw Exception('Model must be local for privacy mode');
    }
  }
  
  Future<void> _disableNetworking() async {
    // Platform-specific network disabling
  }
  
  Future<void> _enableNetworking() async {
    // Re-enable network connections
  }
  
  String _sanitizeOutput(String output) {
    // Remove any potential PII or sensitive data
    return output
        .replaceAll(RegExp(r'\b\d{3}-\d{2}-\d{4}\b'), '[SSN]')
        .replaceAll(RegExp(r'\b\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\b'), '[CC]')
        .replaceAll(RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'), '[EMAIL]');
  }
}
```

### 2. Domain-Specific Models

```dart
// lib/features/domain_specific.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class DomainSpecificLLM {
  final FlutterMCP mcp;
  final Map<String, String> domainModels = {
    'medical': 'local-llm-medical-llama-7b',
    'legal': 'local-llm-legal-bert',
    'finance': 'local-llm-finance-gpt',
    'code': 'local-llm-codellama-7b',
  };
  
  DomainSpecificLLM({required this.mcp});
  
  Future<String> queryDomain({
    required String domain,
    required String query,
    Map<String, dynamic>? context,
  }) async {
    final modelId = domainModels[domain];
    if (modelId == null) {
      throw Exception('Unsupported domain: $domain');
    }
    
    // Load domain-specific model
    await _loadDomainModel(modelId);
    
    // Create domain-specific prompt
    final prompt = _createDomainPrompt(domain, query, context);
    
    // Generate response with domain constraints
    final result = await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'generate_text',
      arguments: {
        'modelId': modelId,
        'prompt': prompt,
        'temperature': 0.3,
        'maxTokens': 500,
        'constraints': _getDomainConstraints(domain),
      },
    );
    
    return _processDomainResponse(domain, result.content.first.text);
  }
  
  Future<void> _loadDomainModel(String modelId) async {
    await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'load_model',
      arguments: {
        'backend': 'ollama',
        'modelName': modelId,
        'parameters': {
          'mlock': true, // Lock model in memory
          'numa': true,  // NUMA optimization
        },
      },
    );
  }
  
  String _createDomainPrompt(
    String domain,
    String query,
    Map<String, dynamic>? context,
  ) {
    final prompts = {
      'medical': '''You are a medical AI assistant. Provide accurate, evidence-based medical information.
IMPORTANT: Always recommend consulting with healthcare professionals for medical advice.

Context: ${context ?? ''}
Query: $query''',
      
      'legal': '''You are a legal AI assistant. Provide general legal information only.
IMPORTANT: This is not legal advice. Consult with a qualified attorney for legal matters.

Context: ${context ?? ''}
Query: $query''',
      
      'finance': '''You are a financial AI assistant. Provide general financial information.
IMPORTANT: This is not financial advice. Consult with a financial advisor for investment decisions.

Context: ${context ?? ''}
Query: $query''',
      
      'code': '''You are a code assistant. Provide accurate code examples and explanations.

Context: ${context ?? ''}
Query: $query''',
    };
    
    return prompts[domain] ?? query;
  }
  
  Map<String, dynamic> _getDomainConstraints(String domain) {
    final constraints = {
      'medical': {
        'forbidden_terms': ['cure', 'guaranteed', 'miracle'],
        'required_disclaimer': true,
      },
      'legal': {
        'forbidden_terms': ['legal advice', 'you should sue'],
        'required_disclaimer': true,
      },
      'finance': {
        'forbidden_terms': ['guaranteed returns', 'risk-free'],
        'required_disclaimer': true,
      },
      'code': {
        'enforce_syntax': true,
        'validate_security': true,
      },
    };
    
    return constraints[domain] ?? {};
  }
  
  String _processDomainResponse(String domain, String response) {
    // Add domain-specific disclaimers
    final disclaimers = {
      'medical': '\n\n*This information is for educational purposes only and is not a substitute for professional medical advice.*',
      'legal': '\n\n*This information is for educational purposes only and is not legal advice.*',
      'finance': '\n\n*This information is for educational purposes only and is not financial advice.*',
    };
    
    final disclaimer = disclaimers[domain] ?? '';
    return response + disclaimer;
  }
}
```

### 3. Federated Learning

```dart
// lib/features/federated_learning.dart
import 'package:flutter_mcp/flutter_mcp.dart';

class FederatedLearning {
  final FlutterMCP mcp;
  final String modelId;
  
  FederatedLearning({
    required this.mcp,
    required this.modelId,
  });
  
  // Participate in federated learning
  Future<void> participateInTraining({
    required List<TrainingExample> localData,
    required FederationConfig config,
  }) async {
    // Train on local data
    final localUpdate = await _trainLocally(localData);
    
    // Apply differential privacy
    final privateUpdate = await _applyDifferentialPrivacy(
      localUpdate,
      config.privacyBudget,
    );
    
    // Send update to aggregation server
    await _sendUpdate(privateUpdate, config.aggregatorUrl);
    
    // Receive global model update
    final globalUpdate = await _receiveGlobalUpdate(config.aggregatorUrl);
    
    // Update local model
    await _updateLocalModel(globalUpdate);
  }
  
  Future<ModelUpdate> _trainLocally(List<TrainingExample> data) async {
    final result = await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'train_local',
      arguments: {
        'modelId': modelId,
        'trainingData': data.map((e) => e.toJson()).toList(),
        'epochs': 3,
        'batchSize': 8,
      },
    );
    
    return ModelUpdate.fromJson(jsonDecode(result.content.first.text));
  }
  
  Future<ModelUpdate> _applyDifferentialPrivacy(
    ModelUpdate update,
    double privacyBudget,
  ) async {
    final result = await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'apply_dp',
      arguments: {
        'update': update.toJson(),
        'epsilon': privacyBudget,
        'delta': 1e-5,
      },
    );
    
    return ModelUpdate.fromJson(jsonDecode(result.content.first.text));
  }
  
  Future<void> _sendUpdate(
    ModelUpdate update,
    String aggregatorUrl,
  ) async {
    // Send update to federated learning aggregator
    // This would typically use secure aggregation protocols
  }
  
  Future<ModelUpdate> _receiveGlobalUpdate(String aggregatorUrl) async {
    // Receive aggregated model update
    // This would include verification of the aggregation
    return ModelUpdate(weights: {}, metrics: {});
  }
  
  Future<void> _updateLocalModel(ModelUpdate update) async {
    await mcp.client.callTool(
      serverId: 'local-llm',
      name: 'apply_update',
      arguments: {
        'modelId': modelId,
        'update': update.toJson(),
      },
    );
  }
}

class TrainingExample {
  final String input;
  final String output;
  final Map<String, dynamic>? metadata;
  
  TrainingExample({
    required this.input,
    required this.output,
    this.metadata,
  });
  
  Map<String, dynamic> toJson() => {
    'input': input,
    'output': output,
    if (metadata != null) 'metadata': metadata,
  };
}

class ModelUpdate {
  final Map<String, dynamic> weights;
  final Map<String, double> metrics;
  
  ModelUpdate({
    required this.weights,
    required this.metrics,
  });
  
  factory ModelUpdate.fromJson(Map<String, dynamic> json) {
    return ModelUpdate(
      weights: json['weights'],
      metrics: Map<String, double>.from(json['metrics']),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'weights': weights,
    'metrics': metrics,
  };
}

class FederationConfig {
  final String aggregatorUrl;
  final double privacyBudget;
  final int minParticipants;
  final Duration roundDuration;
  
  FederationConfig({
    required this.aggregatorUrl,
    required this.privacyBudget,
    required this.minParticipants,
    required this.roundDuration,
  });
}
```

## Troubleshooting

### Common Issues

1. **Model Loading Failures**
   - Check model file exists and is accessible
   - Verify sufficient memory available
   - Ensure backend is running
   - Check model format compatibility

2. **Performance Issues**
   - Enable GPU acceleration if available
   - Use quantized models for better performance
   - Adjust thread count based on CPU
   - Implement proper batching

3. **Memory Problems**
   - Monitor memory usage
   - Unload unused models
   - Use smaller quantized versions
   - Implement memory limits

4. **Platform-Specific Issues**
   - Android: Check NNAPI compatibility
   - iOS: Verify Core ML support
   - Desktop: Install required dependencies
   - Check architecture compatibility

5. **Backend Connection Issues**
   - Verify backend is running
   - Check port availability
   - Ensure firewall permissions
   - Test with curl or similar tools

## See Also

- [Anthropic Claude Integration](/doc/integrations/anthropic-claude.md)
- [OpenAI GPT Integration](/doc/integrations/openai-gpt.md)
- [Google Gemini Integration](/doc/integrations/google-gemini.md)
- [Security Best Practices](/doc/advanced/security.md)