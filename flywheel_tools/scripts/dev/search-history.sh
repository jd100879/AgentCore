#!/usr/bin/env bash
# search-history.sh - Unified search across git/Beads/mail history
#
# Usage:
#   ./scripts/search-history.sh <query> [options]
#
# Options:
#   --source <git|beads|mail|all>  Limit search to specific source (default: all)
#   --format <text|json>           Output format (default: text)
#   --thread <bd-###>              Filter by thread/Beads issue ID
#   --agent <name>                 Filter by agent/author name
#   --since <YYYY-MM-DD>           Filter results after date (inclusive)
#   --until <YYYY-MM-DD>           Filter results before date (inclusive)
#   --limit <n>                    Limit number of results (default: unlimited)
#   --dedupe                       Remove duplicate/related results across sources
#   --score                        Enable relevance scoring (recency + source weight)
#   --source-weights <g:b:m>       Source weights for scoring (git:beads:mail, default: 1.0:1.5:0.8)
#   --product <uid>                Search across all projects in product (cross-repo)
#
# Examples:
#   ./scripts/search-history.sh "authentication"
#   ./scripts/search-history.sh "validation" --format json
#   ./scripts/search-history.sh "refactor" --source git
#   ./scripts/search-history.sh ".*" --thread bd-456
#   ./scripts/search-history.sh "error" --agent HazyFinch --since 2026-01-01
#   ./scripts/search-history.sh "phase" --limit 5
#   ./scripts/search-history.sh "test" --dedupe --score
#   ./scripts/search-history.sh "bug" --score --source-weights "1.0:2.0:0.5"

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BEADS_DB="$PROJECT_ROOT/.beads/beads.db"
MAIL_DB="$PROJECT_ROOT/tools/mcp_agent_mail/storage.sqlite3"

# Default options
QUERY=""
SOURCE="all"
FORMAT="text"
THREAD=""
AGENT=""
SINCE=""
UNTIL=""
LIMIT=""
DEDUPE=false
SCORE=false
PRODUCT=""  # Product-scoped search (cross-repo)
SOURCE_WEIGHTS="1.0:1.5:0.8"  # git:beads:mail (beads slightly higher as task-focused)
# Use Python for cross-platform millisecond timestamp
START_TIME=$(python3 -c "import time; print(int(time.time() * 1000))")

