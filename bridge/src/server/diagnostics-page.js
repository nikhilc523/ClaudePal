export function renderDiagnosticsPage() {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>ClaudePal Bridge Diagnostics</title>
    <style>
      :root {
        color-scheme: light;
        font-family: Menlo, Monaco, monospace;
        background: #f5f7fb;
        color: #132238;
      }
      body {
        margin: 0;
        padding: 24px;
      }
      h1 {
        margin-top: 0;
      }
      .grid {
        display: grid;
        gap: 16px;
        grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      }
      .card {
        background: #ffffff;
        border: 1px solid #d9e2ef;
        border-radius: 12px;
        padding: 16px;
        box-shadow: 0 8px 24px rgba(19, 34, 56, 0.06);
      }
      pre {
        white-space: pre-wrap;
        word-break: break-word;
        margin: 0;
        max-height: 420px;
        overflow: auto;
      }
      button {
        border: 0;
        border-radius: 999px;
        background: #0f6fff;
        color: white;
        padding: 10px 14px;
        font: inherit;
        cursor: pointer;
      }
    </style>
  </head>
  <body>
    <h1>ClaudePal Bridge Diagnostics</h1>
    <p>This page verifies the Phase 1 local bridge loop: HTTP health, persisted data, and live WebSocket broadcasts.</p>
    <div class="grid">
      <section class="card">
        <h2>Health</h2>
        <button id="refresh">Refresh</button>
        <pre id="health"></pre>
      </section>
      <section class="card">
        <h2>Live Stream</h2>
        <pre id="stream"></pre>
      </section>
    </div>
    <script>
      const healthNode = document.getElementById("health");
      const streamNode = document.getElementById("stream");
      const refreshButton = document.getElementById("refresh");

      async function refreshHealth() {
        const response = await fetch("/health");
        const data = await response.json();
        healthNode.textContent = JSON.stringify(data, null, 2);
      }

      function appendStream(entry) {
        const current = streamNode.textContent;
        streamNode.textContent = [entry, current].filter(Boolean).join("\\n\\n");
      }

      refreshButton.addEventListener("click", refreshHealth);
      refreshHealth();

      const protocol = location.protocol === "https:" ? "wss" : "ws";
      const socket = new WebSocket(\`\${protocol}://\${location.host}/ws\`);
      socket.addEventListener("message", (event) => {
        appendStream(event.data);
      });
      socket.addEventListener("close", () => {
        appendStream(JSON.stringify({ type: "socket.closed" }, null, 2));
      });
    </script>
  </body>
</html>`;
}
