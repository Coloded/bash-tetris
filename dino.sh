#!/usr/bin/env bash

score=0
best=0
speed_level=1
frame_delay=0.09
min_delay=0.035
tick=0
game_over=0
ducking=0
duck_ticks=0
jump_locked=0
jump_release_ticks=0
hero_type=1
hero_name="Human"
hero_height=3
hero_width=3
human_height=3

obs_x=()
obs_type=()

cleanup() {
    stty echo 2>/dev/null
    tput cnorm 2>/dev/null
    printf "\e[?1049l"
    clear
    echo "Runner stopped. Score: $score Best: $best"
    exit
}

trap cleanup INT TERM

repeat_char() {
    local count=$1
    local char=$2
    local out=""

    while (( count > 0 )); do
        out+="$char"
        count=$((count - 1))
    done

    printf "%s" "$out"
}

fit_screen() {
    term_cols=$(tput cols 2>/dev/null || echo 80)
    term_rows=$(tput lines 2>/dev/null || echo 24)

    game_w=$((term_cols - 6))
    game_h=$((term_rows - 7))

    if (( game_w > 100 )); then game_w=100; fi
    if (( game_h > 24 )); then game_h=24; fi
    if (( game_w < 50 )); then game_w=50; fi
    if (( game_h < 14 )); then game_h=14; fi

    ground_y=$((game_h - 3))
    dino_x=8
}

draw_menu() {
    printf "\e[H"
    clear
    echo "Choose runner:"
    echo
    echo "1) Human"
    echo "     o"
    echo "    /|\\"
    echo "    / \\"
    echo
    echo "2) Dog"
    echo "    /o_"
    echo "   /_\\\\"
    echo
    echo "3) Cockroach"
    echo "   /oo\\"
    echo
    echo "Q) quit"
    echo
    echo -n "Choice (1-3): "
}

choose_runner() {
    local choice

    while true; do
        draw_menu
        IFS= read -rsn1 choice

        case "$choice" in
            1)
                hero_type=1
                hero_name="Human"
                hero_height=3
                hero_width=3
                return
                ;;
            2)
                hero_type=2
                hero_name="Dog"
                hero_height=2
                hero_width=4
                return
                ;;
            3)
                hero_type=3
                hero_name="Cockroach"
                hero_height=1
                hero_width=4
                return
                ;;
            q|Q)
                cleanup
                ;;
        esac
    done
}

reset_game() {
    score=0
    speed_level=1
    frame_delay=0.09
    tick=0
    game_over=0
    ducking=0
    duck_ticks=0
    jump_locked=0
    jump_release_ticks=0
    dino_y=$ground_y
    jump_v=0
    max_jump_y=$((ground_y - human_height * 3))
    if (( max_jump_y < 1 )); then
        max_jump_y=1
    fi
    obs_x=()
    obs_type=()
    next_spawn=$((18 + RANDOM % 14))
}

start_jump() {
    if (( dino_y == ground_y && ! jump_locked )); then
        jump_v=-4
        ducking=0
        duck_ticks=0
        jump_locked=1
        jump_release_ticks=0
    fi
}

spawn_obstacle() {
    local kind

    if (( score > 150 && RANDOM % 5 == 0 )); then
        kind=3
    elif (( RANDOM % 3 == 0 )); then
        kind=2
    else
        kind=1
    fi

    obs_x+=("$((game_w - 4))")
    obs_type+=("$kind")
}

obstacle_bounds() {
    local type=$1
    local x=$2

    case "$type" in
        1) ob_left=$x; ob_right=$x; ob_top=$((ground_y - 1)); ob_bottom=$ground_y ;;
        2) ob_left=$x; ob_right=$((x + 1)); ob_top=$((ground_y - 2)); ob_bottom=$ground_y ;;
        3) ob_left=$x; ob_right=$((x + 2)); ob_top=$((ground_y - 4)); ob_bottom=$((ground_y - 3)) ;;
    esac
}

