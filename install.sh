#!/bin/bash

# Define the installation directory
INSTALL_DIR="$HOME/.gemini/extensions/booster"

# Create the directory if it doesn't exist
echo "Creating installation directory at $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Write the gemini-extension.json manifest file
echo "Creating manifest file..."
cat > "$INSTALL_DIR/gemini-extension.json" << EOL
{
  "name": "Booster",
  "version": "1.8.0",
  "description": "Adds detailed logging to debug the CLI startup freeze.",
  "author": "Cline",
  "commands": [
    {
      "command": "swarm",
      "prompt": "$INSTALL_DIR/agent-swarm.sh"
    }
  ]
}
EOL

# Write the agent-swarm.sh script file
echo "Creating agent script..."
cat > "$INSTALL_DIR/agent-swarm.sh" << 'EOL'
#!/bin/bash

# The user's immediate prompt is passed as arguments
USER_PROMPT="$@"

# Read conversation history from standard input, if available
CONTEXT=""
if ! tty -s; then
  # Use read with a short timeout to prevent hanging if the CLI runs this at startup
  read -t 0.1 -d '' CONTEXT <&0
fi

# Ensure a prompt is provided either as an argument or via stdin
if [ -z "$USER_PROMPT" ] && [ -z "$CONTEXT" ]; then
  # Exit silently and successfully if run without a prompt (e.g., during CLI startup validation)
  exit 0
fi

# Check if the 'ollama' command is available
if ! command -v ollama &> /dev/null; then
  echo "Error: 'ollama' command not found. Please ensure Ollama is installed and running." >&2
  echo "Install Ollama from: https://ollama.com" >&2
  exit 1
fi

# Load environment variables from .env file if it exists
if [ -f "$(dirname "$0")/.env" ]; then
  source "$(dirname "$0")/.env"
elif [ -f "$HOME/.gemini/extensions/booster/.env" ]; then
  source "$HOME/.gemini/extensions/booster/.env"
fi

# Set default Ollama model if not specified
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3}"
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"

# Create a temporary directory to store agent responses
TEMP_DIR=$(mktemp -d)

# Define the agents with their unique booster phrases
declare -A AGENTS
AGENTS["The Architect"]="Analyze the prompt from a software architecture perspective. Consider scalability, design patterns, and long-term maintainability. Propose a high-level structure for the solution."
AGENTS["The Code Reviewer"]="Review the prompt as if it were a code change. Focus on best practices, readability, potential bugs, and adherence to coding standards. Provide a critical code review."
AGENTS["The Security Analyst"]="Examine the prompt for potential security vulnerabilities. Consider injection attacks, data handling, authentication, and other security risks. Provide a security-focused analysis."
AGENTS["The Tester"]="Analyze the prompt from a testing perspective. Identify edge cases, potential failure points, and a strategy for ensuring the solution is robust and correct. How would you test this?"
AGENTS["The Contrarian"]="Challenge the fundamental assumptions of this prompt. Argue against the proposed course of action and highlight the potential negative consequences, risks, or alternative interpretations. Play devil's advocate."

# Ensure the temporary directory is cleaned up on exit
trap "rm -rf '$TEMP_DIR'" EXIT

# stderr logging for debugging within the CLI
echo "Deploying agents using Ollama..." >&2

# Run each agent
declare -A pid_to_name
pids=()
for name in "${!AGENTS[@]}"; do
  booster="${AGENTS[$name]}"
  # Combine context and the new prompt
  full_prompt="$CONTEXT\n\n$booster: $USER_PROMPT"
  echo "  - Deploying $name..." >&2
  # Pipe the full prompt to the ollama command and run in the background
  (echo -e "$full_prompt" | OLLAMA_HOST="$OLLAMA_HOST" ollama run "$OLLAMA_MODEL" > "$TEMP_DIR/$name.txt") &
  pid=$!
  pids+=($pid)
  pid_to_name[$pid]=$name
done

# Wait for all background jobs to finish and record their status
declare -A agent_status
failed_count=0
for pid in "${pids[@]}"; do
  name=${pid_to_name[$pid]}
  if wait "$pid"; then
    agent_status[$name]="success"
  else
    agent_status[$name]="failed"
    ((failed_count++))
    echo "  - Agent $name failed." >&2
  fi
done

# Abort if all agents failed
if [ "$failed_count" -eq "${#AGENTS[@]}" ]; then
  echo "All agents failed to respond. Aborting." >&2
  exit 1
fi

echo "Agents have responded. Synthesizing results..." >&2

# Combine all responses for the judge agent, sorting by name for deterministic order
ALL_RESPONSES=""
for name in $(echo "${!AGENTS[@]}" | tr ' ' '\n' | sort); do
  status=${agent_status[$name]}
  if [[ "$status" == "success" ]]; then
    response_file="$TEMP_DIR/$name.txt"
    if [ -s "$response_file" ]; then
      response=$(cat "$response_file")
      ALL_RESPONSES+="--- RESPONSE FROM $name ---\n$response\n\n"
    else
      ALL_RESPONSES+="--- EMPTY RESPONSE FROM $name ---\n\n"
    fi
  else
    ALL_RESPONSES+="--- FAILED RESPONSE FROM $name ---\n\n"
  fi
done

# The judge prompt to synthesize the best response
JUDGE_PROMPT="You are a master synthesizer of information. Below are several responses to the same prompt, each from a different perspective. Your task is to analyze all of them, identify the strongest points from each, and synthesize them into a single, comprehensive, and superior response. Critically evaluate the agent responses, highlighting potential risks, weaknesses, or contradictions. Do not simply list the responses; integrate their best elements and address their concerns to produce a cohesive and well-considered final answer. For context, here is the full conversation history and the original prompt that generated these responses:\n\n$CONTEXT\n\nOriginal prompt: '$USER_PROMPT'.\n\nHere are the agent responses:\n\n$ALL_RESPONSES"

# Final call to the judge agent, piping the judge prompt
FINAL_RESPONSE=$(echo -e "$JUDGE_PROMPT" | OLLAMA_HOST="$OLLAMA_HOST" ollama run "$OLLAMA_MODEL")

# The trap will handle cleanup, so the explicit rm is no longer needed here.

# Output the final, synthesized response to stdout
echo "$FINAL_RESPONSE"
EOL

# Make the agent-swarm.sh script executable
echo "Setting permissions..."
chmod +x "$INSTALL_DIR/agent-swarm.sh"

echo ""
echo "Installation complete!"
echo ""
echo "IMPORTANT: Before using the extension, make sure:"
echo "1. Ollama is installed (https://ollama.com)"
echo "2. Ollama is running (run 'ollama serve' in a terminal)"
echo "3. Your desired model is pulled (e.g., 'ollama pull llama3')"
echo ""
echo "You can now use the extension with: gemini swarm \"Your prompt here\""
echo ""
echo "Optional: Create a .env file at $INSTALL_DIR/.env with:"
echo "  OLLAMA_MODEL=llama3"
echo "  OLLAMA_HOST=http://localhost:11434"
