#!/usr/bin/env python3
"""
DeepSeek Auto-Compact Proxy
Intercepts API calls and forces compaction at 70% context usage.

This works around the Claude Code bug where CLAUDE_AUTOCOMPACT_PCT_OVERRIDE is ignored.
"""

import os
import sys
import json
import requests
import uuid
from flask import Flask, request, jsonify, Response, make_response
from datetime import datetime, timedelta
import signal

app = Flask(__name__)

# Configuration
DEEPSEEK_API_BASE = "https://api.deepseek.com"
DEEPSEEK_CONTEXT_LIMIT = 131000  # DeepSeek's token limit
COMPACT_THRESHOLD_PCT = 70  # Trigger compact at 70%
COMPACT_THRESHOLD_TOKENS = int(DEEPSEEK_CONTEXT_LIMIT * (COMPACT_THRESHOLD_PCT / 100))
STALE_SESSION_THRESHOLD_SECONDS = 3600  # 1 hour
CLEANUP_INTERVAL_SECONDS = 300  # 5 minutes

# State tracking (per-session)
sessions = {}
last_cleanup = datetime.now()

class SessionState:
    def __init__(self):
        self.total_tokens = 0
        self.last_request = datetime.now()
        self.request_count = 0
        self.compact_triggered_count = 0

    def estimate_tokens(self, text):
        """Rough token estimation: ~4 chars per token"""
        return len(text) // 4 if text else 0

    def add_usage(self, prompt_tokens, completion_tokens):
        """Add actual token usage from API response"""
        self.total_tokens += prompt_tokens + completion_tokens
        # request_count incremented in proxy_anthropic for all requests
        self.last_request = datetime.now()

    def should_compact(self):
        """Check if we should trigger compaction"""
        return self.total_tokens > COMPACT_THRESHOLD_TOKENS

    def reset_after_compact(self):
        """Reset token count after compaction occurs"""
        old_total = self.total_tokens
        self.total_tokens = int(self.total_tokens * 0.3)  # Assume compact reduces to ~30%
        self.compact_triggered_count += 1
        return old_total

    def is_expired(self):
        """Check if session is stale (older than threshold)"""
        age = (datetime.now() - self.last_request).total_seconds()
        return age > STALE_SESSION_THRESHOLD_SECONDS


def get_session(session_id="default"):
    """Get or create session state, cleaning up expired sessions"""
    # Check if session exists and is expired
    if session_id in sessions:
        session = sessions[session_id]
        if session.is_expired():
            log(f"Session expired: {session_id[:8]}... (last request: {session.last_request})")
            del sessions[session_id]
            # Create new session
            sessions[session_id] = SessionState()
            log(f"Created fresh session after expiration: {session_id[:8]}...")

    if session_id not in sessions:
        sessions[session_id] = SessionState()

    return sessions[session_id]


def cleanup_sessions():
    """Remove all expired sessions"""
    global last_cleanup
    now = datetime.now()

    # Only run cleanup if enough time has passed
    if (now - last_cleanup).total_seconds() < CLEANUP_INTERVAL_SECONDS:
        return

    log(f"Running session cleanup (current sessions: {len(sessions)})")
    expired_count = 0

    # Create list of session IDs to avoid dict size change during iteration
    session_ids = list(sessions.keys())

    for session_id in session_ids:
        # Check if session still exists (may have been deleted by concurrent cleanup)
        if session_id not in sessions:
            continue
        session = sessions[session_id]
        if session.is_expired():
            log(f"Cleaning up expired session: {session_id[:8]}... (last request: {session.last_request})")
            # Double-check still exists before deleting (thread safety)
            if session_id in sessions:
                del sessions[session_id]
                expired_count += 1

    last_cleanup = now
    if expired_count > 0:
        log(f"Session cleanup removed {expired_count} expired sessions, {len(sessions)} remaining")
    else:
        log(f"Session cleanup: no expired sessions, {len(sessions)} total")


