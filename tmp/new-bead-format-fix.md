# Fix ChatGPT JSON fence format mismatch in batch-plan.mjs

## How to Think

This is a bug fix to align the prompt format request with the extraction logic. Your job is to update ONE line in batch-plan.mjs to explicitly request ```json fence format instead of "no commentary". This ensures ChatGPT's response format matches what browser-worker.mjs expects to extract. Preserve all other prompt content - only change the final instruction line. This is a surgical fix, not a refactor. If the extraction logic has changed or uses a different pattern, stop and escalate rather than guessing.

## Acceptance Criteria

- batch-plan.mjs prompt explicitly requests ```json fence format
- Prompt still requests JSON array structure (unchanged)
- No other changes to the prompt template
- Fix matches the extraction regex in browser-worker.mjs:137

## Files to Modify

- scripts/chatgpt/batch-plan.mjs (line 119)

## Verification

```bash
# 1. Check the prompt format
grep -A 5 "Return" scripts/chatgpt/batch-plan.mjs | grep -q "json" && echo "✓ Fence format specified"

# 2. Test with actual ChatGPT request
node scripts/chatgpt/batch-plan.mjs \
  --beads bd-kg8 \
  --conversation-url "$(jq -r .crt_url .flywheel/chatgpt.json)" \
  --out tmp/format-test.json

# 3. Verify successful parse
jq -e '.parse_ok or (. | type == "array")' tmp/format-test.json && echo "✓ JSON extracted successfully"
```

## Context

**Root cause:** batch-plan.mjs:119 says "Return ONLY the JSON array, no commentary" but browser-worker.mjs:137 expects: `/```json\s*([\s\S]*?)\s*```/`

**The fix:** Change line 119 from:
```
Return ONLY the JSON array, no commentary.`;
```

To:
```
Return your response in this EXACT format with no additional text:

\`\`\`json
[
  { "id": "bd-...", ... }
]
\`\`\`
`;
```
