#!/usr/bin/env bash

rows=20
cols=10
score=0
level_name="Normal"
delay=0.7
running=1
paused=0
stty_state=$(stty -g 2>/dev/null || true)
cell_width=4
cell_height=2
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
db_path="${TETRIS_DB:-$script_dir/tetris_scores.sqlite3}"
player_name=""
best_score=""
score_result=""
current_piece_name=""
log_limit=28
logs=()

board=()
for ((i=0; i<rows*cols; i++)); do board[$i]="."; done

shapes=(
"0,0 0,1 0,2 0,3 0,4"
"0,0 1,0 2,0 0,1 1,1 2,1 0,2 1,2 2,2"
"0,0 1,0 2,0 1,1 1,2"
"0,0 1,0 1,1 2,1"
"1,0 2,0 0,1 1,1"
"1,0 1,1 0,2 1,2"
"0,0 0,1 0,2 1,2"
)
shape_names=("I" "O" "T" "S" "Z" "J" "L")

cleanup() {
    local message=${1:-"Game over"}
    trap - EXIT INT TERM
    running=0
    save_score
    tput cnorm 2>/dev/null || true
    printf '\e[?1049l'
    if [[ -n "$stty_state" ]]; then
        stty "$stty_state" 2>/dev/null || true
    else
        stty echo icanon 2>/dev/null || true
    fi
    printf "%s. Score: %s\n" "$message" "$score"
    if [[ -n "$player_name" && -n "$best_score" ]]; then
        printf "Player: %s. Best score: %s\n" "$player_name" "$best_score"
        if [[ -n "$score_result" ]]; then
            printf "%s\n" "$score_result"
        fi
    fi
    exit
}

trap 'cleanup "Game over"' INT TERM
trap 'cleanup "Game over"' EXIT

init_db() {
    sqlite3 "$db_path" "
        CREATE TABLE IF NOT EXISTS players (
            name TEXT PRIMARY KEY,
            pin TEXT NOT NULL,
            score INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
    "
}

show_top_players() {
    local count=${1:-100}
    local rows

    rows=$(sqlite3 -column -header "$db_path" "
        SELECT
            row_number() OVER (ORDER BY score DESC, updated_at ASC, name ASC) AS '#',
            name AS player,
            score
        FROM players
        ORDER BY score DESC, updated_at ASC, name ASC
        LIMIT $count;
    ")

    echo "Top $count players by best score:"
    if [[ -n "$rows" ]]; then
        echo "$rows"
    else
        echo "No players yet."
    fi
}

login_player() {
    local name pin existing_pin

    while true; do
        echo
        read -rp "Player name (A-Z, a-z, 0-9): " name

        if [[ ! "$name" =~ ^[A-Za-z0-9]+$ ]]; then
            echo "Use only English letters and digits."
            continue
        fi

        existing_pin=$(sqlite3 "$db_path" "SELECT pin FROM players WHERE name = '$name';")

        if [[ -n "$existing_pin" ]]; then
            read -rsp "PIN for $name: " pin
            echo

            if [[ "$pin" == "$existing_pin" ]]; then
                player_name="$name"
                best_score=$(sqlite3 "$db_path" "SELECT score FROM players WHERE name = '$player_name';")
                best_score=${best_score:-0}
                return
            fi

            echo "Wrong PIN. Enter another name, or try the correct PIN."
            continue
        fi

        while true; do
            read -rsp "Create PIN for $name (A-Z, a-z, 0-9): " pin
            echo

            if [[ "$pin" =~ ^[A-Za-z0-9]+$ ]]; then
                break
            fi

            echo "PIN can contain only English letters and digits."
        done

        sqlite3 "$db_path" "
            INSERT INTO players (name, pin, score)
            VALUES ('$name', '$pin', 0);
        "
        player_name="$name"
        best_score=0
        return
    done
}

save_score() {
    local old_best

    if [[ -z "$player_name" ]]; then
        return
    fi

    old_best=${best_score:-}
    if [[ -z "$old_best" ]]; then
        old_best=$(sqlite3 "$db_path" "SELECT score FROM players WHERE name = '$player_name';")
    fi
    old_best=${old_best:-0}

    if (( score > old_best )); then
        sqlite3 "$db_path" "
            UPDATE players
            SET score = $score,
                updated_at = CURRENT_TIMESTAMP
            WHERE name = '$player_name';
        "
        best_score=$score
        score_result="New record saved! Previous best: $old_best"
        add_log "New best score saved: $best_score"
    elif [[ -z "$score_result" ]]; then
        best_score=$old_best
        score_result="Record unchanged."
    fi
}

choose_speed() {
    while true; do
        clear
        printf '\e[H'
        echo "Select speed:"
        echo "1) Easy   - very calm"
        echo "2) Normal - calm"
        echo "3) Medium - focused"
        echo "4) Hard   - quick"
        echo
        read -rp "Choice (1-4): " choice
        choice=${choice:0:1}

        case "$choice" in
            1) delay=2.4; level_name="Easy"; return ;;
            2) delay=1.4; level_name="Normal"; return ;;
            3) delay=0.8; level_name="Medium"; return ;;
            4) delay=0.4; level_name="Hard"; return ;;
            *) echo "Use 1, 2, 3, or 4."; sleep 1 ;;
        esac
    done
}

