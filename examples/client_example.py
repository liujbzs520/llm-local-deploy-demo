"""
Client Usage Example
====================
Shows how external clients (buyers) connect to your LLM API gateway
using the standard OpenAI SDK — fully compatible interface.

Install: pip install openai
"""

from openai import OpenAI

# ── Connect to your self-hosted gateway ─────────────────────────────────────
client = OpenAI(
    base_url="https://YOUR_SERVER_IP/v1",   # ← your server
    api_key="sk-your-api-key-from-webui",   # ← key issued to the client
)

# ── List available models ─────────────────────────────────────────────────────
print("Available models:")
for model in client.models.list():
    print(f"  - {model.id}")

# ── Basic chat completion ─────────────────────────────────────────────────────
response = client.chat.completions.create(
    model="qwen2.5:7b",   # any pulled model
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user",   "content": "Explain transformer architecture briefly."},
    ],
    temperature=0.7,
    max_tokens=512,
)

print("\nResponse:")
print(response.choices[0].message.content)
print(f"\nTokens used: {response.usage.total_tokens}")

# ── Streaming example ─────────────────────────────────────────────────────────
print("\nStreaming response:")
stream = client.chat.completions.create(
    model="qwen2.5:7b",
    messages=[{"role": "user", "content": "Count to 5 slowly."}],
    stream=True,
)
for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
print()
