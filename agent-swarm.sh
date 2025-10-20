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

# Check if the 'gemini' command is available
if ! command -v gemini &> /dev/null; then
  echo "Error: 'gemini' command not found. Please ensure it is installed and in your PATH." >&2
  exit 1
fi

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
echo "Deploying agents sequentially (rate limit protection)..." >&2

# Run each agent sequentially with rate limiting (free tier: 2 requests/minute)
declare -A agent_status
failed_count=0
agent_count=0
total_agents=${#AGENTS[@]}

# Sort agent names for deterministic order
sorted_names=($(echo "${!AGENTS[@]}" | tr ' ' '\n' | sort))

for name in "${sorted_names[@]}"; do
  booster="${AGENTS[$name]}"
  # Combine context and the new prompt
  full_prompt="$CONTEXT\n\n$booster: $USER_PROMPT"
  echo "  - Deploying $name..." >&2

  # Run the agent
  if echo -e "$full_prompt" | gemini > "$TEMP_DIR/$name.txt" 2>&1; then
    agent_status[$name]="success"
    echo "  - $name completed successfully." >&2
  else
    agent_status[$name]="failed"
    ((failed_count++))
    echo "  - Agent $name failed." >&2
  fi

  ((agent_count++))

  # Add delay between requests to respect rate limits (30 seconds between agents)
  # Skip delay after the last agent
  if [ "$agent_count" -lt "$total_agents" ]; then
    echo "  - Waiting 30 seconds before next agent (rate limit protection)..." >&2
    sleep 30
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
FINAL_RESPONSE=$(echo -e "$JUDGE_PROMPT" | gemini)

# The trap will handle cleanup, so the explicit rm is no longer needed here.

# Output the final, synthesized response to stdout
echo "$FINAL_RESPONSE"
