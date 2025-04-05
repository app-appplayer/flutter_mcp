# MCP Integration App

A demonstration application for the Flutter MCP (Model Context Protocol) integration package. This app showcases how to use the various components of MCP in a Flutter application.

## Features

- **MCP Integration**: Full integration of MCP Client, Server, and LLM components
- **Chat Interface**: Simple chat interface to interact with LLMs (OpenAI or Claude)
- **Service Management**: Start and stop MCP services dynamically
- **Status Monitoring**: Check the status of all MCP components
- **Cross-Platform**: Supports Android, iOS, macOS, Windows, and Linux

## Getting Started

### Requirements

- Flutter SDK 3.0.0 or higher
- Dart SDK 2.17.0 or higher
- An API key for at least one of:
    - OpenAI (GPT models)
    - Anthropic (Claude models)

### Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/mcp_integration_app.git
   cd mcp_integration_app
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the application:
   ```bash
   flutter run
   ```

### Usage

1. Start the application
2. Enter your API keys (OpenAI and/or Claude)
3. Click "Start" to initialize and start the MCP services
4. Use the chat interface to communicate with the LLM
5. Check service status by clicking the info icon in the app bar
6. Click "Stop" to shut down all MCP services when done

## Architecture

This application demonstrates a complete integration of the MCP ecosystem:

- **MCP Client**: Connects to MCP servers for tools, resources, and prompts
- **MCP Server**: Provides functionalities to LLMs and other clients
- **MCP LLM**: Integrates Large Language Models with the MCP ecosystem
- **Flutter MCP**: Coordinates all components and provides platform features

## Platform Features

The application demonstrates several platform-specific features:

- Background services
- System notifications
- System tray integration (on desktop platforms)
- Secure storage of API keys

## Troubleshooting

- **Services Fail to Start**: Check that you've provided a valid API key and have an internet connection
- **Chat Not Working**: Ensure services are running (status indicator should show "Running")
- **Performance Issues**: Some operations might take time, especially on first run

## License

This project is licensed under the MIT License - see the LICENSE file for details.