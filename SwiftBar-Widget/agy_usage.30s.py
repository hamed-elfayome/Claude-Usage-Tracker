#!/usr/bin/env python3

# <xbar.title>Agy Usage</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>Google Antigravity</xbar.author>
# <xbar.desc>Displays Antigravity CLI quota usage</xbar.desc>
# <xbar.dependencies>python,tmux</xbar.dependencies>

import subprocess
import re
import os

SCRIPT_DIR = "/Users/dna-shem/Desktop/agy-usage"
SCRIPT_PATH = os.path.join(SCRIPT_DIR, "get_agy_usage.sh")

def get_color(percent):
    if percent < 50:
        return "green"
    elif percent < 90:
        return "orange"
    else:
        return "red"

def generate_bar(percent, total_blocks=20):
    filled = int((percent / 100) * total_blocks)
    empty = total_blocks - filled
    return ("█" * filled) + ("░" * empty)

def main():
    try:
        # Run the bash script to fetch usage via tmux
        result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, cwd=SCRIPT_DIR)
        text = result.stdout
    except Exception as e:
        print("W: ? S: ?")
        print("---")
        print(f"Error running script: {e}")
        return

    data = {
        'weekly': {'percent': 0, 'refreshes': 'Unknown'},
        'session': {'percent': 0, 'refreshes': 'Unknown'}
    }
    
    weekly_match = re.search(r'Weekly Limit.*?(\d+(?:\.\d+)?)%.*?(\d+)%\s+remaining\s+·\s+(Refreshes.*?|Resets.*?)\n', text, re.DOTALL)
    if weekly_match:
        remaining = float(weekly_match.group(2))
        data['weekly']['percent'] = int(100 - remaining)
        data['weekly']['refreshes'] = weekly_match.group(3).strip()

    session_match = re.search(r'Five Hour Limit.*?(\d+(?:\.\d+)?)%.*?(\d+)%\s+remaining\s+·\s+(Refreshes.*?|Resets.*?)\n', text, re.DOTALL)
    if session_match:
        remaining = float(session_match.group(2))
        data['session']['percent'] = int(100 - remaining)
        data['session']['refreshes'] = session_match.group(3).strip()
    elif re.search(r'Five Hour Limit.*?Quota available', text, re.DOTALL):
        data['session']['percent'] = 0
        data['session']['refreshes'] = 'Quota available'

    w_pct = data['weekly']['percent']
    s_pct = data['session']['percent']

    # 1. Menu bar string
    print(f"W: {w_pct}%  S: {s_pct}% | color={get_color(max(w_pct, s_pct))}")
    print("---")
    
    # 2. Session Dropdown
    print(f"Session Usage\t{s_pct}% | color={get_color(s_pct)} size=14 font=Menlo-Bold")
    print("5-hour rolling window | color=gray size=12")
    print(f"[{generate_bar(s_pct)}] | color={get_color(s_pct)} font=Menlo")
    print(f"{data['session']['refreshes']} | color=gray size=12")
    
    print("---")
    
    # 3. Weekly Dropdown
    print(f"All models Weekly\t{w_pct}% | color={get_color(w_pct)} size=14 font=Menlo-Bold")
    print(f"[{generate_bar(w_pct)}] | color={get_color(w_pct)} font=Menlo")
    print(f"{data['weekly']['refreshes']} | color=gray size=12")

if __name__ == "__main__":
    main()
