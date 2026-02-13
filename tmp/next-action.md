# Next Action After Compact

**Primary task:** Update post-and-extract.mjs with ChatGPT's extraction pattern

**Location:** `/Users/james/Projects/AgentCore/scripts/chatgpt/post-and-extract.mjs`

**Changes needed:**
1. Replace code block extraction logic
2. Use last assistant message container (not global pre code)
3. Extract innerText from message
4. Regex for ```json fence: `/```json\s*([\s\S]*?)\s*```/`
5. Add two-signal wait:
   - "Stop generating" button gone
   - Message text stable for 2-3 seconds

**Reference:** See MEMORY.md for complete pattern

**Test plan:**
1. Run bridge: `./scripts/start-bridge-agent.sh`
2. Post batch request to ChatGPT
3. Verify JSON extraction works
4. Check no context burn in bridge agent

**ChatGPT session:** Still open at https://chatgpt.com/c/698de3b1-63c8-8329-b1b9-5e916d806e4b
