#!/usr/bin/env python3

import curses
import random
import re
import sqlite3
import time
from pathlib import Path


ROWS = 20
COLS = 10
CELL = "[]"
DB_PATH = Path(__file__).with_name("tetris_scores.sqlite3")

SHAPES = {
    "I": [(0, 0), (0, 1), (0, 2), (0, 3), (0, 4)],
    "O": [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2)],
    "T": [(0, 0), (1, 0), (2, 0), (1, 1), (1, 2)],
    "S": [(0, 0), (1, 0), (1, 1), (2, 1)],
    "Z": [(1, 0), (2, 0), (0, 1), (1, 1)],
    "J": [(1, 0), (1, 1), (0, 2), (1, 2)],
    "L": [(0, 0), (0, 1), (0, 2), (1, 2)],
}

SCORES = {1: 1, 2: 3, 3: 6, 4: 24, 5: 120}
SPEEDS = {
    "1": ("Easy", 2.4),
    "2": ("Normal", 1.4),
    "3": ("Medium", 0.8),
    "4": ("Hard", 0.4),
}
PIECE_COLORS = {"I": 1, "O": 2, "T": 3, "S": 4, "Z": 5, "J": 6, "L": 7}


class UserExit(Exception):
    pass


def safe_addstr(stdscr, y, x, text, attr=0):
    try:
        stdscr.addstr(y, x, text, attr)
    except curses.error:
        pass