# Parse arguments
parse_args() {
    if [ $# -eq 0 ]; then
        echo "Error: Query string required" >&2
        echo "Usage: $0 <query> [--source <git|beads|mail|all>] [--format <text|json>]" >&2
        exit 1
    fi

    QUERY="$1"
    shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --source)
                SOURCE="$2"
                shift 2
                ;;
            --format)
                FORMAT="$2"
                shift 2
                ;;
            --thread)
                THREAD="$2"
                shift 2
                ;;
            --agent)
                AGENT="$2"
                shift 2
                ;;
            --since)
                SINCE="$2"
                shift 2
                ;;
            --until)
                UNTIL="$2"
                shift 2
                ;;
            --limit)
                LIMIT="$2"
                shift 2
                ;;
            --dedupe)
                DEDUPE=true
                shift
                ;;
            --score)
                SCORE=true
                shift
                ;;
            --source-weights)
                SOURCE_WEIGHTS="$2"
                shift 2
                ;;
            --product)
                PRODUCT="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    # Validate query is provided
    if [ -z "$QUERY" ]; then
        echo "Error: Search query is required" >&2
        exit 1
    fi

    # Validate options
    if [[ ! "$SOURCE" =~ ^(git|beads|mail|all)$ ]]; then
        echo "Error: Invalid --source value. Must be: git, beads, mail, or all" >&2
        exit 1
    fi

    if [[ ! "$FORMAT" =~ ^(text|json)$ ]]; then
        echo "Error: Invalid --format value. Must be: text or json" >&2
        exit 1
    fi

    # Validate date formats
    if [ -n "$SINCE" ] && ! [[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "Error: Invalid --since date format. Use YYYY-MM-DD" >&2
        exit 1
    fi

    if [ -n "$UNTIL" ] && ! [[ "$UNTIL" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "Error: Invalid --until date format. Use YYYY-MM-DD" >&2
        exit 1
    fi

    # Validate limit
    if [ -n "$LIMIT" ] && ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid --limit value. Must be a positive number" >&2
        exit 1
    fi

    # Validate source weights format
    if ! [[ "$SOURCE_WEIGHTS" =~ ^[0-9.]+:[0-9.]+:[0-9.]+$ ]]; then
        echo "Error: Invalid --source-weights format. Use git:beads:mail (e.g., 1.0:1.5:0.8)" >&2
        exit 1
    fi
}

# Search git commits
search_git() {
    local query="$1"
    local results=()

    if [ ! -d "$PROJECT_ROOT/.git" ]; then
        echo "Warning: Git repository not found, skipping git search" >&2
        return
    fi

    cd "$PROJECT_ROOT"

    # Build git log command with filters using array for proper argument handling
    local git_opts=("--all" "--format=%H|%an|%aI|%s")

    # Add thread filter (search for [bd-###] in commits)
    if [ -n "$THREAD" ]; then
        git_opts+=("--grep=\\[$THREAD\\]")
    fi

    # Add agent filter (filter by author)
    if [ -n "$AGENT" ]; then
        git_opts+=("--author=$AGENT")
    fi

    # Add date filters
    if [ -n "$SINCE" ]; then
        # Git interprets bare YYYY-MM-DD as end of day, so use previous day to include the specified date
        local since_inclusive=$(date -j -f "%Y-%m-%d" -v-1d "$SINCE" "+%Y-%m-%d" 2>/dev/null || date -d "$SINCE - 1 day" "+%Y-%m-%d" 2>/dev/null || echo "$SINCE")
        git_opts+=("--since=$since_inclusive")
    fi

    if [ -n "$UNTIL" ]; then
        # Git --until is exclusive, so add one day to make it inclusive
        local until_inclusive=$(date -j -f "%Y-%m-%d" -v+1d "$UNTIL" "+%Y-%m-%d" 2>/dev/null || date -d "$UNTIL + 1 day" "+%Y-%m-%d" 2>/dev/null || echo "$UNTIL")
        git_opts+=("--until=$until_inclusive")
    fi

    # Search commit messages (if no thread filter, use query grep)
    if [ -z "$THREAD" ]; then
        while IFS='|' read -r hash author date message; do
            if [ -n "$hash" ]; then
                files=$(git show --name-only --format="" "$hash" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
                echo "git|commit|$hash|$author|$date|$message|$files"
            fi
        done < <(git log --grep="$query" "${git_opts[@]}" 2>/dev/null || true)

        # Search code changes (pickaxe search) only if query is not wildcard
        if [ "$query" != ".*" ] && [ "$query" != "*" ]; then
            while IFS='|' read -r hash author date message; do
                if [ -n "$hash" ]; then
                    files=$(git show --name-only --format="" "$hash" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
                    echo "git|code|$hash|$author|$date|$message|$files"
                fi
            done < <(git log -S"$query" "${git_opts[@]}" 2>/dev/null || true)
        fi
    else
        # When thread filter is active, just get all commits matching the thread
        while IFS='|' read -r hash author date message; do
            if [ -n "$hash" ]; then
                files=$(git show --name-only --format="" "$hash" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
                echo "git|commit|$hash|$author|$date|$message|$files"
            fi
        done < <(git log "${git_opts[@]}" 2>/dev/null || true)
    fi
}

# Search Beads issues and comments
search_beads() {
    local query="$1"

    if [ ! -f "$BEADS_DB" ]; then
        echo "Warning: Beads database not found at $BEADS_DB, skipping beads search" >&2
        return
    fi

    # Escape single quotes for SQL
    local escaped_query="${query//\'/\'\'}"

    # Build WHERE clause for issues
    local issue_where="(title LIKE '%$escaped_query%' OR description LIKE '%$escaped_query%')"

    if [ -n "$THREAD" ]; then
        issue_where="$issue_where AND id='$THREAD'"
    fi

    if [ -n "$AGENT" ]; then
        local escaped_agent="${AGENT//\'/\'\'}"
        issue_where="$issue_where AND owner='$escaped_agent'"
    fi

    if [ -n "$SINCE" ]; then
        issue_where="$issue_where AND created_at >= '$SINCE'"
    fi

    if [ -n "$UNTIL" ]; then
        # Add one day to make it inclusive
        local until_inclusive=$(date -j -f "%Y-%m-%d" -v+1d "$UNTIL" "+%Y-%m-%d" 2>/dev/null || date -d "$UNTIL + 1 day" "+%Y-%m-%d" 2>/dev/null || echo "$UNTIL")
        issue_where="$issue_where AND created_at < '$until_inclusive'"
    fi

    # Search issues
    sqlite3 "$BEADS_DB" -separator '|' <<SQL 2>/dev/null || true
SELECT 'beads', 'issue', id, title, status, owner, created_at
FROM issues
WHERE $issue_where
ORDER BY created_at DESC;
SQL

    # Build WHERE clause for comments
    local comment_where="body LIKE '%$escaped_query%'"

    if [ -n "$THREAD" ]; then
        comment_where="$comment_where AND issue_id='$THREAD'"
    fi

    if [ -n "$AGENT" ]; then
        local escaped_agent="${AGENT//\'/\'\'}"
        comment_where="$comment_where AND author='$escaped_agent'"
    fi

    if [ -n "$SINCE" ]; then
        comment_where="$comment_where AND created_at >= '$SINCE'"
    fi

    if [ -n "$UNTIL" ]; then
        local until_inclusive=$(date -j -f "%Y-%m-%d" -v+1d "$UNTIL" "+%Y-%m-%d" 2>/dev/null || date -d "$UNTIL + 1 day" "+%Y-%m-%d" 2>/dev/null || echo "$UNTIL")
        comment_where="$comment_where AND created_at < '$until_inclusive'"
    fi

    # Search comments
    sqlite3 "$BEADS_DB" -separator '|' <<SQL 2>/dev/null || true
SELECT 'beads', 'comment', issue_id, author, '', body, created_at
FROM comments
WHERE $comment_where
ORDER BY created_at DESC;
SQL
}

# Search agent mail messages
search_mail() {
    local query="$1"

    if [ ! -f "$MAIL_DB" ]; then
        echo "Warning: Mail database not found at $MAIL_DB, skipping mail search" >&2
        return
    fi

    # Escape single quotes for SQL
    local escaped_query="${query//\'/\'\'}"

    # Build WHERE clause
    local where="(subject LIKE '%$escaped_query%' OR body_md LIKE '%$escaped_query%')"

    if [ -n "$THREAD" ]; then
        where="$where AND thread_id='$THREAD'"
    fi

    if [ -n "$AGENT" ]; then
        local escaped_agent="${AGENT//\'/\'\'}"
        where="$where AND sender='$escaped_agent'"
    fi

    if [ -n "$SINCE" ]; then
        # Convert YYYY-MM-DD to Unix timestamp (assuming UTC)
        local since_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$SINCE 00:00:00" "+%s" 2>/dev/null || date -d "$SINCE 00:00:00" "+%s" 2>/dev/null || echo "0")
        where="$where AND created_ts >= $since_ts"
    fi

    if [ -n "$UNTIL" ]; then
        # Convert YYYY-MM-DD to Unix timestamp for end of day (23:59:59)
        local until_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$UNTIL 23:59:59" "+%s" 2>/dev/null || date -d "$UNTIL 23:59:59" "+%s" 2>/dev/null || echo "9999999999")
        where="$where AND created_ts <= $until_ts"
    fi

    sqlite3 "$MAIL_DB" -separator '|' <<SQL 2>/dev/null || true
SELECT 'mail', 'message', id, thread_id, sender, subject, body_md, created_ts
FROM messages
WHERE $where
ORDER BY created_ts DESC;
SQL
}

# Calculate relevance score for a result
# Score = recency_score * source_weight
# recency_score: 0-1 based on how recent (exponential decay)
calculate_score() {
    local source="$1"
    local date="$2"

    # Parse source weights
    local IFS=':'
    read -r git_weight beads_weight mail_weight <<< "$SOURCE_WEIGHTS"

    # Get source weight
    local source_weight=1.0
    case "$source" in
        git) source_weight="$git_weight" ;;
        beads) source_weight="$beads_weight" ;;
        mail) source_weight="$mail_weight" ;;
    esac

    # Convert date to Unix timestamp
    local date_ts=0
    if [[ "$date" =~ ^[0-9]+$ ]]; then
        # Already a Unix timestamp (mail)
        date_ts="$date"
    elif [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        # ISO 8601 format (git, beads)
        date_ts=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${date%%[+-]*}" "+%s" 2>/dev/null || \
                  date -d "${date%%[+-]*}" "+%s" 2>/dev/null || echo "0")
    fi

    # Calculate age in days
    local now_ts=$(date +%s)
    local age_days=$(( (now_ts - date_ts) / 86400 ))

    # Exponential decay: score = e^(-age/30) for 30-day half-life
    # Approximate with: 1.0 / (1 + age/30) for simplicity
    local recency_score=$(python3 -c "print(1.0 / (1.0 + $age_days / 30.0))" 2>/dev/null || echo "0.5")

    # Final score
    python3 -c "print($recency_score * $source_weight)" 2>/dev/null || echo "1.0"
}

# Deduplicate results by identifying related items
# Returns: unique results with duplicates removed
deduplicate_results() {
    local tmpfile=$(mktemp)
    local seen_threads=$(mktemp)
    local seen_commits=$(mktemp)

    cat > "$tmpfile"

    while IFS='|' read -r source type f1 f2 f3 f4 f5 f6; do
        local skip=false

        case "$source" in
            git)
                # Extract thread ID from commit message if present
                local message="$f4"
                if [[ "$message" =~ \[bd-[a-z0-9]+\] ]]; then
                    local thread="${BASH_REMATCH[0]//[\[\]]/}"
                    if grep -q "^$thread$" "$seen_threads" 2>/dev/null; then
                        # Already saw a beads issue or mail for this thread
                        skip=true
                    else
                        echo "$f1" >> "$seen_commits"
                    fi
                else
                    echo "$f1" >> "$seen_commits"
                fi
                ;;
            beads)
                local thread="$f1"
                if [ "$type" = "issue" ]; then
                    if ! grep -q "^$thread$" "$seen_threads" 2>/dev/null; then
                        echo "$thread" >> "$seen_threads"
                    fi
                else
                    # Comment - keep for now
                    skip=false
                fi
                ;;
            mail)
                local thread="$f2"
                if [ -n "$thread" ] && grep -q "^$thread$" "$seen_threads" 2>/dev/null; then
                    # Already saw the beads issue for this thread
                    skip=true
                else
                    if [ -n "$thread" ]; then
                        echo "$thread" >> "$seen_threads"
                    fi
                fi
                ;;
        esac

        if [ "$skip" = false ]; then
            echo "$source|$type|$f1|$f2|$f3|$f4|$f5|$f6"
        fi
    done < "$tmpfile"

    rm -f "$tmpfile" "$seen_threads" "$seen_commits"
}

# Aggregate and sort results
aggregate_results() {
    local tmpfile=$(mktemp)
    local scored_file=$(mktemp)

    # Collect all results into temp file
    cat > "$tmpfile"

    # Apply deduplication if enabled
    if [ "$DEDUPE" = true ]; then
        deduplicate_results < "$tmpfile" > "${tmpfile}.deduped"
        mv "${tmpfile}.deduped" "$tmpfile"
    fi

    # Apply scoring if enabled
    if [ "$SCORE" = true ]; then
        while IFS='|' read -r source type f1 f2 f3 f4 f5 f6; do
            # Determine date field based on source
            local date=""
            case "$source" in
                git) date="$f3" ;;
                beads) date="$f5" ;;
                mail) date="$f6" ;;
            esac

            local score=$(calculate_score "$source" "$date")
            # Prepend score to line for sorting
            echo "$score|$source|$type|$f1|$f2|$f3|$f4|$f5|$f6"
        done < "$tmpfile" > "$scored_file"

        # Sort by score (descending)
        sort -t'|' -k1 -rn "$scored_file" | cut -d'|' -f2-
    else
        # Sort by date (field position varies by source, so we need custom sorting)
        sort -t'|' -k5 -r "$tmpfile" || cat "$tmpfile"
    fi

    rm -f "$tmpfile" "$scored_file"
}

