#!/usr/bin/env python3
import sys
import json
import subprocess

# --- Protocol Helpers ---

def send_message(msg):
    json_str = json.dumps(msg)
    sys.stdout.write(json_str + "\n")
    sys.stdout.flush()

def read_message():
    line = sys.stdin.readline()
    if not line:
        return None
    return json.loads(line)

# --- MacOS Calendar Logic ---

def add_event(title, notes=""):
    """Adds an event to macOS Calendar using AppleScript"""
    script = f'''
    tell application "Calendar"
        tell calendar "Home"
            make new event at end with properties {{summary:"{title}", description:"{notes}", start date:(current date) + 1 * hours, end date:(current date) + 2 * hours}}
        end tell
    end tell
    '''
    try:
        subprocess.run(['osascript', '-e', script], check=True, capture_output=True)
        return "Event created successfully."
    except subprocess.CalledProcessError as e:
        return f"Error creating event: {e.stderr.decode('utf-8')}"

# --- Main Loop ---

def handle_request(req):
    method = req.get('method')
    msg_id = req.get('id')
    
    if method == 'initialize':
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {"listChanged": False}
                },
                "serverInfo": {"name": "MacCalendar", "version": "1.0"}
            }
        }
    
    if method == 'notifications/initialized':
        return None # No response needed

    if method == 'tools/list':
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "tools": [{
                    "name": "calendar.add_event",
                    "description": "Add a new event to the macOS Calendar. Only use this if the user explicitly asks to schedule something.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "title": {"type": "string", "description": "Title of the event"},
                            "notes": {"type": "string", "description": "Description or notes"}
                        },
                        "required": ["title"]
                    }
                }]
            }
        }

    if method == 'tools/call':
        params = req.get('params', {})
        name = params.get('name')
        args = params.get('arguments', {})
        
        if name == 'calendar.add_event':
            title = args.get('title', 'Meeting')
            notes = args.get('notes', '')
            output = add_event(title, notes)
            return {
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {
                    "content": [{"type": "text", "text": output}]
                }
            }
            
    return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": -32601, "message": "Method not found"}}

def main():
    while True:
        try:
            req = read_message()
            if req is None: break
            
            resp = handle_request(req)
            if resp:
                send_message(resp)
        except Exception as e:
            # sys.stderr.write(f"Error: {e}\n")
            pass

if __name__ == "__main__":
    main()