def init_db():
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS players (
                name TEXT PRIMARY KEY,
                pin TEXT NOT NULL,
                score INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """
        )


def top_players(limit=100):
    with sqlite3.connect(DB_PATH) as conn:
        return conn.execute(
            """
            SELECT name, score
            FROM players
            ORDER BY score DESC, updated_at ASC, name ASC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()


def get_player(name):
    with sqlite3.connect(DB_PATH) as conn:
        return conn.execute("SELECT pin, score FROM players WHERE name = ?", (name,)).fetchone()


def create_player(name, pin):
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("INSERT INTO players (name, pin, score) VALUES (?, ?, 0)", (name, pin))


def update_best(name, score):
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute(
            "UPDATE players SET score = ?, updated_at = CURRENT_TIMESTAMP WHERE name = ?",
            (score, name),
        )


def reset_database():
    DB_PATH.unlink(missing_ok=True)
    init_db()


def prompt(stdscr, y, x, label, hidden=False):
    chars = []

    def redraw():
        value = "*" * len(chars) if hidden else "".join(chars)
        stdscr.move(y, x)
        stdscr.clrtoeol()
        safe_addstr(stdscr, y, x, label + value)
        stdscr.move(y, x + len(label) + len(value))
        stdscr.refresh()

    try:
        curses.curs_set(1)
        curses.noecho()
        stdscr.nodelay(False)
        redraw()

        while True:
            ch = stdscr.getch()
            if ch in (10, 13):
                break
            if ch in (27,):
                chars = []
                break
            if ch in (curses.KEY_BACKSPACE, 127, 8):
                if chars:
                    chars.pop()
                    redraw()
                continue
            if 32 <= ch <= 126:
                chars.append(chr(ch))
                redraw()
    except KeyboardInterrupt as exc:
        raise UserExit from exc
    finally:
        curses.noecho()
        try:
            curses.curs_set(0)
        except curses.error:
            pass
        stdscr.nodelay(True)
    return "".join(chars)


def draw_start(stdscr):
    stdscr.nodelay(False)
    try:
        while True:
            stdscr.clear()
            safe_addstr(stdscr, 1, 2, "Bash Tetris")
            safe_addstr(stdscr, 3, 2, "Top 100 players by best score:")
            rows = top_players()
            if rows:
                for i, (name, score) in enumerate(rows[:18], start=1):
                    safe_addstr(stdscr, 4 + i, 2, f"{i:>3}. {name:<20} {score}")
            else:
                safe_addstr(stdscr, 5, 2, "No players yet.")
            safe_addstr(stdscr, 25, 2, "Enter: choose speed")
            safe_addstr(stdscr, 26, 2, "P: reset local database")
            stdscr.refresh()
            ch = stdscr.getch()
            if ch in (10, 13):
                return
            if ch in (ord("p"), ord("P")):
                answer = prompt(stdscr, 28, 2, "Delete all local players and scores? (y/n): ")
                if answer[:1].lower() == "y":
                    reset_database()
                    safe_addstr(stdscr, 30, 2, "Database deleted and recreated. Top is empty now.")
                else:
                    safe_addstr(stdscr, 30, 2, "Database reset cancelled.")
                safe_addstr(stdscr, 31, 2, "Press any key...")
                stdscr.getch()
    except KeyboardInterrupt as exc:
        raise UserExit from exc


def choose_speed(stdscr):
    stdscr.nodelay(False)
    try:
        while True:
            stdscr.clear()
            safe_addstr(stdscr, 1, 2, "Select speed:")
            safe_addstr(stdscr, 3, 2, "1) Easy   - very calm")
            safe_addstr(stdscr, 4, 2, "2) Normal - calm")
            safe_addstr(stdscr, 5, 2, "3) Medium - focused")
            safe_addstr(stdscr, 6, 2, "4) Hard   - quick")
            stdscr.refresh()
            ch = stdscr.getch()
            key = chr(ch) if 0 <= ch < 256 else ""
            if key in SPEEDS:
                return SPEEDS[key]
    except KeyboardInterrupt as exc:
        raise UserExit from exc


def login(stdscr):
    name_re = re.compile(r"^[A-Za-z0-9]+$")
    while True:
        stdscr.clear()
        stdscr.addstr(1, 2, "Player login")
        name = prompt(stdscr, 3, 2, "Player name (A-Z, a-z, 0-9): ")
        if not name_re.match(name):
            stdscr.addstr(5, 2, "Use only English letters and digits. Press any key...")
            stdscr.getch()
            continue
        existing = get_player(name)
        if existing:
            pin = prompt(stdscr, 5, 2, f"PIN for {name}: ", hidden=True)
            if pin == existing[0]:
                return name, existing[1]
            stdscr.addstr(7, 2, "Wrong PIN. Use another name or try again. Press any key...")
            stdscr.getch()
            continue
        pin = prompt(stdscr, 5, 2, f"Create PIN for {name} (A-Z, a-z, 0-9): ", hidden=True)
        if not name_re.match(pin):
            stdscr.addstr(7, 2, "PIN can contain only English letters and digits. Press any key...")
            stdscr.getch()
            continue
        create_player(name, pin)
        return name, 0


class Game:
    def __init__(self, stdscr, player, best, level, fall_delay):
        self.stdscr = stdscr
        self.player = player
        self.best = best
        self.level = level
        self.fall_delay = fall_delay
        self.board = [["." for _ in range(COLS)] for _ in range(ROWS)]
        self.score = 0
        self.logs = []
        self.paused = False
        self.last_fall = time.monotonic()
        self.piece_name = ""
        self.shape = []
        self.px = 3
        self.py = 0
        self.new_piece()

    def log(self, message):
        self.logs.append(message)
        self.logs = self.logs[-28:]

    def reset(self):
        self.save_best()
        self.board = [["." for _ in range(COLS)] for _ in range(ROWS)]
        self.score = 0
        self.paused = False
        self.logs = ["Game restarted"]
        self.new_piece()

    def save_best(self):
        if self.score > self.best:
            old = self.best
            self.best = self.score
            update_best(self.player, self.best)
            self.log(f"New best score saved: {self.best}")
            return f"New record saved! Previous best: {old}"
        return "Record unchanged."

    def occupied(self):
        return {(self.px + x, self.py + y) for x, y in self.shape}

    def can_place(self, px, py, shape):
        for x, y in shape:
            bx, by = px + x, py + y
            if bx < 0 or bx >= COLS or by < 0 or by >= ROWS:
                return False
            if self.board[by][bx] != ".":
                return False
        return True

    def is_solid(self, r, c):
        if c < 0 or c >= COLS or r >= ROWS:
            return True
        if r < 0:
            return False
        return self.board[r][c] != "."

    def easy_wants_i(self):
        if self.level != "Easy" or not any(cell != "." for row in self.board for cell in row):
            return False
        for c in range(COLS):
            depth = 0
            for r in range(ROWS - 1, -1, -1):
                if self.board[r][c] == "." and self.is_solid(r, c - 1) and self.is_solid(r, c + 1):
                    depth += 1
                    if depth >= 3:
                        return True
                else:
                    depth = 0
        return False

    def new_piece(self):
        names = list(SHAPES)
        self.piece_name = "I" if self.easy_wants_i() else random.choice(names)
        self.shape = SHAPES[self.piece_name][:]
        self.px = 3
        self.py = 0
        self.last_fall = time.monotonic()
        if not self.can_place(self.px, self.py, self.shape):
            raise RuntimeError("game over")
        suffix = " (Easy help)" if self.level == "Easy" and self.piece_name == "I" and self.easy_wants_i() else ""
        self.log(f"Figure: {self.piece_name}{suffix}")

    def rotate(self):
        rotated = [(1 - y, x) for x, y in self.shape]
        min_x = min(x for x, _ in rotated)
        min_y = min(y for _, y in rotated)
        rotated = [(x - min_x, y - min_y) for x, y in rotated]
        for offset in (0, -1, 1, -2, 2, -3, 3):
            if self.can_place(self.px + offset, self.py, rotated):
                self.px += offset
                self.shape = rotated
                return

    def advance(self):
        if self.can_place(self.px, self.py + 1, self.shape):
            self.py += 1
            return
        for x, y in self.shape:
            self.board[self.py + y][self.px + x] = self.piece_name
        self.clear_lines()
        self.new_piece()

    def clear_lines(self):
        new_board = [row for row in self.board if any(cell == "." for cell in row)]
        cleared = ROWS - len(new_board)
        if cleared:
            self.board = [["." for _ in range(COLS)] for _ in range(cleared)] + new_board
            points = SCORES.get(cleared, 0)
            self.score += points
            word = "line" if cleared == 1 else "lines"
            point_word = "point" if points == 1 else "points"
            self.log(f"Cleared {cleared} {word} +{points} {point_word}")
            self.save_best()

    def handle_key(self, ch):
        if ch in (ord("q"), ord("Q")):
            return False
        if ch == ord(" "):
            self.paused = not self.paused
            self.log("Pause on" if self.paused else "Pause off")
            return True
        if ch in (ord("r"), ord("R")):
            self.reset()
            return True
        if self.paused:
            return True
        if ch in (ord("s"), ord("S"), curses.KEY_LEFT) and self.can_place(self.px - 1, self.py, self.shape):
            self.px -= 1
        elif ch in (ord("f"), ord("F"), curses.KEY_RIGHT) and self.can_place(self.px + 1, self.py, self.shape):
            self.px += 1
        elif ch == curses.KEY_DOWN and self.can_place(self.px, self.py + 1, self.shape):
            self.py += 1
            self.last_fall = time.monotonic()
        elif ch in (ord("d"), ord("D"), curses.KEY_UP):
            self.rotate()
        return True

    def tick(self):
        if not self.paused and time.monotonic() - self.last_fall >= self.fall_delay:
            self.last_fall = time.monotonic()
            self.advance()

    def draw_cell(self, y, x, piece):
        if piece == ".":
            safe_addstr(self.stdscr, y, x, "  ")
            return
        color = curses.color_pair(PIECE_COLORS[piece])
        safe_addstr(self.stdscr, y, x, CELL, color)

    def draw(self):
        s = self.stdscr
        s.erase()
        safe_addstr(s, 1, 2, "+------------------------------------+")
        safe_addstr(s, 2, 2, "| Controls                           |")
        safe_addstr(s, 3, 2, "+------------------------------------+")
        controls = [
            "S / Left  : move left",
            "F / Right : move right",
            "D / Up    : rotate",
            "Down      : move down",
            "Space     : pause / resume",
            "R         : restart",
            "Q         : quit",
        ]
        for i, text in enumerate(controls, 4):
            safe_addstr(s, i, 2, f"| {text:<34} |")
        safe_addstr(s, 11, 2, "+------------------------------------+")
        safe_addstr(s, 12, 2, "| Event log                          |")
        safe_addstr(s, 13, 2, "+------------------------------------+")
        for i in range(28):
            text = self.logs[i] if i < len(self.logs) else ""
            safe_addstr(s, 14 + i, 2, f"| {text[:34]:<34} |")
        safe_addstr(s, 42, 2, "+------------------------------------+")

        ox, oy = 44, 1
        state = "PAUSED" if self.paused else "Q quit"
        safe_addstr(s, oy, ox, f"Score: {self.score}   Best: {self.best}   Speed: {self.level}   {state}")
        safe_addstr(s, oy + 1, ox, "+" + "-" * (COLS * 2) + "+")
        active = self.occupied()
        for r in range(ROWS):
            safe_addstr(s, oy + 2 + r, ox, "|")
            for c in range(COLS):
                piece = self.piece_name if (c, r) in active else self.board[r][c]
                self.draw_cell(oy + 2 + r, ox + 1 + c * 2, piece)
            safe_addstr(s, oy + 2 + r, ox + 1 + COLS * 2, "|")
        if self.paused:
            safe_addstr(s, oy + 11, ox + 8, "PAUSE", curses.A_REVERSE)
        safe_addstr(s, oy + 2 + ROWS, ox, "+" + "-" * (COLS * 2) + "+")
        s.refresh()


def init_colors():
    curses.start_color()
    curses.use_default_colors()
    pairs = [
        (curses.COLOR_CYAN, -1),
        (curses.COLOR_YELLOW, -1),
        (curses.COLOR_MAGENTA, -1),
        (curses.COLOR_GREEN, -1),
        (curses.COLOR_RED, -1),
        (curses.COLOR_BLUE, -1),
        (curses.COLOR_WHITE, -1),
    ]
    for i, (fg, bg) in enumerate(pairs, start=1):
        curses.init_pair(i, fg, bg)


def run(stdscr):
    try:
        random.seed()
        curses.curs_set(0)
        stdscr.keypad(True)
        stdscr.nodelay(True)
        stdscr.timeout(30)
        init_colors()
        init_db()
        draw_start(stdscr)
        level, delay = choose_speed(stdscr)
        player, best = login(stdscr)
        stdscr.nodelay(True)
        game = Game(stdscr, player, best, level, delay)
    except (KeyboardInterrupt, UserExit):
        return "Interrupted.", 0, "", 0, ""

    result = "Quit."
    try:
        running = True
        while running:
            ch = stdscr.getch()
            if ch != -1:
                running = game.handle_key(ch)
            game.tick()
            game.draw()
    except RuntimeError:
        result = "Game over."
    except (KeyboardInterrupt, UserExit):
        result = "Interrupted."

    save_message = game.save_best()
    return result, game.score, player, game.best, save_message


if __name__ == "__main__":
    try:
        result, score, player, best, save_message = curses.wrapper(run)
        print(f"{result} Score: {score}")
        if player:
            print(f"Player: {player}. Best score: {best}")
        if save_message:
            print(save_message)
    except KeyboardInterrupt:
        print("Interrupted.")
