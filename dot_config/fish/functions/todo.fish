function todo --description "Add or manage Todoist tasks and reminders"
    set -l script "$HOME/.config/omarchy/plugins/mehdichamani.tasks/tasks_backend.py"
    if not test -e "$script"
        echo (set_color red)"Error: tasks_backend.py not found at $script"(set_color normal) >&2
        return 1
    end

    # If user passed --list or -l
    if test "$argv[1]" = "--list" -o "$argv[1]" = "-l"
        $script list --force
        return 0
    end

    # If no arguments provided, prompt interactively
    if test (count $argv) -eq 0
        read -P (set_color cyan)"New task (e.g. Meeting @ tomorrow 18:30): "(set_color normal) task_input
        if test -z "$task_input"
            return 0
        end
        set argv (string split " " -- $task_input)
    end

    set -l task_text (string join " " -- $argv)
    set -l result (python3 "$script" add "$task_text")

    set -l is_ok (printf '%s' "$result" | jq -r '.ok // false' 2>/dev/null)
    if test "$is_ok" = "true"
        set -l task_title (printf '%s' "$result" | jq -r '.task.title // ""' 2>/dev/null)
        echo (set_color green)"✓ Task added:"(set_color normal) "$task_title"
        # Notify Omarchy shell widget to refresh
        omarchy-shell -q mehdichamani.tasks refresh >/dev/null 2>&1
    else
        set -l err (printf '%s' "$result" | jq -r '.error // "Unknown error"' 2>/dev/null)
        echo (set_color red)"✗ Error:"(set_color normal) "$err" >&2
        return 1
    end
end