# Apply result limit if specified
apply_limit() {
    if [ -n "$LIMIT" ]; then
        head -n "$LIMIT"
    else
        cat
    fi
}

# Format results as text
format_text() {
    local count=0

    while IFS='|' read -r source type f1 f2 f3 f4 f5 f6; do
        count=$((count + 1))

        case "$source" in
            git)
                local hash="$f1"
                local author="$f2"
                local date="$f3"
                local message="$f4"
                local files="$f5"

                echo ""
                echo "[git] $date ${hash:0:7} $author"
                echo "  $message"
                if [ -n "$files" ]; then
                    echo "  Files: $files"
                fi
                ;;
            beads)
                if [ "$type" = "issue" ]; then
                    local id="$f1"
                    local title="$f2"
                    local status="$f3"
                    local owner="$f4"
                    local date="$f5"

                    echo ""
                    echo "[beads] $date $id $status"
                    echo "  $title"
                    if [ -n "$owner" ]; then
                        echo "  Owner: $owner"
                    fi
                else
                    local issue_id="$f1"
                    local author="$f2"
                    local body="$f4"
                    local date="$f5"

                    echo ""
                    echo "[beads] $date Comment on $issue_id by $author"
                    echo "  ${body:0:100}..."
                fi
                ;;
            mail)
                local id="$f1"
                local thread_id="$f2"
                local sender="$f3"
                local subject="$f4"
                local body="$f5"
                local date="$f6"

                echo ""
                echo "[mail] $date #$id $sender"
                echo "  $subject"
                if [ -n "$thread_id" ]; then
                    echo "  Thread: $thread_id"
                fi
                echo "  ${body:0:100}..."
                ;;
        esac
    done

    if [ $count -eq 0 ]; then
        echo "No results found for query: $QUERY"
    else
        echo ""
        echo "---"
        echo "Total results: $count"
    fi
}

