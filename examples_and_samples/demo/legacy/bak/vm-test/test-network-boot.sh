#!/bin/bash

# PhoenixGuard Network Boot Test
echo "🌐 Starting PhoenixGuard Network Boot Test..."

VM_DIR="$(dirname "$0")"
cd "$VM_DIR"

# Start a simple HTTP server for testing
echo "🚀 Starting test HTTP server on port 8000..."

# Create test boot files
mkdir -p boot-server/api/v1/boot/ubuntu/latest

# Create dummy kernel and initrd for testing
echo "Test kernel content" > boot-server/api/v1/boot/ubuntu/latest/kernel
echo "Test initrd content" > boot-server/api/v1/boot/ubuntu/latest/initrd

# Create index page
cat > boot-server/index.html << 'BOOTEOF'
<!DOCTYPE html>
<html>
<head>
    <title>PhoenixGuard CloudBoot Test Server</title>
</head>
<body>
    <h1>🔥 PhoenixGuard CloudBoot Test Server 🔥</h1>
    <p>This is a test server for PhoenixGuard HTTPS-only boot.</p>
    <h2>Available Endpoints:</h2>
    <ul>
        <li><a href="/api/v1/boot/ubuntu/latest/kernel">Ubuntu Latest Kernel</a></li>
        <li><a href="/api/v1/boot/ubuntu/latest/initrd">Ubuntu Latest InitRD</a></li>
    </ul>
    <p><strong>Note:</strong> This is a test server. In production, use HTTPS with proper certificates.</p>
</body>
</html>
BOOTEOF

# Start Python HTTP server in background
cd boot-server
echo "📡 Starting HTTP server at http://localhost:8000"
python3 -m http.server 8000 &
SERVER_PID=$!
cd ..

echo "🌐 Test server started (PID: $SERVER_PID)"
echo "📡 You can test endpoints:"
echo "   http://localhost:8000/api/v1/boot/ubuntu/latest/kernel"
echo "   http://localhost:8000/api/v1/boot/ubuntu/latest/initrd"
echo ""
echo "Press Ctrl+C to stop the server"

# Keep server running
trap "echo '🛑 Stopping server...'; kill $SERVER_PID 2>/dev/null; exit 0" INT TERM

wait $SERVER_PID