def get_or_create_session_id_from_request():
    """Get session ID from X-Session-ID header, cookie, or create new one.
    Returns (session_id, is_new_session) tuple.
    """
    # Clean up expired sessions (throttled)
    cleanup_sessions()

    # First check for X-Session-ID header (preferred method for Claude Code)
    session_id = request.headers.get('X-Session-ID')
    is_new = False
    source = "header"

    if session_id and session_id.strip():
        # Validate UUID format
        try:
            uuid_obj = uuid.UUID(session_id)
            session_id = str(uuid_obj)  # Normalize format
            log(f"Session from X-Session-ID header: {session_id[:8]}...")
        except ValueError:
            # Invalid UUID, treat as no session
            log(f"Invalid X-Session-ID format: {session_id[:16]}...", "WARN")
            session_id = None

    # Fallback to query parameter (for ANTHROPIC_BASE_URL with session_id param)
    if not session_id:
        session_id = request.args.get('session_id')
        source = "query" if session_id else source

    # Fallback to cookie
    if not session_id:
        session_id = request.cookies.get('deepseek_session')
        source = "cookie" if session_id else source

    # Generate new if still not found
    if not session_id or not session_id.strip():
        session_id = str(uuid.uuid4())
        is_new = True
        source = "new"
        log(f"New session created: {session_id[:8]}...")

    # Log session source for debugging
    if not is_new and source:
        log(f"Session from {source}: {session_id[:8]}...")

    return session_id, is_new