dino_bounds() {
    if (( ducking && dino_y == ground_y )); then
        di_left=$dino_x
        di_right=$((dino_x + hero_width - 1))
        if (( hero_type == 1 )); then
            di_top=$((ground_y - 1))
        else
            di_top=$ground_y
        fi
        di_bottom=$ground_y
    else
        di_left=$dino_x
        di_right=$((dino_x + hero_width - 1))
        di_top=$((dino_y - hero_height + 1))
        di_bottom=$dino_y
    fi
}

check_collision() {
    local i

    dino_bounds
    for ((i=0; i<${#obs_x[@]}; i++)); do
        obstacle_bounds "${obs_type[$i]}" "${obs_x[$i]}"

        if (( di_left <= ob_right && di_right >= ob_left && di_top <= ob_bottom && di_bottom >= ob_top )); then
            return 0
        fi
    done

    return 1
}

update_game() {
    local i
    local new_x=()
    local new_type=()

    if (( dino_y < ground_y || jump_v != 0 )); then
        dino_y=$((dino_y + jump_v))
        jump_v=$((jump_v + 1))

        if (( dino_y < max_jump_y )); then
            dino_y=$max_jump_y
            jump_v=1
        fi

        if (( dino_y > ground_y )); then
            dino_y=$ground_y
            jump_v=0
        fi
    fi

    for ((i=0; i<${#obs_x[@]}; i++)); do
        obs_x[$i]=$((obs_x[$i] - speed_level))
        if (( obs_x[$i] > -5 )); then
            new_x+=("${obs_x[$i]}")
            new_type+=("${obs_type[$i]}")
        fi
    done
    obs_x=("${new_x[@]}")
    obs_type=("${new_type[@]}")

    next_spawn=$((next_spawn - speed_level))
    if (( next_spawn <= 0 )); then
        spawn_obstacle
        next_spawn=$((18 + RANDOM % 18))
        if (( speed_level > 1 )); then
            next_spawn=$((next_spawn + 8))
        fi
    fi

    score=$((score + 1))
    if (( score > best )); then
        best=$score
    fi

    if (( score > 0 && score % 180 == 0 && speed_level < 4 )); then
        speed_level=$((speed_level + 1))
    fi

    if check_collision; then
        game_over=1
    fi
}

cell_at() {
    local r=$1
    local c=$2
    local i type x

    if (( r == ground_y + 1 )); then
        printf "_"
        return
    fi

    hero_cell_at "$r" "$c" && return

    for ((i=0; i<${#obs_x[@]}; i++)); do
        type=${obs_type[$i]}
        x=${obs_x[$i]}

        if (( type == 1 )); then
            if (( c == x && r >= ground_y - 1 && r <= ground_y )); then printf "#"; return; fi
        elif (( type == 2 )); then
            if (( c >= x && c <= x + 1 && r >= ground_y - 2 && r <= ground_y )); then printf "#"; return; fi
        else
            if (( r == ground_y - 4 && c >= x && c <= x + 2 )); then printf "<"; return; fi
            if (( r == ground_y - 3 && c >= x && c <= x + 2 )); then printf "="; return; fi
        fi
    done

    if (( r == ground_y && c % 11 == tick % 11 )); then
        printf "."
    else
        printf " "
    fi
}

hero_cell_at() {
    local r=$1
    local c=$2
    local dx=$((c - dino_x))

    if (( dx < 0 || dx >= hero_width )); then
        return 1
    fi

    if (( ducking && dino_y == ground_y )); then
        case "$hero_type" in
            1)
                if (( r == ground_y - 1 )); then
                    case "$dx" in 0) printf "_" ;; 1) printf "o" ;; 2) printf "_" ;; esac
                    return 0
                fi
                if (( r == ground_y )); then
                    case "$dx" in 0) printf "/" ;; 1) printf "_" ;; 2) printf "\\" ;; esac
                    return 0
                fi
                ;;
            2)
                if (( r == ground_y )); then
                    case "$dx" in 0) printf "_" ;; 1) printf "o" ;; 2) printf "_" ;; 3) printf ">" ;; esac
                    return 0
                fi
                ;;
            3)
                if (( r == ground_y )); then
                    case "$dx" in 0) printf "_" ;; 1) printf "o" ;; 2) printf "o" ;; 3) printf "_" ;; esac
                    return 0
                fi
                ;;
        esac
    else
        case "$hero_type" in
            1)
                if (( r == dino_y - 2 && dx == 1 )); then printf "o"; return 0; fi
                if (( r == dino_y - 1 )); then
                    case "$dx" in 0) printf "/" ;; 1) printf "|" ;; 2) printf "\\" ;; esac
                    return 0
                fi
                if (( r == dino_y )); then
                    case "$dx" in 0) printf "/" ;; 1) printf " " ;; 2) printf "\\" ;; esac
                    return 0
                fi
                ;;
            2)
                if (( r == dino_y - 1 )); then
                    case "$dx" in 0) printf "/" ;; 1) printf "o" ;; 2) printf "_" ;; 3) printf " " ;; esac
                    return 0
                fi
                if (( r == dino_y )); then
                    case "$dx" in 0) printf "/" ;; 1) printf "_" ;; 2) printf "\\" ;; 3) printf "\\" ;; esac
                    return 0
                fi
                ;;
            3)
                if (( r == dino_y )); then
                    case "$dx" in 0) printf "/" ;; 1) printf "o" ;; 2) printf "o" ;; 3) printf "\\" ;; esac
                    return 0
                fi
                ;;
        esac
    fi

    return 1
}

