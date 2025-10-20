#!/bin/bash

# The user's immediate prompt is passed as arguments
USER_PROMPT="$@"

# Read conversation history from standard input, if available
CONTEXT=""
if ! tty -s; then
  CONTEXT=$(cat)
fi

# Ensure a prompt is provided either as an argument or via stdin
if [ -z "$USER_PROMPT" ] && [ -z "$CONTEXT" ]; then
  echo "Usage: gemini swarm \"<prompt>\" or pipe a prompt to the command." >&2
  exit 1
fi

# Create a temporary directory to store agent responses
TEMP_DIR=$(mktemp -d)

# Define the agents with their unique booster phrases
declare -A AGENTS
AGENTS["The Critic"]="Critically analyze this prompt. Identify potential flaws, weaknesses, and hidden assumptions. Provide a response that is skeptical and rigorous."
AGENTS["The Innovator"]="Think outside the box. How can this prompt be interpreted in a novel or unconventional way? Provide a creative, forward-thinking response."
AGENTS["The Pragmatist"]="Focus on the practical application. What is the most direct, actionable, and realistic response to this prompt? Avoid theory and focus on concrete steps."
AGENTS["The Ethicist"]="Consider the ethical implications of this prompt. What are the potential benefits and harms? Provide a response that is principled and considers the broader impact."

# stderr logging for debugging within the CLI
echo "Deploying agents..." >&2

# Run each agent sequentially
AGENT_NAMES=()
for name in "${!AGENTS[@]}"; do
  booster="${AGENTS[$name]}"
  # Combine context and the new prompt
  full_prompt="$CONTEXT\n\n$booster: $USER_PROMPT"
  echo "  - Deploying $name..." >&2
  # Pipe the full prompt to the gemini command
  echo -e "$full_prompt" | gemini > "$TEMP_DIR/$name.txt"
  AGENT_NAMES+=($name)
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

# Final call to the judge agent, piping the judge prompt
FINAL_RESPONSE=$(echo -e "$JUDGE_PROMPT" | gemini)

# Clean up the temporary directory
rm -rf "$TEMP_DIR"

# Output the final, synthesized response to stdout
echo "$FINAL_RESPONSE"
