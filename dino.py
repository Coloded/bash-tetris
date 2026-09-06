#!/usr/bin/env python3
"""Terminal runner; only Python's standard library is required."""

import curses
from dataclasses import dataclass
import random
import time

STEP_MS = 20
MAX_SPEED = 20000
MIN_GAP = 40000
HEROES = {
    '1': ('Human', (' oo ', '/||\\', '/  \\'), '_oo_'),
    '2': ('Dog', ('/\\/\\', ' oo>', '/__\\'), '_o_>'),
    '3': ('Cockroach', ('\\  /', '(oo)', '/||\\'), '_oo_'),
}


@dataclass
class Obstacle:
    x: int  # thousandths of a cell
    kind: int


class Runner:
    def __init__(self, hero='1'):
        self.hero = hero
        self.best = 0
        self.width, self.height = 77, 19
        self.reset()

    def reset(self):
        self.score = self.sim_ms = self.steps = 0
        self.game_over = self.ducking = self.jump_locked = False
        self.duck_until = 0
        self.last_jump = -1000
        self.altitude = self.velocity = 0
        self.speed = 12000
        self.obstacles = []
        self.to_spawn = 15000
        self.next_step = time.monotonic() + STEP_MS / 1000

    @property
    def ground(self):
        return self.height - 2

    @property
    def feet(self):
        return self.ground - (self.altitude + 500) // 1000

    def jump(self):
        if self.altitude == 0 and not self.jump_locked:
            self.velocity = -20000
            self.ducking = False
            self.duck_until = 0
            self.jump_locked = True
        self.last_jump = self.sim_ms

    def handle_key(self, key):
        if key in (ord('q'), ord('Q')):
            return False
        if key in (ord('r'), ord('R')):
            self.reset()
        elif not self.game_over:
            if key in (ord(' '), curses.KEY_UP):
                self.jump()
            elif key == curses.KEY_DOWN and self.altitude == 0:
                self.duck_until = self.sim_ms + 700
                self.ducking = True
        return True

    def spawn(self):
        if self.score >= 150 and random.randrange(5) == 0:
            kind = 3
        else:
            kind = 2 if random.randrange(3) == 0 else 1
        x = (self.width + 3) * 1000
        if self.obstacles:
            x = max(x, self.obstacles[-1].x + MIN_GAP)
        self.obstacles.append(Obstacle(x, kind))
        # One-second flight + recovery and collision-box widths at max speed.
        self.to_spawn = MIN_GAP + random.randrange(12001)

    def collision(self):
        top = self.feet if self.ducking and self.altitude == 0 else self.feet - 2
        for obstacle in self.obstacles:
            x = obstacle.x // 1000
            right = x + (0 if obstacle.kind == 1 else 1 if obstacle.kind == 2 else 2)
            ob_top = self.ground - (1 if obstacle.kind == 1 else 2)
            bottom = self.ground - (1 if obstacle.kind == 3 else 0)
            if 8 <= right and 11 >= x and top <= bottom and self.feet >= ob_top:
                return True
        return False

    def step(self):
        self.sim_ms += STEP_MS
        if self.altitude > 0 or self.velocity < 0:
            self.altitude -= self.velocity * STEP_MS // 1000 + 40000 * STEP_MS**2 // 2000000
            self.velocity += 40000 * STEP_MS // 1000
            if self.altitude <= 0:
                self.altitude = self.velocity = 0
        self.ducking = self.altitude == 0 and self.sim_ms < self.duck_until
        if self.altitude == 0 and self.sim_ms - self.last_jump >= 200:
            self.jump_locked = False
        self.speed = min(MAX_SPEED, 12000 + self.steps * 8000 // 3000)
        distance = self.speed * STEP_MS // 1000
        for obstacle in self.obstacles:
            obstacle.x -= distance
        self.obstacles = [o for o in self.obstacles if o.x > -5000]
        self.to_spawn -= distance
        if self.to_spawn <= 0:
            self.spawn()
        self.steps += 1
        self.score = self.sim_ms // 100
        self.best = max(self.best, self.score)
        self.game_over = self.collision()

    def tick(self, now):
        if now - self.next_step > .25:
            self.next_step = now
        while not self.game_over and now + 1e-9 >= self.next_step:
            self.step()
            self.next_step += STEP_MS / 1000

    def resize(self, rows, cols):
        self.width = min(100, cols - 3)
        self.height = min(20, rows - 5)
        return rows >= 16 and cols >= 52

    def render_rows(self):
        rows = [[' '] * self.width for _ in range(self.height)]

        def put(y, x, text):
            if 0 <= y < self.height:
                for offset, char in enumerate(text):
                    if 0 <= x + offset < self.width:
                        rows[y][x + offset] = char

        put(self.ground + 1, 0, '_' * self.width)
        for obstacle in self.obstacles:
            x = obstacle.x // 1000
            if obstacle.kind == 3:
                put(self.ground - 2, x, '<=>')
                put(self.ground - 1, x, ' v ')
            else:
                for y in range(self.ground - obstacle.kind, self.ground + 1):
                    put(y, x, '#' * obstacle.kind)
        _, sprite, duck = HEROES[self.hero]
        if self.ducking and self.altitude == 0:
            put(self.ground, 8, duck)
        else:
            for offset, line in enumerate(sprite):
                put(self.feet - 2 + offset, 8, line)
        return [''.join(row) for row in rows]


def write(screen, y, x, text):
    rows, cols = screen.getmaxyx()
    if not (0 <= y < rows and 0 <= x < cols):
        return
    try:
        screen.addstr(y, x, text[:max(0, cols - x - 1)])
    except curses.error:
        pass


def run(screen):
    curses.curs_set(0)
    screen.keypad(True)
    screen.timeout(100)
    while True:
        screen.erase()
        for y, line in enumerate(('Choose runner:', '1) Human', '2) Dog',
                                  '3) Cockroach', 'Same size, jump and speed for all.',
                                  'Choice (1-3), Q: quit')):
            write(screen, y, 0, line)
        screen.refresh()
        key = screen.getch()
        if key in (ord('q'), ord('Q')):
            return 0, 0
        if key in (ord('1'), ord('2'), ord('3')):
            game = Runner(chr(key))
            break
    screen.nodelay(True)
    while True:
        start = time.monotonic()
        key = screen.getch()
        fits = game.resize(*screen.getmaxyx())
        if key in (ord('q'), ord('Q')):
            break
        screen.erase()
        if fits:
            game.handle_key(key)
            game.tick(time.monotonic())
            write(screen, 0, 0, f'{HEROES[game.hero][0]} Score:{game.score} Best:{game.best} Speed:{game.speed / 1000:.1f}')
            write(screen, 1, 0, '+' + '-' * game.width + '+')
            for y, row in enumerate(game.render_rows(), 2):
                write(screen, y, 0, '|' + row + '|')
            write(screen, game.height + 2, 0, '+' + '-' * game.width + '+')
            footer = 'GAME OVER - R: restart  Q: quit' if game.game_over else 'Up/Space: jump  Down: duck  R: restart  Q: quit'
            write(screen, game.height + 3, 0, footer)
        else:
            game.next_step = time.monotonic() + STEP_MS / 1000
            write(screen, 0, 0, 'Paused: enlarge terminal to 52x16. Q: quit')
        screen.refresh()
        time.sleep(max(0, 1 / 50 - (time.monotonic() - start)))
    return game.score, game.best


if __name__ == '__main__':
    try:
        score, best = curses.wrapper(run)
        print(f'Runner stopped. Score: {score} Best: {best}')
    except KeyboardInterrupt:
        print('Interrupted.')
