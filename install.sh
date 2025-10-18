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

# --- DEBUG LOGGING ---
LOG_FILE="/tmp/swarm_debug.log"
echo "---" >> "$LOG_FILE"
echo "Script executed at: $(date)" >> "$LOG_FILE"
echo "Arguments received: $@" >> "$LOG_FILE"
# ---

# The user's immediate prompt is passed as arguments
USER_PROMPT="$@"

# Read conversation history from standard input, if available
CONTEXT=""
echo "Checking for stdin..." >> "$LOG_FILE"
# Use read with a short timeout to prevent hanging if the CLI runs this at startup
if ! tty -s; then
  echo "Not a TTY. Attempting to read from stdin with 0.1s timeout..." >> "$LOG_FILE"
  read -t 0.1 -d '' CONTEXT <&0
  echo "Read from stdin finished. Context length: ${#CONTEXT}" >> "$LOG_FILE"
else
  echo "Is a TTY. Skipping stdin read." >> "$LOG_FILE"
fi

# Ensure a prompt is provided either as an argument or via stdin
echo "Checking if prompt is empty..." >> "$LOG_FILE"
if [ -z "$USER_PROMPT" ] && [ -z "$CONTEXT" ]; then
  # Exit silently and successfully if run without a prompt (e.g., during CLI startup validation)
  echo "No prompt or context found. Exiting silently to prevent freeze." >> "$LOG_FILE"
  exit 0
fi

echo "Prompt found. Proceeding with agent logic..." >> "$LOG_FILE"

# Create a temporary directory to store agent responses
TEMP_DIR=$(mktemp -d)

# Define the agents with their unique booster phrases
declare -A AGENTS
AGENTS["The Critic"]="Critically analyze this prompt. Identify potential flaws, weaknesses, and hidden assumptions. Provide a response that is skeptical and rigorous."
AGENTS["The Innovator"]="Think outside the box. How can this prompt be interpreted in a novel or unconventional way? Provide a creative, forward-thinking response."
AGENTS["The Pragmatist"]="Focus on the practical application. What is the most direct, actionable, and realistic response to this prompt? Avoid theory and focus on concrete steps."
AGENTS["The Ethicist"]="Consider the ethical implications of this prompt. What are the potential benefits and harms? Provide a response that is principled and considers the broader impact."
AGENTS["The Historian"]="Provide historical context for this prompt. What are the relevant precedents, past events, and historical trends that inform this topic? Your response should be grounded in historical facts and analysis."
AGENTS["The Futurist"]="Extrapolate the future implications of this prompt. What are the potential long-term trends, scenarios, and consequences? Provide a speculative but well-reasoned response about what might happen next."
AGENTS["The Architect"]="Analyze this prompt from a software architecture perspective. Propose a high-level design, considering scalability, maintainability, and system boundaries. Use established architectural patterns."
AGENTS["The Refactorer"]="Examine the code or concept in this prompt for areas of improvement. Suggest specific refactorings to improve code quality, readability, performance, and adherence to best practices."
AGENTS["The Security Champion"]="Identify potential security vulnerabilities related to this prompt. Analyze the design, code, or concept for flaws like injection attacks, data exposure, or authentication issues, and recommend specific mitigations."

# stderr logging for debugging within the CLI
echo "Deploying agents..." >&2

# Run each agent in the background
PIDS=()
AGENT_NAMES=()
for name in "${!AGENTS[@]}"; do
  booster="${AGENTS[$name]}"
  # Combine context and the new prompt
  full_prompt="$CONTEXT\n\n$booster: $USER_PROMPT"
  echo "  - Deploying $name..." >&2
  # Pipe the full prompt to the gemini command, suppressing stderr
  (echo -e "$full_prompt" | gemini 2>/dev/null > "$TEMP_DIR/$name.txt") &
  PIDS+=($!)
  AGENT_NAMES+=($name)
done

echo "Waiting for agent responses..." >&2
for pid in "${PIDS[@]}"; do
  wait $pid
done

echo "Agents have responded. Synthesizing results..." >&2

# Combine all responses for the judge agent
ALL_RESPONSES=""
for name in "${AGENT_NAMES[@]}"; do
  response=$(cat "$TEMP_DIR/$name.txt")
  ALL_RESPONSES+="--- RESPONSE FROM $name ---\n$response\n\n"
done

# The judge prompt to synthesize the best response
JUDGE_PROMPT="You are a master synthesizer of information. Below are several responses to the same prompt, each from a different perspective. Your task is to analyze all of them, identify the strongest points from each, and synthesize them into a single, comprehensive, and superior response. Do not simply list the responses; integrate their best elements into a cohesive whole. For context, here is the full conversation history and the original prompt that generated these responses:\n\n$CONTEXT\n\nOriginal prompt: '$USER_PROMPT'.\n\nHere are the agent responses:\n\n$ALL_RESPONSES"

# Final call to the judge agent, piping the judge prompt and suppressing stderr
FINAL_RESPONSE=$(echo -e "$JUDGE_PROMPT" | gemini 2>/dev/null)

# Clean up the temporary directory
rm -rf "$TEMP_DIR"

# Output the final, synthesized response to stdout
echo "$FINAL_RESPONSE"
EOL

# Make the agent-swarm.sh script executable
echo "Setting permissions..."
chmod +x "$INSTALL_DIR/agent-swarm.sh"

echo ""
echo "Installation complete!"
echo "You can now use the extension with: gemini swarm \"Your prompt here\""