# Format results as JSON
format_json() {
    local results=()
    local count=0

    echo "{"
    echo "  \"query\": \"$QUERY\","
    echo "  \"results\": ["

    local first=true
    while IFS='|' read -r source type f1 f2 f3 f4 f5 f6; do
        count=$((count + 1))

        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi

        case "$source" in
            git)
                local hash="$f1"
                local author="$f2"
                local date="$f3"
                local message="$f4"
                local files="$f5"

                # Escape for JSON
                message="${message//\\/\\\\}"
                message="${message//\"/\\\"}"
                author="${author//\\/\\\\}"
                author="${author//\"/\\\"}"
                files="${files//\\/\\\\}"
                files="${files//\"/\\\"}"

                echo -n "    {"
                echo -n "\"source\":\"git\","
                echo -n "\"type\":\"$type\","
                echo -n "\"hash\":\"$hash\","
                echo -n "\"author\":\"$author\","
                echo -n "\"date\":\"$date\","
                echo -n "\"message\":\"$message\""
                if [ -n "$files" ]; then
                    echo -n ",\"files\":\"$files\""
                fi
                echo -n "}"
                ;;
            beads)
                if [ "$type" = "issue" ]; then
                    local id="$f1"
                    local title="$f2"
                    local status="$f3"
                    local owner="$f4"
                    local date="$f5"

                    title="${title//\\/\\\\}"
                    title="${title//\"/\\\"}"

                    echo -n "    {"
                    echo -n "\"source\":\"beads\","
                    echo -n "\"type\":\"issue\","
                    echo -n "\"id\":\"$id\","
                    echo -n "\"title\":\"$title\","
                    echo -n "\"status\":\"$status\","
                    echo -n "\"owner\":\"$owner\","
                    echo -n "\"date\":\"$date\""
                    echo -n "}"
                else
                    local issue_id="$f1"
                    local author="$f2"
                    local body="$f4"
                    local date="$f5"

                    body="${body//\\/\\\\}"
                    body="${body//\"/\\\"}"
                    body="${body:0:200}"

                    echo -n "    {"
                    echo -n "\"source\":\"beads\","
                    echo -n "\"type\":\"comment\","
                    echo -n "\"issue_id\":\"$issue_id\","
                    echo -n "\"author\":\"$author\","
                    echo -n "\"body\":\"$body\","
                    echo -n "\"date\":\"$date\""
                    echo -n "}"
                fi
                ;;
            mail)
                local id="$f1"
                local thread_id="$f2"
                local sender="$f3"
                local subject="$f4"
                local body="$f5"
                local date="$f6"

                subject="${subject//\\/\\\\}"
                subject="${subject//\"/\\\"}"
                body="${body//\\/\\\\}"
                body="${body//\"/\\\"}"
                body="${body:0:200}"

                echo -n "    {"
                echo -n "\"source\":\"mail\","
                echo -n "\"type\":\"message\","
                echo -n "\"id\":\"$id\","
                echo -n "\"thread_id\":\"$thread_id\","
                echo -n "\"sender\":\"$sender\","
                echo -n "\"subject\":\"$subject\","
                echo -n "\"body\":\"$body\","
                echo -n "\"date\":\"$date\""
                echo -n "}"
                ;;
        esac
    done

    echo ""
    echo "  ],"

    # Calculate query time
    local end_time=$(python3 -c "import time; print(int(time.time() * 1000))")
    local query_time=$((end_time - START_TIME))

    echo "  \"total\": $count,"
    echo "  \"query_time_ms\": $query_time"
    echo "}"
}