show_start_screen() {
    local choice

    while true; do
        clear
        printf '\e[H'
        echo "Bash Tetris"
        echo
        show_top_players 100
        echo
        echo "Press Enter to choose speed."
        echo "Press P to reset local database."
        echo
        read -rp "Start screen: " choice
        choice=${choice:0:1}

        case "$choice" in
            "")
                return
                ;;
            p|P)
                reset_database_from_start_screen
                ;;
            *)
                return
                ;;
        esac
    done
}

reset_database_from_start_screen() {
    local confirm

    echo
    read -rp "Delete all local players and scores? (y/n): " confirm

    case "$confirm" in
        y|Y)
            rm -f -- "$db_path"
            init_db
            echo
            echo "Database deleted and recreated."
            echo
            show_top_players 100
            echo
            read -rp "Press Enter to continue..." _
            ;;
        *)
            echo
            echo "Database reset cancelled."
            read -rp "Press Enter to continue..." _
            ;;
    esac
}

start_terminal_game_mode() {
    stty -echo -icanon min 0 time 0 2>/dev/null || true
    tput civis 2>/dev/null || true
    printf '\e[?1049h'
    printf '\e[8;52;90t'
}

add_log() {
    local message="$1"

    logs+=("$message")
    while (( ${#logs[@]} > log_limit )); do
        logs=("${logs[@]:1}")
    done
}

reset_board() {
    board=()
    for ((i=0; i<rows*cols; i++)); do board[$i]="."; done
}

restart_game() {
    save_score
    reset_board
    score=0
    paused=0
    score_result=""
    logs=()
    add_log "Game restarted"
    new_piece
}

is_solid_cell() {
    local r=$1
    local c=$2

    if (( c < 0 || c >= cols || r >= rows )); then
        return 0
    fi

    if (( r < 0 )); then
        return 1
    fi

    [[ "${board[$((r * cols + c))]}" != "." ]]
}

easy_should_give_i_piece() {
    local r c depth has_block=0

    for ((r=0; r<rows; r++)); do
        for ((c=0; c<cols; c++)); do
            if [[ "${board[$((r * cols + c))]}" != "." ]]; then
                has_block=1
                break 2
            fi
        done
    done

    (( has_block )) || return 1

    for ((c=0; c<cols; c++)); do
        depth=0

        for ((r=rows-1; r>=0; r--)); do
            if [[ "${board[$((r * cols + c))]}" == "." ]] && is_solid_cell "$r" $((c - 1)) && is_solid_cell "$r" $((c + 1)); then
                depth=$((depth + 1))
                if (( depth >= 3 )); then
                    return 0
                fi
            else
                depth=0
            fi
        done
    done

    return 1
}

new_piece() {
    local index helped=0

    if [[ "$level_name" == "Easy" ]] && easy_should_give_i_piece; then
        index=0
        helped=1
    else
        index=$((RANDOM % ${#shapes[@]}))
    fi

    shape="${shapes[$index]}"
    current_piece_name="${shape_names[$index]}"
    px=3
    py=0
    if ! can_move "$px" "$py" "$shape"; then
        cleanup "Game over"
    fi

    if (( helped )); then
        add_log "Figure: $current_piece_name (Easy help)"
    else
        add_log "Figure: $current_piece_name"
    fi
}

rotate_piece() {
    local rotated=""
    local normalized=""
    local x y nx ny min_x=99 min_y=99 offset
    local offsets=(0 -1 1 -2 2 -3 3)

    for b in $shape; do
        x=${b%,*}
        y=${b#*,}
        nx=$((1 - y))
        ny=$x
        rotated+="$nx,$ny "
        (( nx < min_x )) && min_x=$nx
        (( ny < min_y )) && min_y=$ny
    done

    for b in $rotated; do
        x=${b%,*}
        y=${b#*,}
        normalized+="$((x - min_x)),$((y - min_y)) "
    done

    for offset in "${offsets[@]}"; do
        if can_move $((px + offset)) "$py" "$normalized"; then
            px=$((px + offset))
            shape="$normalized"
            return
        fi
    done
}

can_move() {
    local nx=$1
    local ny=$2
    local sh="$3"
    local x y bx by

    for b in $sh; do
        x=${b%,*}
        y=${b#*,}
        bx=$((nx + x))
        by=$((ny + y))

        if (( bx < 0 || bx >= cols || by < 0 || by >= rows )); then
            return 1
        fi

        if [[ "${board[$((by * cols + bx))]}" != "." ]]; then
            return 1
        fi
    done

    return 0
}

place_piece() {
    local x y bx by

    for b in $shape; do
        x=${b%,*}
        y=${b#*,}
        bx=$((px + x))
        by=$((py + y))
        board[$((by * cols + bx))]="$current_piece_name"
    done
}

advance_piece() {
    if can_move "$px" $((py + 1)) "$shape"; then
        py=$((py + 1))
    else
        place_piece
        clear_lines
        new_piece
    fi
}

clear_lines() {
    local r c rr full cleared=0 points=0

    for ((r=rows-1; r>=0; r--)); do
        full=1

        for ((c=0; c<cols; c++)); do
            if [[ "${board[$((r * cols + c))]}" == "." ]]; then
                full=0
                break
            fi
        done

        if (( full )); then
            for ((rr=r; rr>0; rr--)); do
                for ((c=0; c<cols; c++)); do
                    board[$((rr * cols + c))]="${board[$(((rr - 1) * cols + c))]}"
                done
            done

            for ((c=0; c<cols; c++)); do
                board[$c]="."
            done

            cleared=$((cleared + 1))
            r=$((r + 1))
        fi
    done

    case "$cleared" in
        1) points=1 ;;
        2) points=3 ;;
        3) points=6 ;;
        4) points=24 ;;
        5) points=120 ;;
    esac

    if (( points > 0 )); then
        score=$((score + points))
        if (( cleared == 1 )); then
            add_log "Cleared 1 line +$points point"
        else
            add_log "Cleared $cleared lines +$points points"
        fi
        save_score
    fi
}

draw_centered_line() {
    local line="$1"
    local width
    local pad

    width=$(tput cols 2>/dev/null || echo 80)
    pad=$(((width - ${#line}) / 2))
    (( pad < 0 )) && pad=0
    printf "%*s%s\n" "$pad" "" "$line"
}

center_text_in_width() {
    local text="$1"
    local width=$2
    local left right

    if (( ${#text} > width )); then
        text="${text:0:width}"
    fi

    left=$(((width - ${#text}) / 2))
    right=$((width - ${#text} - left))
    printf "%*s%s%*s" "$left" "" "$text" "$right" ""
}

panel_line() {
    local text="$1"
    local width=$2
    local inner=$((width - 4))

    if (( ${#text} > inner )); then
        text="${text:0:inner}"
    fi

    printf "| %-*s |" "$inner" "$text"
}

panel_border() {
    local width=$1
    local line="+"
    local i

    for ((i=0; i<width-2; i++)); do line+="-"; done
    line+="+"
    printf "%s" "$line"
}

draw_layout_line() {
    local left="$1"
    local right="$2"
    local total_width=$3
    local terminal_width
    local pad

    terminal_width=$(tput cols 2>/dev/null || echo 100)
    pad=$(((terminal_width - total_width) / 2))
    (( pad < 0 )) && pad=0
    printf "%*s%s    %s\n" "$pad" "" "$left" "$right"
}

render_cell() {
    local cell="$1"
    local reset=$'\e[0m'

    case "$cell" in
        ".") printf "    " ;;
        I) printf "\e[36m[][]%s" "$reset" ;;
        O) printf "\e[33m[][]%s" "$reset" ;;
        T) printf "\e[35m[][]%s" "$reset" ;;
        S) printf "\e[32m[][]%s" "$reset" ;;
        Z) printf "\e[31m[][]%s" "$reset" ;;
        J) printf "\e[34m[][]%s" "$reset" ;;
        L) printf "\e[37m[][]%s" "$reset" ;;
        *) printf "[][]" ;;
    esac
}

draw() {
    local r c h b x y cell line border header center_text pause_pad pause_line
    local left_width=38
    local board_width=$((cols * cell_width + 2))
    local total_width=$((left_width + 4 + board_width))
    local game_height=$((rows * cell_height + 3))
    local -a left_lines=()
    local -a game_lines=()
    local i log_start log_index log_text

    printf "\e[H\e[2J"
    for ((i=0; i<2; i++)); do printf "\n"; done

    if (( paused )); then
        header="Score: $score   Best: ${best_score:-0}   Speed: $level_name   PAUSED"
    else
        header="Score: $score   Best: ${best_score:-0}   Speed: $level_name   Q quit"
    fi
    border="+"
    for ((c=0; c<cols*cell_width; c++)); do border+="-"; done
    border+="+"

    game_lines+=("$(center_text_in_width "$header" "$board_width")")
    game_lines+=("$border")

    for ((r=0; r<rows; r++)); do
        if (( paused && r == rows / 2 )); then
            center_text=" PAUSE "
            pause_pad=$(((cols * cell_width - ${#center_text}) / 2))
            (( pause_pad < 0 )) && pause_pad=0
            pause_line="|"
            printf -v pause_line "%s%*s%s%*s|" "$pause_line" "$pause_pad" "" "$center_text" "$((cols * cell_width - pause_pad - ${#center_text}))" ""
            for ((h=0; h<cell_height; h++)); do
                game_lines+=("$pause_line")
            done
            continue
        fi

        line="|"

        for ((c=0; c<cols; c++)); do
            cell="${board[$((r * cols + c))]}"

            for b in $shape; do
                x=${b%,*}
                y=${b#*,}
                if (( px + x == c && py + y == r )); then
                    cell="$current_piece_name"
                fi
            done

            line+="$(render_cell "$cell")"
        done

        line+="|"
        for ((h=0; h<cell_height; h++)); do
            game_lines+=("$line")
        done
    done

    game_lines+=("$border")

    left_lines+=("$(panel_border "$left_width")")
    left_lines+=("$(panel_line "Controls" "$left_width")")
    left_lines+=("$(panel_border "$left_width")")
    left_lines+=("$(panel_line "S / Left  : move left" "$left_width")")
    left_lines+=("$(panel_line "F / Right : move right" "$left_width")")
    left_lines+=("$(panel_line "D / Up    : rotate" "$left_width")")
    left_lines+=("$(panel_line "Down      : move down" "$left_width")")
    left_lines+=("$(panel_line "Space     : pause / resume" "$left_width")")
    left_lines+=("$(panel_line "R         : restart" "$left_width")")
    left_lines+=("$(panel_line "Q         : quit" "$left_width")")
    left_lines+=("$(panel_border "$left_width")")
    left_lines+=("$(panel_line "Event log" "$left_width")")
    left_lines+=("$(panel_border "$left_width")")

    if (( ${#logs[@]} == 0 )); then
        left_lines+=("$(panel_line "No events yet." "$left_width")")
    else
        log_start=0
        if (( ${#logs[@]} > log_limit )); then
            log_start=$((${#logs[@]} - log_limit))
        fi
        for ((log_index=log_start; log_index<${#logs[@]}; log_index++)); do
            log_text="${logs[$log_index]}"
            left_lines+=("$(panel_line "$log_text" "$left_width")")
        done
    fi

    while (( ${#left_lines[@]} < game_height - 1 )); do
        left_lines+=("$(panel_line "" "$left_width")")
    done
    left_lines+=("$(panel_border "$left_width")")

    for ((i=0; i<game_height; i++)); do
        draw_layout_line "${left_lines[$i]}" "${game_lines[$i]}" "$total_width"
    done
}

read_key() {
    key=""
    IFS= read -rsn1 -t "$delay" key || true

    if [[ "$key" == $'\e' ]]; then
        IFS= read -rsn2 -t 0.01 rest || true
        key+="$rest"
    fi
}

handle_input() {
    case "$key" in
        " ")
            if (( paused )); then
                paused=0
                add_log "Pause off"
            else
                paused=1
                add_log "Pause on"
            fi
            ;;
        s|S|$'\e[D')
            (( paused )) && return
            if can_move $((px - 1)) "$py" "$shape"; then
                px=$((px - 1))
            fi
            ;;
        f|F|$'\e[C')
            (( paused )) && return
            if can_move $((px + 1)) "$py" "$shape"; then
                px=$((px + 1))
            fi
            ;;
        $'\e[B')
            (( paused )) && return
            if can_move "$px" $((py + 1)) "$shape"; then
                py=$((py + 1))
            fi
            ;;
        d|D|$'\e[A')
            (( paused )) && return
            rotate_piece
            ;;
        r|R)
            restart_game
            ;;
        q|Q)
            cleanup "Quit"
            ;;
    esac
}

init_db
show_start_screen
choose_speed
login_player
start_terminal_game_mode
new_piece

while (( running )); do
    draw
    read_key
    handle_input

    if (( paused )); then
        continue
    fi

    advance_piece
done
