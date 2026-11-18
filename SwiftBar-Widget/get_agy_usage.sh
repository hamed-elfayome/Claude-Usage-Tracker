#!/bin/bash

# Define a unique session name
SESSION_NAME="agy_headless_usage"

# Check if tmux is installed
if ! command -v tmux &> /dev/null; then
    echo "Error: tmux is required but not installed."
    exit 1
fi

# 1. Start a new detached tmux session running 'agy'
# We set a large window size (200x100) to ensure the output doesn't get paginated.
tmux new-session -d -x 200 -y 100 -s "$SESSION_NAME" "agy"

# 2. Wait for agy to finish loading and present the prompt
sleep 5

# 3. Send the '/usage' command and press Enter
tmux send-keys -t "$SESSION_NAME" "/usage" Enter

# 4. Wait for the usage output to be rendered
sleep 3

# 5. Capture the contents of the tmux pane
OUTPUT=$(tmux capture-pane -t "$SESSION_NAME" -p)

# 6. Kill the tmux session
tmux kill-session -t "$SESSION_NAME"

# 7. Print the extracted output to the terminal, filtering out empty lines at the end and cleaning up terminal artifacts
echo "$OUTPUT" | sed '/^$/d' | grep -v 'Gemini 3.1 Pro · high' | sed '/^ *$/d'