# Product-scoped search (cross-repo)
search_product() {
    local product_uid="$1"
    local query="$2"

    # Get product info and linked projects
    # NOTE: Basic implementation - queries current project only
    # TODO: Query MCP server for linked projects and search each project's databases
    # Future enhancement: scripts/lib/project-config.sh to discover linked repos

    echo "# Product search mode: $product_uid" >&2
    echo "# Note: Cross-repo search requires linked project discovery" >&2
    echo "# Currently searching local project only" >&2

    # For now, fall through to regular search in current project
    # with product context noted in results
}

# Main orchestrator
main() {
    parse_args "$@"

    cd "$PROJECT_ROOT"

    # Product-scoped search (cross-repo)
    if [ -n "$PRODUCT" ]; then
        search_product "$PRODUCT" "$QUERY"
        # Note: Currently falls through to local search
        # TODO: Implement full cross-repo search
    fi

    # Execute searches based on source filter
    {
        if [ "$SOURCE" = "all" ] || [ "$SOURCE" = "git" ]; then
            search_git "$QUERY"
        fi

        if [ "$SOURCE" = "all" ] || [ "$SOURCE" = "beads" ]; then
            search_beads "$QUERY"
        fi

        if [ "$SOURCE" = "all" ] || [ "$SOURCE" = "mail" ]; then
            search_mail "$QUERY"
        fi
    } | aggregate_results | apply_limit | {
        if [ "$FORMAT" = "json" ]; then
            format_json
        else
            format_text
        fi
    }
}

main "$@"
