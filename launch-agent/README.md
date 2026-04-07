# macOS Launch Agent for Nova Tracker

This folder contains the configuration and scripts to run the Nova Tracker server (`server.mjs`) as a background service on macOS. This ensures the server starts automatically whenever you log in and stays running silently without a visible terminal window.

## Contents

- `com.nova.tracker.plist`: The macOS Launch Agent configuration template.
- `setup_macos_service.sh`: A management script to install, uninstall, and check the status of the service.

## Getting Started

### 1. Install & Start
Run the following command to register and start the background service:

```bash
./launch-agent/setup_macos_service.sh install
```

This will:
- Generate the final `.plist` file with absolute paths to your `node` binary and project directory.
- Copy it to `~/Library/LaunchAgents/`.
- Register it with the macOS system (`launchctl`).

### 2. Check Status
To see if the service is correctly running:

```bash
./launch-agent/setup_macos_service.sh status
```

### 3. View Logs
You can see recent server activity and any errors by running:

```bash
./launch-agent/setup_macos_service.sh logs
```

The full log file is located at the repository root: `nova_server.log`.

### 4. Restart
If you've made changes to the server code or configuration and want to apply them:

```bash
./launch-agent/setup_macos_service.sh restart
```

### 5. Uninstall
To stop the background service and remove it from your system:

```bash
./launch-agent/setup_macos_service.sh uninstall
```

## Troubleshooting

- **Permissions**: If the script fails, ensure it is executable: `chmod +x launch-agent/setup_macos_service.sh`.
- **Node Path**: The script uses `which node` to find your Node binary. If you use a version manager like `nvm`, ensure the correct version is active when you run the install command.
- **Port Conflict**: The service defaults to port `1515`. Ensure no other process is using this port.