def log(message, level="INFO"):
    """Log with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] [{level}] {message}", flush=True)


def parse_sse_for_usage(response_content):
    """Parse Server-Sent Events (SSE) to find usage data.

    SSE format: data: {...}\n\n
    Looks for 'usage' field in JSON data.
    """
    if not response_content:
        return None

    content = response_content.decode('utf-8', errors='ignore')
    lines = content.split('\n')

    for line in lines:
        line = line.strip()
        if line.startswith('data: '):
            data_str = line[6:]  # Remove 'data: ' prefix
            if data_str == '[DONE]':
                continue
            try:
                data = json.loads(data_str)
                if 'usage' in data:
                    return data['usage']
            except json.JSONDecodeError:
                continue

    return None


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "proxy": "deepseek-compact-proxy",
        "sessions": len(sessions),
        "threshold": f"{COMPACT_THRESHOLD_PCT}% ({COMPACT_THRESHOLD_TOKENS} tokens)"
    })


@app.route('/status', methods=['GET'])
def status():
    """Show current session status"""
    # Get session ID from cookie or create new one
    session_id, is_new_session = get_or_create_session_id_from_request()
    session = get_session(session_id)

    resp = make_response(jsonify({
        "total_tokens": session.total_tokens,
        "limit": DEEPSEEK_CONTEXT_LIMIT,
        "threshold": COMPACT_THRESHOLD_TOKENS,
        "usage_pct": round((session.total_tokens / DEEPSEEK_CONTEXT_LIMIT) * 100, 2),
        "threshold_pct": COMPACT_THRESHOLD_PCT,
        "should_compact": session.should_compact(),
        "requests": session.request_count,
        "compacts_triggered": session.compact_triggered_count,
        "session_id": session_id[:8] + "..."
    }))

    # Set session cookie if new session
    if is_new_session:
        resp.set_cookie('deepseek_session', session_id, max_age=86400*30)  # 30 days

    return resp


@app.route('/reset', methods=['POST'])
def reset():
    """Manually reset session (after compact)"""
    # Get session ID from cookie or create new one
    session_id, is_new_session = get_or_create_session_id_from_request()
    session = get_session(session_id)

    old_tokens = session.reset_after_compact()
    log(f"Manual reset: Session {session_id[:8]}... {old_tokens} → {session.total_tokens} tokens")

    resp = make_response(jsonify({"status": "reset", "tokens": session.total_tokens, "session_id": session_id[:8] + "..."}))

    # Set session cookie if new session
    if is_new_session:
        resp.set_cookie('deepseek_session', session_id, max_age=86400*30)  # 30 days

    return resp


@app.route('/anthropic/<path:endpoint>', methods=['POST', 'GET', 'PUT', 'DELETE'])
def proxy_anthropic(endpoint):
    """Proxy all Anthropic API-compatible requests"""
    # Get or create session ID from cookie
    session_id, is_new_session = get_or_create_session_id_from_request()
    session = get_session(session_id)

    # Log request with session ID and cookie info
    log(f"Request: {request.method} /{endpoint} | Session: {session_id[:8]}... | Tokens: {session.total_tokens}/{DEEPSEEK_CONTEXT_LIMIT} ({round(session.total_tokens/DEEPSEEK_CONTEXT_LIMIT*100, 1)}%) | Cookie: {'yes' if 'deepseek_session' in request.cookies else 'no'}, New: {is_new_session}")
    session.request_count += 1
    session.last_request = datetime.now()

    # Force compaction if threshold reached by returning 429 error
    if session.should_compact():
        log(f"🛑 FORCING COMPACTION: {session.total_tokens}/{DEEPSEEK_CONTEXT_LIMIT} ({COMPACT_THRESHOLD_PCT}%)", "WARN")
        log(f"🛑 Returning 429 error to trigger Claude Code auto-compact", "WARN")

        # Return 429 error to force Claude Code to compact
        error_response = {
            "type": "error",
            "error": {
                "type": "overloaded_error",
                "message": f"Context usage exceeded {COMPACT_THRESHOLD_PCT}% threshold ({session.total_tokens}/{DEEPSEEK_CONTEXT_LIMIT} tokens). Claude Code will now compact the conversation history."
            }
        }

        resp = make_response(jsonify(error_response), 429)
        resp.headers['Retry-After'] = '1'  # Hint to retry after compaction

        # Set session cookie if new session
        if is_new_session:
            resp.set_cookie('deepseek_session', session_id, max_age=86400*30)

        # Reset token count since compaction will happen
        old_total = session.reset_after_compact()
        log(f"Session token count reset: {old_total} → {session.total_tokens} tokens (post-compact estimate)")

        return resp

    # Forward request to DeepSeek
    target_url = f"{DEEPSEEK_API_BASE}/anthropic/{endpoint}"

    try:
        # Prepare request
        headers = dict(request.headers)
        headers.pop('Host', None)

        # Forward request
        response = requests.request(
            method=request.method,
            url=target_url,
            headers=headers,
            data=request.get_data(),
            allow_redirects=False,
            timeout=600  # 10 minute timeout
        )

        # Track token usage from response
        try:
            content_type = response.headers.get('content-type', '')
            status_code = response.status_code
            log(f"Response: status={status_code}, content-type={content_type[:50]}")

            # Handle different response types
            if content_type.startswith('application/json'):
                try:
                    response_data = response.json()
                    log(f"Response JSON keys: {list(response_data.keys())}")

                    # Extract token usage from response if available
                    if 'usage' in response_data:
                        usage = response_data['usage']
                        prompt_tokens = usage.get('input_tokens', 0)
                        completion_tokens = usage.get('output_tokens', 0)
                        session.add_usage(prompt_tokens, completion_tokens)
                        log(f"Usage: +{prompt_tokens + completion_tokens} tokens | Total: {session.total_tokens}/{DEEPSEEK_CONTEXT_LIMIT}")
                    elif status_code == 200:
                        # Successful response but no usage field - might be streaming or different format
                        log(f"WARN: 200 response but no usage field. Response: {str(response_data)[:200]}")
                        # Estimate from request if available
                        if request.json and 'messages' in request.json:
                            estimated = session.estimate_tokens(str(request.json['messages']))
                            session.total_tokens += estimated
                            log(f"Estimated from 200 response: +{estimated} tokens | Total: {session.total_tokens}/{DEEPSEEK_CONTEXT_LIMIT}")
                    elif request.json and 'messages' in request.json:
                        # Error response (non-200) - estimate from request
                        estimated = session.estimate_tokens(str(request.json['messages']))
                        session.total_tokens += estimated
                        log(f"Estimated from error response: +{estimated} tokens (status {status_code}) | Total: {session.total_tokens}/{DEEPSEEK_CONTEXT_LIMIT}")
                except json.JSONDecodeError:
                    # Response is not valid JSON
                    log(f"JSON decode error for content-type {content_type}")
                    if request.json and 'messages' in request.json:
                        estimated = session.estimate_tokens(str(request.json['messages']))
                        session.total_tokens += estimated
                        log(f"Estimated: +{estimated} tokens (invalid JSON response)")

            elif content_type.startswith('text/event-stream'):
                # Streaming response - parse Server-Sent Events
                log(f"Streaming response detected, trying to parse SSE for usage data")

                # Try to parse SSE for usage data
                usage_data = parse_sse_for_usage(response.content)
                if usage_data:
                    prompt_tokens = usage_data.get('input_tokens', 0)
                    completion_tokens = usage_data.get('output_tokens', 0)
                    session.add_usage(prompt_tokens, completion_tokens)
                    log(f"SSE Usage: +{prompt_tokens + completion_tokens} tokens | Total: {session.total_tokens}/{DEEPSEEK_CONTEXT_LIMIT}")
                else:
                    # No usage found in SSE, estimate from request
                    log(f"No usage data found in SSE, estimating from request")
                    if request.json and 'messages' in request.json:
                        estimated = session.estimate_tokens(str(request.json['messages']))
                        session.total_tokens += estimated
                        log(f"Estimated from streaming: +{estimated} tokens | Total: {session.total_tokens}/{DEEPSEEK_CONTEXT_LIMIT}")
                    else:
                        log(f"WARN: Streaming but no request messages to estimate from")

            else:
                # Response is not JSON or streaming
                log(f"Non-JSON, non-streaming response: content-type={content_type}")
                if request.json and 'messages' in request.json:
                    estimated = session.estimate_tokens(str(request.json['messages']))
                    session.total_tokens += estimated
                    log(f"Estimated: +{estimated} tokens (non-JSON response)")
                elif status_code == 200:
                    # Successful but unknown format - minimal estimate
                    session.total_tokens += 100  # Minimal assumption
                    log(f"Minimal estimate for 200 response: +100 tokens | Total: {session.total_tokens}/{DEEPSEEK_CONTEXT_LIMIT}")
        except Exception as e:
            log(f"Error tracking token usage: {e}", "ERROR")
            import traceback
            log(f"Traceback: {traceback.format_exc()}", "ERROR")

        # Return response
        # Strip Transfer-Encoding and Content-Encoding headers to avoid chunked encoding issues
        # Flask/Werkzeug will handle encoding properly
        response_headers = dict(response.headers)
        response_headers.pop('Transfer-Encoding', None)
        response_headers.pop('Content-Encoding', None)
        response_headers.pop('Content-Length', None)  # Flask will recalculate

        resp = make_response(response.content, response.status_code)
        resp.headers.update(response_headers)

        # Set session cookie if new session
        if is_new_session:
            resp.set_cookie('deepseek_session', session_id, max_age=86400*30)  # 30 days

        return resp

    except requests.exceptions.Timeout:
        log("Request timeout", "ERROR")
        resp = make_response(jsonify({"error": {"type": "timeout", "message": "Request timed out"}}), 504)
        # Set session cookie if new session
        if is_new_session:
            resp.set_cookie('deepseek_session', session_id, max_age=86400*30)  # 30 days
        return resp
    except Exception as e:
        log(f"Proxy error: {str(e)}", "ERROR")
        resp = make_response(jsonify({"error": {"type": "proxy_error", "message": str(e)}}), 500)
        # Set session cookie if new session
        if is_new_session:
            resp.set_cookie('deepseek_session', session_id, max_age=86400*30)  # 30 days
        return resp


def signal_handler(sig, frame):
    """Handle shutdown gracefully"""
    log("Shutting down proxy...")
    sys.exit(0)


if __name__ == '__main__':
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Configuration from environment
    port = int(os.environ.get('PROXY_PORT', 5000))
    host = os.environ.get('PROXY_HOST', '127.0.0.1')

    log("=" * 60)
    log("DeepSeek Auto-Compact Proxy")
    log("=" * 60)
    log(f"Context Limit: {DEEPSEEK_CONTEXT_LIMIT:,} tokens")
    log(f"Compact Threshold: {COMPACT_THRESHOLD_PCT}% ({COMPACT_THRESHOLD_TOKENS:,} tokens)")
    log(f"Listening on: http://{host}:{port}")
    log("=" * 60)
    log("")
    log("Use in wrapper: export ANTHROPIC_BASE_URL=\"http://127.0.0.1:5000/anthropic\"")
    log("")

    app.run(host=host, port=port, debug=False)