draw() {
    local r c

    printf "\e[H"
    printf "Runner: %-9s Score: %-6s Best: %-6s Speed: %-2s  Up/Space jump | Down duck | R restart | Q quit\n" "$hero_name" "$score" "$best" "$speed_level"
    printf "+"
    repeat_char "$game_w" "-"
    printf "+\n"

    for ((r=0; r<game_h; r++)); do
        printf "|"
        for ((c=0; c<game_w; c++)); do
            cell_at "$r" "$c"
        done
        printf "|\n"
    done

    printf "+"
    repeat_char "$game_w" "-"
    printf "+\n"

    if (( game_over )); then
        printf "GAME OVER. Press R to restart or Q to quit.                    \n"
    else
        printf "Jump over cacti. Duck under birds.                             \n"
    fi
}

read_key() {
    key=""
    rest=""

    IFS= read -rsn1 -t "$frame_delay" key
    if [[ "$key" == $'\e' ]]; then
        IFS= read -rsn2 -t 0.001 rest
        key+="$rest"
    fi
}

is_jump_key() {
    [[ "$key" == " " || "$key" == $'\e[A' ]]
}

handle_key() {
    case "$key" in
        " "|$'\e[A')
            if (( ! game_over )); then start_jump; fi
            ;;
        $'\e[B')
            if (( ! game_over && dino_y == ground_y )); then duck_ticks=6; fi
            ;;
        r|R)
            reset_game
            ;;
        q|Q)
            cleanup
            ;;
    esac
}

update_ducking() {
    if (( dino_y == ground_y && duck_ticks > 0 )); then
        ducking=1
        duck_ticks=$((duck_ticks - 1))
    else
        ducking=0
        duck_ticks=0
    fi
}

update_jump_lock() {
    if (( ! jump_locked )); then
        return
    fi

    if (( dino_y != ground_y )); then
        jump_release_ticks=0
        return
    fi

    if is_jump_key; then
        jump_release_ticks=0
    else
        jump_release_ticks=$((jump_release_ticks + 1))
        if (( jump_release_ticks >= 2 )); then
            jump_locked=0
            jump_release_ticks=0
        fi
    fi
}

main() {
    printf "\e[?1049h"
    stty -echo 2>/dev/null
    tput civis 2>/dev/null
    clear

    fit_screen
    choose_runner
    reset_game
    draw

    while true; do
        read_key
        handle_key
        update_ducking

        if (( ! game_over )); then
            update_game
            update_jump_lock
            tick=$((tick + 1))

            case "$speed_level" in
                1) frame_delay=0.09 ;;
                2) frame_delay=0.075 ;;
                3) frame_delay=0.06 ;;
                *) frame_delay=$min_delay ;;
            esac
        fi

        draw
    done
}

main
